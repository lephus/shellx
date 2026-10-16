import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../browser/browser_engine.dart';
import 'tool_entry.dart';

/// D13: reloads after a refused connection — 1, 2, 4, 8 s, then every 10 s.
Duration toolRetryDelay(int attempt) =>
    attempt < 4 ? Duration(seconds: 1 << attempt) : const Duration(seconds: 10);

/// Ruling R9: between D13's reloads, a local tool's port is knocked on once
/// a second, so the page shows within about a second of its server coming
/// up (criterion 5), whatever the reload schedule has reached.
const Duration kToolKnockEvery = Duration(seconds: 1);

/// Whether something accepts a TCP connection on [host]:[port] now. Sends
/// nothing; never logs the host.
typedef ToolKnock = Future<bool> Function(String host, int port);

Future<bool> knockToolPort(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 500),
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

/// Ruling R10: a page that opens more than this many JavaScript dialogs in
/// [kToolDialogWindow] gets the default answers without a dialog until it
/// calms down (a loop of `alert()` must not lock the window).
const int kToolDialogBurst = 5;
const Duration kToolDialogWindow = Duration(seconds: 10);

/// What one tool's page shows (D13, D17).
@immutable
final class ToolPageState {
  const ToolPageState({
    this.url,
    this.loading = false,
    this.canGoBack = false,
    this.error,
    this.download,
    this.started = false,
  });

  /// The page's address now (null before the first load).
  final Uri? url;
  final bool loading;
  final bool canGoBack;

  /// D13: the panel over the page; null when the page shows.
  final BrowserLoadErrorKind? error;

  /// D9: a download was stopped (its URL, or the page's).
  final Uri? download;

  /// The page was asked to load at least once (lazy, D14).
  final bool started;

  /// D9 "On {host}": the page left the tool's origin (an SSO round trip).
  bool awayFrom(ToolEntry tool) {
    final u = url;
    if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return false;
    final t = tool.uri;
    return u.scheme != t.scheme || u.host != t.host || u.port != t.port;
  }

  ToolPageState copyWith({
    Object? url = _keep,
    bool? loading,
    bool? canGoBack,
    Object? error = _keep,
    Object? download = _keep,
    bool? started,
  }) => ToolPageState(
    url: identical(url, _keep) ? this.url : url as Uri?,
    loading: loading ?? this.loading,
    canGoBack: canGoBack ?? this.canGoBack,
    error: identical(error, _keep)
        ? this.error
        : error as BrowserLoadErrorKind?,
    download: identical(download, _keep) ? this.download : download as Uri?,
    started: started ?? this.started,
  );

  @override
  String toString() => 'ToolPageState(…)';
}

const Object _keep = Object();

/// One tool's live page: its engine, its state, D13's retries and the
/// crash reload, D9's outside links, downloads and dialogs. Created when
/// its dock first shows it (D14), disposed when its chip closes, the tool
/// goes or the app needs the room (D5).
final class ToolPage extends ChangeNotifier {
  ToolPage({
    required ToolEntry tool,
    required BrowserEngine Function(BrowserDialogPresenter dialogs) engine,
    ToolKnock knock = knockToolPort,
    DateTime Function() now = DateTime.now,
  }) : _tool = tool,
       _knock = knock,
       _now = now {
    this.engine = engine(_presentDialog);
    _events = this.engine.events.listen(_on);
  }

  late final BrowserEngine engine;
  late final StreamSubscription<BrowserEngineEvent> _events;
  final ToolKnock _knock;
  final DateTime Function() _now;
  ToolEntry _tool;
  ToolPageState _state = const ToolPageState();
  bool _shown = false;
  bool _disposed = false;

  /// What the last load asked for; while that load is pending, what a
  /// recovery loads ([_recoveryUrl]).
  Uri? _target;

  /// A load the app asked for ([_load]) has not finished yet: no
  /// [LoadFinished] since (a ✕ leaves it pending). See [_recoveryUrl].
  bool _loadPending = false;
  int _attempt = 0;
  int _crashes = 0;
  Timer? _retry;
  Timer? _knocker;
  bool _knocking = false;
  final List<DateTime> _dialogs = [];

