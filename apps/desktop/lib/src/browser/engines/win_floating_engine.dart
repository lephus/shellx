import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart'
    show JavaScriptMode, NavigationDecision;
import 'package:webview_win_floating/webview_win_floating.dart';

import '../browser_engine.dart';
import 'wk_webview_engine.dart' show pageUriOf;

/// D8: the WebView2 profile every tool shares.
const String kToolProfileName = 'tools';

/// D8: `%LOCALAPPDATA%\ShellX\tools`; null without `LOCALAPPDATA` (then no
/// page can start: never a folder next to the program).
String? toolDataFolder(Map<String, String> environment) {
  final base = environment['LOCALAPPDATA'];
  if (base == null || base.isEmpty) return null;
  return '$base\\ShellX\\tools';
}

/// D13: WebView2's `COREWEBVIEW2_WEB_ERROR_STATUS` → the panel's kind; null
/// for a navigation that was cancelled (14).
BrowserLoadErrorKind? winErrorKind(int status) => switch (status) {
  14 => null,
  12 => BrowserLoadErrorKind.refused,
  6 || 9 || 10 || 11 => BrowserLoadErrorKind.unreachable,
  13 => BrowserLoadErrorKind.dns,
  7 => BrowserLoadErrorKind.timeout,
  >= 1 && <= 5 => BrowserLoadErrorKind.certificate,
  _ => BrowserLoadErrorKind.other,
};

/// V2-3 D7: WebView2 through `webview_win_floating` 3.0.3 — a real WebView2
/// window placed over the Flutter window. Flutter cannot draw over it
/// ([coversFlutter]): the dock hides it while an overlay is open. The page
/// keeps every key while it has the keyboard (no forwarding). Downloads use
/// WebView2's own download bar (the plugin has no hook; ruling in the plan),
/// JavaScript dialogs are WebView2's own.
///
/// Without a data folder no WebView2 starts at all (it would keep the
/// tools' data next to the program, D8). Without WebView2 every call
/// answers [BrowserLoadErrorKind.unavailable]. Once disposed, the engine
/// calls nothing and says nothing.
final class WinFloatingEngine implements BrowserEngine {
  WinFloatingEngine({
    required NavigationPolicy policy,
    required String dataFolder,
  }) : _policy = policy,
       _controller = dataFolder.isEmpty
           ? null
           : WinWebViewController(
               params: WindowsWebViewControllerCreationParams(
                 userDataFolder: dataFolder,
                 profileName: kToolProfileName,
               ),
               // D9: no camera, microphone, location or notifications.
               onPermissionRequest: (request) => unawaited(request.deny()),
             ) {
    final controller = _controller;
    if (controller == null) {
      _ready = Future.value(false);
    } else {
      _live.add(this);
      _ready = _setup(controller);
    }
  }

  /// Engines with a WebView2 of their own, not disposed (the data store
  /// clears through one of them).
  static final Set<WinFloatingEngine> _live = {};

  final NavigationPolicy _policy;

  /// Null without a data folder: nothing ever reaches the plugin.
  final WinWebViewController? _controller;

  /// True once WebView2 started and the page is set up; false when it
  /// could not start (§8: no WebView2 Runtime), without a data folder, or
  /// when disposed during setup. Never fails.
  late final Future<bool> _ready;

  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  /// The page's views now in Flutter's tree ([buildView]).
  int _views = 0;
  bool _freeing = false;
  final Completer<void> _freed = Completer<void>();

  /// The plugin reports a failed navigation twice: failed, then finished.
  bool _failedLoad = false;

  /// D7: what [setVisible] asked for last. The plugin's widget shows the
  /// page by itself whenever it mounts or comes back into the tree.
  bool _visible = true;

