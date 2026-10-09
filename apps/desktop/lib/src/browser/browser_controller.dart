/// A6 D18–D25: one browser pane's programmable side (W4) — the API A7
/// exposes, the origin gate, the console/network buffers.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Widget;

import 'browser_bridge.dart';
import 'browser_engine.dart';
import 'browser_url.dart';

/// D18: every failure the API reports; [code] is the wire code (§3.6).
final class BrowserError implements Exception {
  const BrowserError(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'BrowserError($code)';
}

/// What the toolbar, the pane header and A7 `list` show (§3.1).
final class BrowserPaneState {
  const BrowserPaneState({
    required this.url,
    this.title = '',
    this.loading = false,
    this.progress,
    this.canGoBack = false,
    this.canGoForward = false,
    this.error,
    this.agentActive = false,
    this.userNavigation = false,
  });

  final Uri url;
  final String title;
  final bool loading;

  /// 0–100, `null` when the engine does not report progress (D13).
  final int? progress;
  final bool canGoBack;
  final bool canGoForward;
  final BrowserLoadErrorKind? error;

  /// D25: an agent command arrived in the last 10 s.
  final bool agentActive;

  /// D17: the current navigation was started by the user (announce it).
  final bool userNavigation;

  BrowserOrigin get origin => classifyOrigin(url);

  BrowserPaneState copyWith({
    Uri? url,
    String? title,
    bool? loading,
    Object? progress = _keep,
    bool? canGoBack,
    bool? canGoForward,
    Object? error = _keep,
    bool? agentActive,
    bool? userNavigation,
  }) => BrowserPaneState(
    url: url ?? this.url,
    title: title ?? this.title,
    loading: loading ?? this.loading,
    progress: identical(progress, _keep) ? this.progress : progress as int?,
    canGoBack: canGoBack ?? this.canGoBack,
    canGoForward: canGoForward ?? this.canGoForward,
    error: identical(error, _keep)
        ? this.error
        : error as BrowserLoadErrorKind?,
    agentActive: agentActive ?? this.agentActive,
    userNavigation: userNavigation ?? this.userNavigation,
  );
}

const Object _keep = Object();

/// D22.
final class ConsoleEntry {
  const ConsoleEntry({
    required this.seq,
    required this.ts,
    required this.level,
    required this.text,
    required this.url,
  });
  final int seq;
  final DateTime ts;
  final String level;
  final String text;
  final String url;
}

/// D23.
final class NetworkEntry {
  const NetworkEntry({
    required this.seq,
    required this.ts,
    required this.url,
    required this.type,
    this.method,
    this.status,
    this.durationMs,
    this.size,
  });
  final int seq;
  final DateTime ts;
  final String url;
  final String type;
  final String? method;
  final int? status;
  final int? durationMs;
  final int? size;
}

final class BrowserPageInfo {
  const BrowserPageInfo({required this.url, required this.title});
  final Uri url;
  final String title;
}

/// Things the UI turns into a toast or an announcement.
enum BrowserNotice { schemeBlocked, downloadBlocked, agentStarted }

const int kBufferSize = 500;
const int kListLimit = 200;
const int kBridgeMessagesPerSecond = 200;
const Duration kAgentMarkFor = Duration(seconds: 10);
const Duration kAgentAnnounceGap = Duration(seconds: 60);
const Duration kEvalTimeout = Duration(seconds: 10);
const Duration kEvalTimeoutMax = Duration(seconds: 30);
const Duration kWaitTimeout = Duration(seconds: 15);
const Duration kWaitTimeoutMax = Duration(seconds: 60);

final class BrowserController {
  BrowserController({
    required this.paneId,
    required BrowserEngine engine,
    required Uri initialUrl,
    required bool Function() allowAnyOrigin,
    required void Function(BrowserPaneState state) onState,
    void Function(BrowserNotice notice)? onNotice,
    void Function(String chord)? onShortcut,
    void Function()? onContentClicked,
    DateTime Function()? clock,
    String Function()? nonce,
  }) : _engine = engine,
       _allowAnyOrigin = allowAnyOrigin,
       _onState = onState,
       _onNotice = onNotice ?? ((_) {}),
       _onShortcut = onShortcut ?? ((_) {}),
       _onContentClicked = onContentClicked ?? (() {}),
       _clock = clock ?? DateTime.now,
       _nonce = nonce ?? _randomNonce,
       _state = BrowserPaneState(url: initialUrl) {
    _sub = engine.events.listen(_onEvent);
  }

  final int paneId;
  final BrowserEngine _engine;
  final bool Function() _allowAnyOrigin;
  final void Function(BrowserPaneState) _onState;
  final void Function(BrowserNotice) _onNotice;
  final void Function(String) _onShortcut;
  final void Function() _onContentClicked;
  final DateTime Function() _clock;
  final String Function() _nonce;
  late final StreamSubscription<BrowserEngineEvent> _sub;

