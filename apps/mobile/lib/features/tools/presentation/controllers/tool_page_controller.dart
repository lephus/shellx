import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, setEquals;
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart' show kToolReservedPrefix;
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// What the tool page tells the user in a toast (it has the strings).
enum ToolNotice { noDownloads, siblingOff }

/// After this long a page still loading says how many requests it made (V2-4 E20).
const Duration kToolSlowAfter = Duration(seconds: 3);

/// Makes a web view that reports to [callbacks] (the page does: it has the injection and asks before
/// another site opens in the browser).
typedef ToolEngineFactory = ToolWebEngine Function(ToolWebCallbacks callbacks);

/// The page's `alert`, `confirm` and `prompt` as the app shows them, titled with the tool's name.
final class ToolDialogs {
  const ToolDialogs({required this.alert, required this.confirm, required this.prompt});

  final Future<void> Function(String message) alert;
  final Future<bool> Function(String message) confirm;
  final Future<String?> Function(String message, String? value) prompt;
}

final _blankUrl = Uri.parse('about:blank');

/// V2-4 E13, E15, E16: one tool on the phone. It serves the tool while the page is open and the app
/// is in the foreground, drives the web view (the entry URL, reloads), and says where the page is.
/// Nothing it carries is ever logged.
///
/// NB1: every serve (the first, or a new one after a pause or a change) has a new secret, and cookies
/// ignore ports, so a web view only ever shows pages of ports this session serves: when a serve comes back
/// on other served origins than the web view was opened for (another port, a sibling missing or new), its
/// entry page is shown in a fresh web view, after the old one was sent to `about:blank` (its scripts and
/// requests stop before the new entry sets the new cookie) and dropped. A serve that comes back on the same
/// origins (A) loads its entry in the web view that is there: every page of its history is on a port
/// served again, and its `sessionStorage` and in-page history stay. Neither the user's back nor the
/// page's own `history.back()` can reach a port this session no longer serves.
///
/// B: a page stops with its servers. The web view goes to `about:blank` when the app goes to the
/// background, when the servers close while the page stays (disabled, gone, unavailable), and when the page
/// is left: a page that went on would ask ports nothing of ours serves, with the gate cookies of every port.
@injectable
class ToolPageController extends Controller {
  ToolPageController(@factoryParam this.agentId, @factoryParam this.tool, SessionHolder session)
    : _backend = session.backend.peek();

  final String agentId;
  final ToolInfo tool;
  final ShellxBackend? _backend;
  ToolPageSession? _page;
  ToolEngineFactory? _newEngine;
  ToolDialogs? _dialogs;
  StreamSubscription<void>? _changes;
  StreamSubscription<ToolPageEvent>? _events;
  final _notices = StreamController<(ToolNotice, int?)>.broadcast(sync: true);
  Timer? _slow;
  bool _foreground = true;
  bool _disposed = false;

  /// NB1: how many web views were made; a web view is heard only while it is the latest.
  int _generation = 0;

  /// Whether anything was loaded in the current web view (the first entry load may use a blank one).
  bool _used = false;

  /// A: the served origins (`http://localhost:<port>`) the current web view was opened for.
  Set<String> _openedFor = const {};

  /// C1: the main-frame address this page last let through, until its page has finished, failed or the
  /// app loaded something itself; how many times it was let through, and whether a page has started
  /// since. See [decide].
  String? _passed;
  int _passes = 0;
  bool _startedSincePass = false;

  final Signal<ToolWebEngine?> _engine = signal(null);
  final Signal<ToolPhase> _phase = signal(ToolPhase.opening);
  final Signal<int?> _alias = signal(null);
  final Signal<int> _progress = signal(0);
  final Signal<bool> _loading = signal(false);
  final Signal<bool> _firstLoad = signal(true);
  final Signal<int?> _slowRequests = signal(null);

  ShellxBackend? get backend => _backend;

  /// The web view of the current serve (null before [start]); a new serve has a new one (NB1).
  ReadonlySignal<ToolWebEngine?> get engine => _engine;
  ReadonlySignal<ToolPhase> get phase => _phase;

  /// The port this phone serves the tool on when it is not the tool's own (E3).
  ReadonlySignal<int?> get alias => _alias;
  ReadonlySignal<int> get progress => _progress;
  ReadonlySignal<bool> get loading => _loading;

  /// Until the first page of the current web view is in: "Đang tải qua đường hầm…".
  ReadonlySignal<bool> get firstLoad => _firstLoad;

  /// The requests of a page loading for more than [kToolSlowAfter]; null otherwise.
  ReadonlySignal<int?> get slowRequests => _slowRequests;

  /// Toasts for the page: a download it cannot take, a tool of the workspace that is off.
  Stream<(ToolNotice, int?)> get notices => _notices.stream;

  ToolWebEngine? get _current => _engine.peek();