  bool get _disposed => _events.isClosed;

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<bool> _setup(WinWebViewController controller) async {
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      // Disposed while setup waited: nothing more goes to the plugin.
      if (_disposed) return false;
      await controller.setNavigationDelegate(_delegate(controller));
      return true;
    } on Object catch (error) {
      // §8: the plugin could not make the view (no WebView2 Runtime).
      debugPrint('tool page: engine unavailable (${error.runtimeType})');
      return false;
    }
  }

  WinNavigationDelegate _delegate(WinWebViewController controller) =>
      WinNavigationDelegate(
        onNavigationRequest: (request) {
          final url = pageUriOf(request.url);
          // The plugin asks only for the top frame and for new windows
          // (WebView2 NewWindowRequested), which it reports as "not the
          // main frame".
          final newWindow = !request.isMainFrame;
          switch (_policy(url, mainFrame: true, newWindow: newWindow)) {
            case NavigationVerdict.allow when !newWindow:
              return NavigationDecision.navigate;
            case NavigationVerdict.outside when url != null:
              _emit(OpenOutside(url, newWindow: newWindow));
            case _:
              _emit(const NavigationBlocked());
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) {
          _failedLoad = false;
          _emit(const LoadStarted());
        },
        onPageFinished: (_) {
          // The "finished" that follows a failure: the failure stands, as
          // on macOS, where a failed load never finishes.
          if (_failedLoad) {
            _failedLoad = false;
            return;
          }
          _emit(const LoadFinished());
          unawaited(_history(controller));
        },
        // Required with onPageFinished: the plugin calls it unchecked. A
        // 4xx/5xx answer is the server's own page: it finishes as loaded.
        onHttpError: (_) {},
        onSslAuthError: (error) {
          unawaited(error.cancel());
          _fail(BrowserLoadErrorKind.certificate);
        },
        onWebResourceError: (error) {
          final kind = winErrorKind(error.errorCode);
          if (kind != null) _fail(kind);
        },
        // Only a URL with a scheme: never an empty Uri for the address.
        onUrlChange: (change) {
          final uri = pageUriOf(change.url);
          if (uri != null) _emit(UrlChanged(uri));
        },
        onPageTitleChanged: (title) => _emit(TitleChanged(title)),
        onHistoryChanged: () => unawaited(_history(controller)),
      );

  void _fail(BrowserLoadErrorKind kind) {
    _failedLoad = true;
    _emit(LoadFailed(kind));
  }

  Future<void> _history(WinWebViewController controller) async {
    try {
      if (_disposed) return;
      final back = await controller.canGoBack();
      if (_disposed) return;
      final forward = await controller.canGoForward();
      _emit(HistoryChanged(canGoBack: back, canGoForward: forward));
    } on Object {
      // The view went away meanwhile.
    }
  }

  /// §8: without WebView2 (no Runtime, or no data folder) every call says
  /// "unavailable" instead of throwing. Once disposed, a call (a new one,
  /// or one that waited for setup) reaches nothing and says nothing.
  Future<void> _guard(
    Future<void> Function(WinWebViewController controller) call,
  ) async {
    final controller = _controller;
    if (controller == null || !await _ready) {
      _emit(const LoadFailed(BrowserLoadErrorKind.unavailable));
      return;
    }
    if (_disposed) return;
    try {
      await call(controller);
    } on Object catch (error) {
      debugPrint('tool page: engine unavailable (${error.runtimeType})');
      _emit(const LoadFailed(BrowserLoadErrorKind.unavailable));
    }
  }

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  bool get coversFlutter => true;

  @override
  Future<void> load(Uri url) => _guard((c) => c.loadRequest(url));

  @override
  Future<void> goBack() => _guard((c) => c.goBack());

  @override
  Future<void> goForward() => _guard((c) => c.goForward());

  @override
  Future<void> reload() => _guard((c) => c.reload());

  @override
  Future<void> stop() => _guard((c) => c.cancelNavigate());

  @override
  Future<void> setForwardedChords(List<String> chords) async {}

  @override
  Future<void> focusContent() => _guard((c) => c.requestFocus());

  /// WebView2 keeps the keyboard until a click lands outside it (D7).
  @override
  Future<void> releaseFocus() async {}

  @override
  Future<void> setVisible(bool visible) {
    _visible = visible;
    return _guard((c) => c.setVisibility(visible));
  }

  /// D7: the plugin's widget has just shown the page (it resumes WebView2
  /// as it mounts or comes back): a page asked to hide meanwhile — a menu
  /// opened while WebView2 was starting — hides again.
  void _keepHidden() {
    if (_visible || _disposed) return;
    unawaited(_guard((c) => c.setVisibility(false)));
  }

  /// The plugin's widget calls its controller by itself (when it mounts,
  /// after each layout, when it leaves), so it only stands for a page whose
  /// WebView2 started. Without one, and once disposed: an empty box.
  @override
  Widget buildView() {
    final controller = _controller;
    if (controller == null || _disposed) return const SizedBox.shrink();
    return _WinFloatingView(
      key: ObjectKey(this),
      engine: this,
      controller: controller,
    );
  }

  /// From now on no call and no event. The plugin's controller is freed
  /// once no view of the page is left in the tree, so the plugin's widget
  /// makes its last calls (it hides and suspends the page as it leaves)
  /// first. Completes when the controller is freed.
  @override
  Future<void> dispose() async {
    if (!_disposed) {
      _live.remove(this);
      await _events.close();
      if (_views == 0) unawaited(_free());
    }
    await _freed.future;
  }

  void _viewGone() {
    _views--;
    if (_views == 0 && _disposed) unawaited(_free());
  }

  Future<void> _free() async {
    if (_freeing) return;
    _freeing = true;
    try {
      await _controller?.dispose();
    } on Object {
      // Never made (no WebView2 Runtime): nothing to free.
    }
    _freed.complete();
  }
}