  BrowserPaneState _state;
  BrowserPaneState get state => _state;

  final Queue<ConsoleEntry> _console = Queue();
  final Queue<NetworkEntry> _network = Queue();
  int _seq = 0;
  final Map<String, Completer<Object?>> _evals = {};
  final List<Completer<BrowserPageInfo>> _waiters = [];
  Timer? _agentTimer;
  DateTime? _lastAnnounce;
  DateTime? _windowStart;
  int _windowCount = 0;
  int _dropped = 0;
  bool _disposed = false;

  static String _randomNonce() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _set(BrowserPaneState next) {
    _state = next;
    if (!_disposed) _onState(next);
  }

  // ---- user and agent commands ----

  Future<void> navigate(Uri url, {bool byUser = false}) {
    _alive();
    if (!isNavigable(url)) throw const BrowserError('navigation_blocked');
    // Loading from now on, not from the engine's first event: a
    // waitForLoad() right after navigate() must wait for this page (§6).
    _set(
      _state.copyWith(
        url: url,
        loading: true,
        progress: null,
        error: null,
        userNavigation: byUser,
      ),
    );
    return _engine.load(url);
  }

  Future<void> back({bool byUser = false}) {
    _alive();
    _set(_state.copyWith(userNavigation: byUser));
    return _engine.goBack();
  }

  Future<void> forward({bool byUser = false}) {
    _alive();
    _set(_state.copyWith(userNavigation: byUser));
    return _engine.goForward();
  }

  Future<void> reload({bool byUser = false}) {
    _alive();
    _set(
      _state.copyWith(
        loading: true,
        progress: null,
        error: null,
        userNavigation: byUser,
      ),
    );
    return _engine.reload();
  }

  Future<void> stop() {
    _alive();
    return _engine.stop();
  }

  /// D24: settles when the current navigation finishes; at once when
  /// nothing is loading.
  Future<BrowserPageInfo> waitForLoad({Duration timeout = kWaitTimeout}) {
    _alive();
    if (!_state.loading) {
      final error = _state.error;
      if (error != null) {
        return Future.error(BrowserError('load_failed', error.name));
      }
      return Future.value(_info());
    }
    final c = Completer<BrowserPageInfo>();
    _waiters.add(c);
    return c.future.timeout(
      _clamp(timeout, kWaitTimeoutMax),
      onTimeout: () {
        _waiters.remove(c);
        throw const BrowserError('timeout');
      },
    );
  }

  /// D19: [body] is an async function body; the result is the decoded
  /// JSON value (`null` for undefined).
  Future<Object?> evalJs(String body, {Duration timeout = kEvalTimeout}) async {
    _alive();
    if (body.length > kEvalScriptMax) throw const BrowserError('bad_request');
    _gate();
    final nonce = _nonce();
    final c = Completer<Object?>();
    _evals[nonce] = c;
    try {
      await _engine.runScript(
        buildEvalScript(
          nonce: nonce,
          body: body,
          allowAnyOrigin: _allowAnyOrigin(),
          transport: _engine.transport,
        ),
      );
    } on Object catch (e) {
      _evals.remove(nonce);
      throw BrowserError('eval_error', e.runtimeType.toString());
    }
    return c.future.timeout(
      _clamp(timeout, kEvalTimeoutMax),
      onTimeout: () {
        _evals.remove(nonce);
        throw const BrowserError('timeout');
      },
    );
  }

  /// D20, D24: refused when the page left an allowed origin meanwhile.
  Future<Uint8List> screenshot() async {
    _alive();
    _gate();
    final before = _state.url;
    final png = await _engine.capturePng();
    if (_state.url != before) _gate();
    return png;
  }

  List<ConsoleEntry> console({
    int since = 0,
    int limit = kListLimit,
    String? level,
  }) {
    _alive();
    _gate();
    return _page(
      _console,
      since,
      limit,
      (e) => e.seq,
      (e) => level == null || e.level == level,
    );
  }

  List<NetworkEntry> network({int since = 0, int limit = kListLimit}) {
    _alive();
    _gate();
    return _page(_network, since, limit, (e) => e.seq, (_) => true);
  }

  /// The engine's view and focus, for BrowserPaneView (Task 9).
  Widget buildView() => _engine.buildView();
  Future<void> focusContent() => _engine.focusContent();
  Future<void> releaseFocus() => _engine.releaseFocus();
  Future<void> setForwardedChords(List<String> chords) =>
      _engine.setForwardedChords(chords);