  /// When the page last sent something outside ([_openOutside]).
  final List<DateTime> _outside = [];

  /// Set by the window: a ShellX chord the page handed back (D10).
  void Function(String chord)? onShortcut;

  /// Set by the window: a click inside the page (D10).
  void Function()? onContentClicked;

  /// Set by the window: a new window, `mailto:` or `tel:` (D9), at most
  /// [kToolDialogBurst] per [kToolDialogWindow] ([_openOutside]).
  void Function(Uri url)? onOpenOutside;

  /// Set by the dock while the page is on screen: shows a JavaScript
  /// dialog with the tool's name (D9). Without it: the default answers.
  BrowserDialogPresenter? presenter;

  ToolEntry get tool => _tool;
  ToolPageState get state => _state;
  bool get shown => _shown;

  /// The dock shows this page, or stopped showing it. The first show loads
  /// the tool's URL (D14: nothing loads before); retries run only while
  /// shown (D13).
  void setShown(bool shown) {
    if (_disposed || _shown == shown) return;
    _shown = shown;
    if (shown && !_state.started) {
      unawaited(_load(_tool.uri));
      return;
    }
    if (shown && _state.error == BrowserLoadErrorKind.refused) {
      _scheduleRetry();
    } else if (!shown) {
      _stopRetrying();
    }
  }

  /// ↻ and the panels' "Reload": a user's reload starts over (crash count,
  /// retry schedule). After an error, before the first load and while a
  /// load the app asked for is pending (one ✕ stopped included), it loads
  /// [_recoveryUrl]: a native reload would reload the last page committed,
  /// about:blank after a stopped first load (R25). Only a page that
  /// finished loading, with no error, is reloaded natively.
  Future<void> reload() async {
    _startOver();
    _stopRetrying();
    if (_state.error != null || !_state.started || _loadPending) {
      await _load(_recoveryUrl);
    } else {
      _set(_state.copyWith(download: null));
      await engine.reload();
    }
  }

  /// ✕ (D17). The engines report nothing for a cancelled navigation, so the
  /// page stops loading here and the bar shows ↻ again. What the app asked
  /// for stays pending: ↻ loads it again ([reload]).
  Future<void> stop() {
    _set(_state.copyWith(loading: false));
    return engine.stop();
  }

  Future<void> back() => engine.goBack();

  /// D9 "Back to tool": a URL the app newly asks for ([_startOver]).
  Future<void> backToTool() {
    _startOver();
    return _load(_tool.uri);
  }

  /// D23: the tool was edited. A new URL loads at once (if the page had
  /// started), as a URL the app newly asks for ([_startOver]); a new name
  /// or flag only changes what the bar says.
  void retarget(ToolEntry next) {
    final moved = next.url != _tool.url;
    _tool = next;
    if (moved && _state.started) {
      _startOver();
      unawaited(_load(next.uri));
    } else {
      notifyListeners();
    }
  }

  /// D13 from the start for what the app asks for anew (↻, an edited URL,
  /// "Back to tool"): refused, it is tried again after 1, 2, 4, 8 s, then
  /// every 10 s (still only while shown, so a page hidden meanwhile gets its
  /// 1 s once shown), and a crash reloads it once by itself. Never on a
  /// recovery's own load: after a committed page a recovery loads the
  /// page's address, not the target, and must keep its back-off.
  void _startOver() {
    _attempt = 0;
    _crashes = 0;
  }

  void dismissDownload() => _set(_state.copyWith(download: null));

  /// What a recovery loads (a D13 retry, the R9 knock, the crash reload,
  /// the panels' "Reload"): the URL that failed. Until a load the app asked
  /// for finishes, that is its URL — the new one after an edit (D23), the
  /// tool after D9 "Về tool" — whatever the engine reports meanwhile; after
  /// it, the page's own address (a link, ↻, a crash).
  Uri get _recoveryUrl {
    final target = _target;
    if (_loadPending && target != null) return target;
    return _state.url ?? target ?? _tool.uri;
  }

