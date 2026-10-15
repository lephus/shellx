import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';

/// What the tool page tells the user in a toast (it has the strings).
enum ToolNotice { noDownloads, siblingOff }

/// After this long a page still loading says how many requests it made (V2-4 E20).
const Duration kToolSlowAfter = Duration(seconds: 3);

/// V2-4 E13, E15, E16: one tool on the phone. It serves the tool while the page is open and the app
/// is in the foreground, drives the web view (the entry URL, reloads), and says where the page is.
/// Nothing it carries is ever logged.
@injectable
class ToolPageController extends Controller {
  ToolPageController(@factoryParam this.agentId, @factoryParam this.tool, SessionHolder session)
    : _backend = session.backend.peek();

  final String agentId;
  final ToolInfo tool;
  final ShellxBackend? _backend;
  ToolPageSession? _page;
  ToolWebEngine? _engine;
  StreamSubscription<void>? _changes;
  StreamSubscription<ToolPageEvent>? _events;
  final _notices = StreamController<(ToolNotice, int?)>.broadcast(sync: true);
  Timer? _slow;
  bool _foreground = true;
  bool _disposed = false;

  /// C1: the main-frame address this page last let through, until its page has finished, failed or the
  /// app loaded something itself; how many times it was let through, and whether a page has started
  /// since. See [decide].
  String? _passed;
  int _passes = 0;
  bool _startedSincePass = false;

  final Signal<ToolPhase> _phase = signal(ToolPhase.opening);
  final Signal<int?> _alias = signal(null);
  final Signal<int> _progress = signal(0);
  final Signal<bool> _loading = signal(false);
  final Signal<bool> _firstLoad = signal(true);
  final Signal<int?> _slowRequests = signal(null);

  ShellxBackend? get backend => _backend;
  ReadonlySignal<ToolPhase> get phase => _phase;

  /// The port this phone serves the tool on when it is not the tool's own (E3).
  ReadonlySignal<int?> get alias => _alias;
  ReadonlySignal<int> get progress => _progress;
  ReadonlySignal<bool> get loading => _loading;

  /// Until the first page is in: "Đang tải qua đường hầm…".
  ReadonlySignal<bool> get firstLoad => _firstLoad;

  /// The requests of a page loading for more than [kToolSlowAfter]; null otherwise.
  ReadonlySignal<int?> get slowRequests => _slowRequests;

  /// Toasts for the page: a download it cannot take, a tool of the workspace that is off.
  Stream<(ToolNotice, int?)> get notices => _notices.stream;

  /// Serves the tool and shows it in [engine]; [texts] are the server's own answers.
  void start(ToolWebEngine engine, ToolHostTexts texts) {
    _engine = engine;
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

  void _sync() {
    final page = _page;
    if (page == null) return;
    _set(_phase, page.phase);
    _set(_alias, page.alias);
  }

  void _onEvent(ToolPageEvent event) {
    switch (event) {
      case ToolLoad(:final url):
        _forgetPassed();
        unawaited(_engine?.load(url));
      case ToolReload():
        _forgetPassed();
        unawaited(_engine?.reload());
      case ToolSiblingOff(:final port):
        _notices.add((ToolNotice.siblingOff, port));
      case ToolDownloadBlocked():
        _notices.add((ToolNotice.noDownloads, null));
    }
  }

  /// [ToolWebCallbacks.decide]: E12 against what this phone serves now, and C1: a main-frame address
  /// let through that comes back to the policy before any page has started is a download (or a
  /// response the web view will not render) and is stopped, with the "no downloads" toast.
  ///
  /// Why: on Android the plugin loads whatever the policy lets through, and hands a download to the
  /// same policy again (`onDownloadStart` → `onNavigationRequest`); let through each time, the same
  /// request would go to the computer for ever. Where the web view reports a page start for such an
  /// attempt (it fires when a navigation begins) the first re-entry cannot be told from a link
  /// followed again, so an address let through twice and never finished is stopped the third time.
  /// A finished or failed page, a load the app makes itself, a different address, a frame, a link
  /// within a page (a fragment) and `about:blank` forget or skip all of this.
  ToolNavigation decide(String url, bool mainFrame) {
    final decision = toolNavigation(url, mainFrame: mainFrame, origins: _page?.origins ?? const {});
    if (decision is ToolOtherLocal) _notices.add((ToolNotice.siblingOff, decision.port));
    if (mainFrame && decision is ToolGo && url != 'about:blank' && !(Uri.tryParse(url)?.hasFragment ?? false)) {
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

  void progressed(int percent) => _set(_progress, percent);

  /// E12: the web content process stopped: the page loads again.
  void crashed() {
    _forgetPassed();
    unawaited(_engine?.reload());
  }

  void fileChooser() => _notices.add((ToolNotice.noDownloads, null));

  Future<void> reload() async {
    _forgetPassed();
    await _engine?.reload();
  }

  /// "Về trang đầu".
  void home() => _page?.home();

  /// Android back: a page back in the web view first; false when there is none (the page closes).
  Future<bool> back() async {
    final engine = _engine;
    if (engine == null || !await engine.canGoBack()) return false;
    await engine.goBack();
    return true;
  }

  /// E13: served only while the app is in the foreground (Apple TN2277); back in it, served again
  /// (the port may change) and loaded.
  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _foreground = foreground;
    final page = _page;
    if (page == null) return;
    if (foreground) {
      page.resume();
    } else {
      unawaited(page.pause());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _slow?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_events?.cancel());
    unawaited(_page?.close());
    unawaited(_notices.close());
  }

  void _set<T>(Signal<T> s, T value) {
    if (_disposed) return;
    s.value = value;
  }
}