  /// Serves the tool and shows it in web views made by [newEngine]; [dialogs] are the page's own, [texts]
  /// are the server's own answers.
  void start(ToolEngineFactory newEngine, ToolDialogs dialogs, ToolHostTexts texts) {
    _newEngine = newEngine;
    _dialogs = dialogs;
    _set(_engine, _makeEngine());
    final backend = _backend;
    if (backend == null) return _set(_phase, ToolPhase.closed);
    final MachineSession machine;
    try {
      machine = backend.machine(agentId);
    } on StateError {
      return _set(_phase, ToolPhase.gone); // not paired any more
    }
    final page = _page = machine.tools.page(tool, texts);
    _changes = page.changes.listen((_) => _sync());
    _events = page.events.listen(_onEvent);
    page.start();
    _sync();
  }

  ToolWebEngine _makeEngine() {
    final generation = ++_generation;
    _used = false;
    return _newEngine!(_callbacks(generation));
  }

  /// What a web view reports to, for as long as it is the latest one made. A retired web view (NB1) is on
  /// its way out: what it reports changes nothing, it shows no dialog, and it can only go blank.
  ToolWebCallbacks _callbacks(int generation) {
    bool latest() => generation == _generation;
    return ToolWebCallbacks(
      decide: (url, mainFrame) => latest() ? decide(url, mainFrame) : _retiredDecision(url),
      onProgress: (percent) {
        if (latest()) progressed(percent);
      },
      onPageStarted: () {
        if (latest()) pageStarted();
      },
      onPageFinished: () {
        if (latest()) pageFinished();
      },
      onLoadError: (mainFrame) {
        if (latest()) loadFailed(mainFrame);
      },
      onCrashed: () {
        if (latest()) crashed();
      },
      onFileChooser: () {
        if (latest()) fileChooser();
      },
      alert: (message) => latest() ? _dialogs!.alert(message) : Future<void>.value(),
      confirm: (message) => latest() ? _dialogs!.confirm(message) : Future<bool>.value(false),
      prompt: (message, value) => latest() ? _dialogs!.prompt(message, value) : Future<String?>.value(),
    );
  }

  static ToolNavigation _retiredDecision(String url) => url == 'about:blank' ? const ToolGo() : const ToolBlock();

  void _sync() {
    final page = _page;
    if (page == null) return;
    final phase = page.phase;
    // B: the servers closed while the page stays (a cover over it): the page stops with them.
    if (_serversClosed(phase) && !_serversClosed(_phase.peek())) _goBlank();
    _set(_phase, phase);
    _set(_alias, page.alias);
  }

  static bool _serversClosed(ToolPhase phase) =>
      phase == ToolPhase.disabled || phase == ToolPhase.gone || phase == ToolPhase.unavailable;

  /// B: the current web view goes to `about:blank` (if anything was loaded in it): its page stops, with its
  /// scripts and their requests. Pages that go on after their servers closed (a WebSocket client that
  /// reconnects, a poll) would ask ports nothing of ours serves, with the gate cookies of every port.
  void _goBlank() {
    if (_used) unawaited(_current?.load(_blankUrl));
  }

  void _onEvent(ToolPageEvent event) {
    switch (event) {
      case ToolLoad(:final url):
        _forgetPassed();
        if (url.path == '${kToolReservedPrefix}enter') {
          _showEntry(url);
        } else {
          _load(url); // "Về trang đầu": the start page of the serve the web view already shows
        }
      case ToolReload():
        _forgetPassed();
        unawaited(_current?.reload());
      case ToolSiblingOff(:final port):
        _notices.add((ToolNotice.siblingOff, port));
      case ToolDownloadBlocked():
        _notices.add((ToolNotice.noDownloads, null));
    }
  }

  void _load(Uri url) {
    _used = true;
    unawaited(_current?.load(url));
  }

  /// NB1, A: the entry URL of a serve (a first serve, or a new one, each with a new secret). It loads in the
  /// current web view when nothing was loaded in it yet or when the origins served now are the ones it was
  /// opened for; otherwise in a fresh one, after the current one went blank and was dropped.
  void _showEntry(Uri url) {
    final old = _current;
    if (old == null) return;
    final origins = <String>{...?_page?.origins};
    if (_used && !setEquals(origins, _openedFor)) {
      unawaited(old.load(_blankUrl));
      _generation++;
      old.dispose();
      _set(_engine, _makeEngine());
    }
    _openedFor = origins;
    _resetLoad();
    _load(url);
  }

  /// A serve's entry page is yet to come: nothing is loading, and the first-load cover is up again.
  void _resetLoad() {
    _slow?.cancel();
    _slow = null;
    _set(_loading, false);
    _set(_slowRequests, null);
    _set(_progress, 0);
    _set(_firstLoad, true);
  }