  Future<void> _load(Uri url) async {
    _target = url;
    _loadPending = true;
    _stopRetrying();
    _set(
      _state.copyWith(
        started: true,
        loading: true,
        error: null,
        download: null,
      ),
    );
    await engine.load(url);
  }

  void _on(BrowserEngineEvent e) {
    switch (e) {
      case LoadStarted():
        _set(_state.copyWith(loading: true, error: null, download: null));
      case LoadFinished():
        _attempt = 0;
        _loadPending = false;
        _stopRetrying();
        _set(_state.copyWith(loading: false, error: null));
      case UrlChanged(:final url):
        _set(_state.copyWith(url: url));
      case HistoryChanged(:final canGoBack):
        _set(_state.copyWith(canGoBack: canGoBack));
      case LoadFailed(:final kind):
        _failed(kind);
      case DownloadBlocked(:final url):
        _set(_state.copyWith(loading: false, download: url ?? _state.url));
      case OpenOutside(:final url):
        _openOutside(url);
      case ShortcutForwarded(:final chord):
        onShortcut?.call(chord);
      case ContentClicked():
        onContentClicked?.call();
      case TitleChanged() || LoadProgress() || NavigationBlocked():
        break; // D9: a blocked navigation says nothing
    }
  }

  void _failed(BrowserLoadErrorKind kind) {
    if (kind == BrowserLoadErrorKind.crashed && _crashes == 0) {
      // D13: the page's process died: one reload by itself.
      _crashes++;
      unawaited(_load(_recoveryUrl));
      return;
    }
    _set(_state.copyWith(loading: false, error: kind));
    if (kind == BrowserLoadErrorKind.refused && _shown) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    _retry = Timer(toolRetryDelay(_attempt), () {
      _attempt++;
      unawaited(_load(_recoveryUrl));
    });
    final target = _recoveryUrl;
    if (isLocalToolHost(target.host)) {
      _knocker?.cancel();
      _knocker = Timer.periodic(kToolKnockEvery, (_) => _knockOnce(target));
    }
  }

  Future<void> _knockOnce(Uri target) async {
    if (_knocking) return;
    _knocking = true;
    try {
      final up = await _knock(target.host, target.port);
      // Still what a recovery loads: never a URL edited away meanwhile.
      if (up &&
          !_disposed &&
          _shown &&
          _state.error == BrowserLoadErrorKind.refused &&
          target == _recoveryUrl) {
        unawaited(_load(target));
      }
    } finally {
      _knocking = false;
    }
  }

  void _stopRetrying() {
    _retry?.cancel();
    _retry = null;
    _knocker?.cancel();
    _knocker = null;
  }

  /// D9 sends a new window, `mailto:` and `tel:` to the system without a
  /// tap, so a page in a loop could launch the browser or the mail app over
  /// and over. Controller ruling (R10's numbers, counted apart from the
  /// dialogs): at most [kToolDialogBurst] per [kToolDialogWindow] reach the
  /// window; the rest are dropped without a word (D24: no URL in a log).
  void _openOutside(Uri url) {
    if (_withinBurst(_outside)) onOpenOutside?.call(url);
  }

  Future<Object?> _presentDialog(BrowserJsDialog dialog) async {
    final calm = _withinBurst(_dialogs);
    final show = presenter;
    if (show == null || !calm || _disposed) {
      return switch (dialog.kind) {
        BrowserJsDialogKind.alert => null,
        BrowserJsDialogKind.confirm => false,
        BrowserJsDialogKind.prompt => null,
      };
    }
    return show(dialog);
  }

  /// Ruling R10's count on [times] (one list per kind of event): records
  /// this one, and says whether at most [kToolDialogBurst] fell within the
  /// last [kToolDialogWindow].
  bool _withinBurst(List<DateTime> times) {
    final now = _now();
    times
      ..removeWhere((t) => now.difference(t) > kToolDialogWindow)
      ..add(now);
    return times.length <= kToolDialogBurst;
  }

  void _set(ToolPageState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopRetrying();
    unawaited(_events.cancel());
    unawaited(engine.dispose());
    super.dispose();
  }

  @override
  String toString() => 'ToolPage(…)';
}