  /// D25: called by the A7 command handler for every command on this pane.
  void agentCommand() {
    _alive();
    _agentTimer?.cancel();
    _agentTimer = Timer(
      kAgentMarkFor,
      () => _set(_state.copyWith(agentActive: false)),
    );
    final now = _clock();
    if (!_state.agentActive &&
        (_lastAnnounce == null ||
            now.difference(_lastAnnounce!) >= kAgentAnnounceGap)) {
      _lastAnnounce = now;
      _onNotice(BrowserNotice.agentStarted);
    }
    if (!_state.agentActive) _set(_state.copyWith(agentActive: true));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _agentTimer?.cancel();
    await _sub.cancel();
    for (final c in _evals.values) {
      c.completeError(const BrowserError('not_found'));
    }
    _evals.clear();
    for (final c in _waiters) {
      c.completeError(const BrowserError('not_found'));
    }
    _waiters.clear();
    await _engine.dispose();
  }

  // ---- internals ----

  void _alive() {
    if (_disposed) throw const BrowserError('not_found');
  }

  void _gate() {
    final origin = _state.origin;
    if (origin == BrowserOrigin.local || origin == BrowserOrigin.none) return;
    if (_allowAnyOrigin()) return;
    throw const BrowserError('forbidden_origin');
  }

  static Duration _clamp(Duration d, Duration max) =>
      d > max ? max : (d <= Duration.zero ? max : d);

  BrowserPageInfo _info() =>
      BrowserPageInfo(url: _state.url, title: _state.title);

  List<T> _page<T>(
    Iterable<T> all,
    int since,
    int limit,
    int Function(T) seq,
    bool Function(T) keep,
  ) => all
      .where((e) => seq(e) > since && keep(e))
      .take(limit.clamp(1, kListLimit))
      .toList(growable: false);

  void _push<T>(Queue<T> q, T entry) {
    q.addLast(entry);
    while (q.length > kBufferSize) {
      q.removeFirst();
    }
  }

  /// D21 / §5: at most 200 bridge messages a second; the excess is counted
  /// into one `warn` entry when the next second starts.
  bool _admit() {
    final now = _clock();
    final start = _windowStart;
    if (start == null || now.difference(start) >= const Duration(seconds: 1)) {
      final dropped = _dropped;
      _windowStart = now;
      _windowCount = 0;
      _dropped = 0;
      if (dropped > 0) {
        _push(
          _console,
          ConsoleEntry(
            seq: ++_seq,
            ts: now,
            level: 'warn',
            text: '[shellx] dropped $dropped',
            url: _state.url.toString(),
          ),
        );
      }
    }
    if (_windowCount >= kBridgeMessagesPerSecond) {
      _dropped++;
      return false;
    }
    _windowCount++;
    return true;
  }

  void _onEvent(BrowserEngineEvent event) {
    switch (event) {
      case UrlChanged(:final url):
        _set(_state.copyWith(url: url));
      case TitleChanged(:final title):
        _set(_state.copyWith(title: title));
      case LoadStarted():
        _set(_state.copyWith(loading: true, progress: null, error: null));
      case LoadProgress(:final percent):
        _set(_state.copyWith(progress: percent.clamp(0, 100)));
      case LoadFinished():
        _set(_state.copyWith(loading: false, progress: 100));
        for (final c in _waiters) {
          c.complete(_info());
        }
        _waiters.clear();
      case LoadFailed(:final kind):
        _set(_state.copyWith(loading: false, progress: null, error: kind));
        for (final c in _waiters) {
          c.completeError(BrowserError('load_failed', kind.name));
        }
        _waiters.clear();
      case HistoryChanged(:final canGoBack, :final canGoForward):
        _set(_state.copyWith(canGoBack: canGoBack, canGoForward: canGoForward));
      case NavigationBlocked():
        _onNotice(BrowserNotice.schemeBlocked);
      case DownloadBlocked():
        _onNotice(BrowserNotice.downloadBlocked);
      case ShortcutForwarded(:final chord):
        _onShortcut(chord);
      case ContentClicked():
        _onContentClicked();
      case BridgeReceived(:final raw):
        _onBridge(raw);
    }
  }

  void _onBridge(String raw) {
    final message = parseBridgeMessage(raw);
    if (message == null) return;
    if (message is! EvalResultMessage && !_admit()) return;
    final now = _clock();
    switch (message) {
      case ConsoleMessage(:final level, :final text, :final url):
        _push(
          _console,
          ConsoleEntry(
            seq: ++_seq,
            ts: now,
            level: level,
            text: text,
            url: url,
          ),
        );
      case NetworkMessage m:
        _push(
          _network,
          NetworkEntry(
            seq: ++_seq,
            ts: now,
            url: m.url,
            type: m.type,
            method: m.method,
            status: m.status,
            durationMs: m.durationMs,
            size: m.size,
          ),
        );
      case TitleMessage(:final title):
        _set(_state.copyWith(title: title));
      case EvalResultMessage m:
        final c = _evals.remove(m.nonce);
        if (c == null) {
          return; // not ours, or already settled: a page can forge these
        }
        if (m.ok) {
          c.complete(jsonDecode(m.json!));
        } else {
          c.completeError(BrowserError(m.code!, m.message));
        }
    }
  }
}