  /// [ToolWebCallbacks.decide]: E12 against what this phone serves now, and (on Android) C1: a main-frame
  /// address let through that comes back to the policy before any page has started is a download (or a
  /// response the web view will not render) and is stopped, with the "no downloads" toast.
  ///
  /// Why: on Android the plugin loads whatever the policy lets through, and hands a download to the
  /// same policy again (`onDownloadStart` → `onNavigationRequest`); let through each time, the same
  /// request would go to the computer for ever. Where the web view reports a page start for such an
  /// attempt (it fires when a navigation begins) the first re-entry cannot be told from a link
  /// followed again, so an address let through twice and never finished is stopped the third time.
  /// A finished or failed page, a load the app makes itself, a different address, a frame and
  /// `about:blank` forget or skip all of this. A fragment is no exception: same-page fragment links
  /// never reach Android's policy, and `manual.pdf#page=4` is as much a download as `manual.pdf`.
  ///
  /// Not on iOS: WebKit never re-enters the policy for a download, and it asks the policy for every
  /// `#/route` link of a page, so the same address coming back there is a user following a link again.
  ToolNavigation decide(String url, bool mainFrame) {
    final decision = toolNavigation(url, mainFrame: mainFrame, origins: _page?.origins ?? const {});
    if (decision is ToolOtherLocal) _notices.add((ToolNotice.siblingOff, decision.port));
    if (defaultTargetPlatform == TargetPlatform.android && mainFrame && decision is ToolGo && url != 'about:blank') {
      if (_passed == url && (!_startedSincePass || _passes >= 2)) {
        _notices.add((ToolNotice.noDownloads, null));
        return const ToolBlock();
      }
      _passes = _passed == url ? _passes + 1 : 1;
      _passed = url;
      _startedSincePass = false;
    }
    return decision;
  }

  void _forgetPassed() {
    _passed = null;
    _passes = 0;
    _startedSincePass = false;
  }

  void pageStarted() {
    _startedSincePass = true;
    _page?.resetRequests();
    _set(_progress, 0); // each load starts its line at 0
    _set(_loading, true);
    _set(_slowRequests, null);
    _slow?.cancel();
    var waited = Duration.zero;
    const tick = Duration(milliseconds: 500);
    _slow = Timer.periodic(tick, (_) {
      waited += tick;
      if (waited >= kToolSlowAfter) _set(_slowRequests, _page?.requests ?? 0);
    });
  }

  void pageFinished() {
    _forgetPassed();
    _slow?.cancel();
    _slow = null;
    _set(_loading, false);
    _set(_slowRequests, null);
    _set(_firstLoad, false);
  }

  /// I3: a load failed. iOS reports a page that did not load only as an error and never calls
  /// `onPageFinished`, so the error of the page itself ends that load (the progress line, the slow
  /// line and its timer, the first-load cover); an error inside the page (Android reports every
  /// resource that failed) changes nothing.
  void loadFailed(bool mainFrame) {
    if (mainFrame) pageFinished();
  }

  void progressed(int percent) => _set(_progress, percent);

  /// E12: the web content process stopped: the page loads again.
  void crashed() {
    _forgetPassed();
    unawaited(_current?.reload());
  }

  void fileChooser() => _notices.add((ToolNotice.noDownloads, null));

  Future<void> reload() async {
    _forgetPassed();
    await _current?.reload();
  }

  /// "Về trang đầu".
  void home() => _page?.home();

  /// Android back: a page back in the web view first; false when there is none (the page closes).
  ///
  /// I1: only while the page is shown. Chromium's web view never hands back or forward to the navigation
  /// policy, so behind a cover each press would walk the hidden history; and NB2: only while the session
  /// serves. Every serve has a web view of its own (NB1), so what is behind the back is never a page of
  /// an earlier serve.
  Future<bool> back() async {
    final engine = _current;
    if (engine == null || !_backInPage || !await engine.canGoBack()) return false;
    await engine.goBack();
    return true;
  }

  /// Shown (not behind a cover) and served: a lost channel lifts the cover, but with the servers closed
  /// (after "disabled", "gone", "unavailable", or a lost channel right after a resume) the history points
  /// at ports nothing of ours serves (NB2).
  bool get _backInPage {
    final phase = _phase.peek();
    return _page?.servedPort != null &&
        !_firstLoad.peek() &&
        (phase == ToolPhase.ready || phase == ToolPhase.reconnecting);
  }

  /// E13: served only while the app is in the foreground (Apple TN2277), and the web view goes blank so
  /// that the page stops with it; back in the foreground, served again (the port may change) and loaded in
  /// a fresh web view (NB1).
  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _foreground = foreground;
    final page = _page;
    if (page == null) return;
    if (foreground) {
      page.resume();
    } else {
      unawaited(page.pause());
      _goBlank();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++; // what the left web view reports is not heard any more
    _goBlank(); // B: its page stops before the web view is dropped
    _slow?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_events?.cancel());
    unawaited(_page?.close());
    unawaited(_notices.close());
    _current?.dispose();
  }

  void _set<T>(Signal<T> s, T value) {
    if (_disposed) return;
    s.value = value;
  }
}