/// The page's place in Flutter's tree: counted on its engine while mounted
/// (the engine frees the controller only after the last one left), the
/// plugin's widget inside only once WebView2 started. Keyed by its engine,
/// so another page's view never takes over this one's state.
class _WinFloatingView extends StatefulWidget {
  const _WinFloatingView({
    super.key,
    required this.engine,
    required this.controller,
  });

  final WinFloatingEngine engine;
  final WinWebViewController controller;

  @override
  State<_WinFloatingView> createState() => _WinFloatingViewState();
}

class _WinFloatingViewState extends State<_WinFloatingView> {
  @override
  void initState() {
    super.initState();
    widget.engine._views++;
  }

  @override
  void dispose() {
    // The plugin's widget below has already left (children go first) and
    // its last calls are on their way: the controller can go after them.
    widget.engine._viewGone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: widget.engine._ready,
    builder: (context, started) =>
        started.data == true && !widget.engine._disposed
        ? _PluginView(engine: widget.engine, controller: widget.controller)
        : const SizedBox.shrink(),
  );
}

/// The plugin's widget, which resumes and shows WebView2 when it mounts
/// and when it comes back into the tree (`initState`, `activate`). After
/// that frame the engine hides the page again if the dock asked it to
/// (D7): the plugin's calls go out first, this one after them.
class _PluginView extends StatefulWidget {
  const _PluginView({required this.engine, required this.controller});

  final WinFloatingEngine engine;
  final WinWebViewController controller;

  @override
  State<_PluginView> createState() => _PluginViewState();
}

class _PluginViewState extends State<_PluginView> {
  @override
  void initState() {
    super.initState();
    _afterPluginShows();
  }

  @override
  void activate() {
    super.activate();
    _afterPluginShows();
  }

  void _afterPluginShows() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.engine._keepHidden();
    });
  }

  @override
  Widget build(BuildContext context) =>
      WinWebViewWidget(controller: widget.controller);
}

/// D8, D22, R16 on Windows: through a live page whose WebView2 started
/// (WebView2 clears the profile, `ClearBrowsingDataAll`); with none, no
/// WebView2 process holds the folder, so it is deleted. A page whose
/// WebView2 never started is no reason to fail.
final class WinFloatingDataStore implements BrowserDataStore {
  WinFloatingDataStore(this.dataFolder);
  final String? dataFolder;

  @override
  Future<void> clearAll() async {
    for (final page in [...WinFloatingEngine._live]) {
      if (await page._ready && !page._disposed) {
        await page._controller!.clearCache();
        return;
      }
    }
    final folder = dataFolder;
    if (folder == null) return;
    final dir = Directory(folder);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
