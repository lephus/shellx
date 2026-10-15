import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../browser_engine.dart';

const String browserNativeChannelName = 'pro.shellx.desktop/browser';

typedef _NativeSink = ({
  void Function(BrowserEngineEvent event) sink,
  void Function(Uri? url) newWindow,
});

/// D9, D13: what a main-frame error of [domain] / [code] is — an error for
/// the panel, a stopped download, or nothing to show (null: a newer
/// navigation cancelled this one).
BrowserEngineEvent? macErrorEvent(
  String? domain,
  int code, {
  bool processTerminated = false,
  Uri? url,
}) {
  if (processTerminated) return const LoadFailed(BrowserLoadErrorKind.crashed);
  switch (domain) {
    case 'WebKitErrorDomain':
      // 102 "frame load interrupted": BrowserNative's download guard
      // cancelled the response and already said so. 100: a type WebKit
      // cannot show that slipped past the guard.
      if (code == 102) return null;
      if (code == 100) return DownloadBlocked(url: url);
      return const LoadFailed(BrowserLoadErrorKind.other);
    case 'NSURLErrorDomain':
      final kind = switch (code) {
        -999 => null,
        -1004 => BrowserLoadErrorKind.refused,
        -1022 => BrowserLoadErrorKind.ats,
        -1003 || -1006 => BrowserLoadErrorKind.dns,
        -1001 => BrowserLoadErrorKind.timeout,
        -1009 || -1005 || -1018 || -1020 => BrowserLoadErrorKind.unreachable,
        >= -1206 && <= -1200 => BrowserLoadErrorKind.certificate,
        _ => BrowserLoadErrorKind.other,
      };
      return kind == null ? null : LoadFailed(kind);
    default:
      return const LoadFailed(BrowserLoadErrorKind.other);
  }
}

/// A URL WebKit reported for the page, or null when it gave none (a first
/// navigation that failed before it committed), an empty one, or one
/// without a scheme: never an empty Uri that would pass for the page's
/// address.
Uri? pageUriOf(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  return uri != null && uri.hasScheme ? uri : null;
}

/// D9: a page's new window (`window.open`, or a `target=_blank` link, mail
/// and phone included) never opens, here or in a second view: it goes
/// outside (http, https, mailto, tel) or nowhere.
BrowserEngineEvent newWindowEvent(NavigationPolicy policy, Uri? url) {
  final verdict = policy(url, mainFrame: true, newWindow: true);
  if (verdict == NavigationVerdict.outside && url != null) {
    return OpenOutside(url, newWindow: true);
  }
  return const NavigationBlocked();
}

/// R28: Safari's Web Inspector reaches the user's own tool, best effort.
/// The plugin refuses it below macOS 13.3 (a [PlatformException]); the page
/// sets up and loads all the same (spec §8: macOS 12–13 work like 14+).
Future<void> enableWebInspector(
  Future<void> Function(bool inspectable) setInspectable,
) async {
  try {
    await setInspectable(true);
  } on PlatformException catch (e) {
    debugPrint('ShellX: Web Inspector not enabled: ${e.runtimeType}');
  }
}

/// The app's one `pro.shellx.desktop/browser` channel (BrowserNative.swift).
final class BrowserNativeMac implements BrowserDataStore {
  BrowserNativeMac([
    MethodChannel channel = const MethodChannel(browserNativeChannelName),
  ]) : _channel = channel;

  final MethodChannel _channel;
  final Map<int, _NativeSink> _sinks = {};
  bool _listening = false;

  /// Starts forwarding [webViewId]'s native events: chords and clicks to
  /// [sink], new windows (D9) to [newWindow] (BrowserNative `attach`).
  Future<void> attach(
    int webViewId, {
    required void Function(BrowserEngineEvent event) sink,
    required void Function(Uri? url) newWindow,
  }) {
    // Lazily, so merely constructing it (a provider) needs no binding.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
    }
    _sinks[webViewId] = (sink: sink, newWindow: newWindow);
    return _channel.invokeMethod<void>('attach', {'id': webViewId});
  }

  void detach(int webViewId) {
    _sinks.remove(webViewId);
    unawaited(
      _channel
          .invokeMethod<void>('forget', {'id': webViewId})
          .catchError((_) {}),
    );
  }

  Future<dynamic> _onCall(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final target = _sinks[args['id']];
    if (target == null) return;
    switch (call.method) {
      case 'shortcut':
        final chord = args['chord'];
        if (chord is String) target.sink(ShortcutForwarded(chord));
      case 'pointerDown':
        target.sink(const ContentClicked());
      case 'newWindow':
        final url = args['url'];
        target.newWindow(pageUriOf(url is String ? url : null));
      case 'download':
        final url = args['url'];
        target.sink(
          DownloadBlocked(url: pageUriOf(url is String ? url : null)),
        );
    }
  }

  Future<void> stop(int id) => _channel.invokeMethod<void>('stop', {'id': id});
  Future<void> focus(int id) =>
      _channel.invokeMethod<void>('focus', {'id': id});
  Future<void> blur(int id) => _channel.invokeMethod<void>('blur', {'id': id});
  Future<void> setForwardedChords(int id, List<String> chords) => _channel
      .invokeMethod<void>('setForwardedChords', {'id': id, 'chords': chords});

  /// D8, D22: the app's default WebKit store (`~/Library/WebKit/<bundle id>`).
  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearWebsiteData');
}

/// The app's one native channel (macOS); its handler registers lazily.
final browserNativeMacProvider = Provider<BrowserNativeMac>(
  (ref) => BrowserNativeMac(),
);

/// A6 D1 for V2-3 (D6): WKWebView through webview_flutter_wkwebview, as a
/// platform view, in the app's default data store (D8). No JavaScript
/// channel, no user script, no snapshot (D16). [policy] decides every
/// navigation (D9); [dialogs] shows the page's alert/confirm/prompt.
final class WkWebViewEngine implements BrowserEngine {
  WkWebViewEngine({
    required BrowserNativeMac native,
    required NavigationPolicy policy,
    BrowserDialogPresenter? dialogs,
  }) : _native = native,
       _policy = policy,
       _dialogs = dialogs {
    // D9: camera and microphone are refused (the app has no usage
    // description, and a tool gets no device).
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(),
      onPermissionRequest: (request) => unawaited(request.deny()),
    );
    _platform = _controller.platform as WebKitWebViewController;
    _id = _platform.webViewIdentifier;
    _ready = _setup();
  }

  final BrowserNativeMac _native;
  final NavigationPolicy _policy;
  final BrowserDialogPresenter? _dialogs;
  late final WebViewController _controller;
  late final WebKitWebViewController _platform;
  late final int _id;
  late final Future<void> _ready;
  final StreamController<BrowserEngineEvent> _events =
      StreamController.broadcast();

  void _emit(BrowserEngineEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _newWindow(Uri? url) => _emit(newWindowEvent(_policy, url));

  Future<void> _setup() async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // Disposed while setup waited: nothing more goes to native code.
    if (_events.isClosed) return;
    // Safari's Web Inspector reaches the user's own tool (macOS 13.3+).
    await enableWebInspector(_platform.setInspectable);
    if (_events.isClosed) return;
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final url = pageUriOf(request.url);
          final verdict = _policy(
            url,
            mainFrame: request.isMainFrame,
            newWindow: false,
          );
          switch (verdict) {
            case NavigationVerdict.allow:
              return NavigationDecision.navigate;
            case NavigationVerdict.outside when url != null:
              _emit(OpenOutside(url, newWindow: false));
            case _:
              _emit(const NavigationBlocked());
          }
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => _emit(const LoadStarted()),
        onProgress: (p) => _emit(LoadProgress(p)),
        // Once disposed, the blank page `forget` loads (D5) reads nothing
        // back: no history, no title.
        onPageFinished: (_) async {
          if (_events.isClosed) return;
          _emit(const LoadFinished());
          await _history();
          final title = await _controller.getTitle();
          if (title != null) _emit(TitleChanged(title));
        },
        onUrlChange: (change) {
          if (_events.isClosed) return;
          final uri = pageUriOf(change.url);
          if (uri != null) _emit(UrlChanged(uri));
          unawaited(_history());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false) return;
          final event = macErrorEvent(
            error is WebKitWebResourceError ? error.domain : null,
            error.errorCode,
            processTerminated:
                error.errorType ==
                WebResourceErrorType.webContentProcessTerminated,
            url: pageUriOf(error.url),
          );
          if (event != null) _emit(event);
        },
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((r) async {
      await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.alert, message: r.message),
      );
    });
    await _controller.setOnJavaScriptConfirmDialog((r) async {
      final ok = await _dialogs?.call(
        BrowserJsDialog(kind: BrowserJsDialogKind.confirm, message: r.message),
      );
      return ok == true;
    });
    await _controller.setOnJavaScriptTextInputDialog((r) async {
      final text = await _dialogs?.call(
        BrowserJsDialog(
          kind: BrowserJsDialogKind.prompt,
          message: r.message,
          defaultText: r.defaultText,
        ),
      );
      // The pinned plugin answers a String: a cancelled prompt reaches the
      // page as "", not null (an accepted limit).
      return text is String ? text : '';
    });
    // Last: the plugin's own UI delegate is set by now, and BrowserNative
    // stands its new-window guard in front of it. Never once disposed:
    // `forget` has gone already, and nothing would undo this `attach`.
    if (_events.isClosed) return;
    await _native.attach(_id, sink: _emit, newWindow: _newWindow);
  }

  Future<void> _history() async => _emit(
    HistoryChanged(
      canGoBack: await _controller.canGoBack(),
      canGoForward: await _controller.canGoForward(),
    ),
  );

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  bool get coversFlutter => false;

  /// Setup done and not disposed. A disposed engine makes no native call: a
  /// dispose may have cut setup short, and its page has no D9 policy and no
  /// guard.
  Future<bool> _live() async {
    await _ready;
    return !_events.isClosed;
  }

  @override
  Future<void> load(Uri url) async {
    if (!await _live()) return;
    await _controller.loadRequest(url);
  }

  @override
  Future<void> goBack() async {
    if (!await _live()) return;
    await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    if (!await _live()) return;
    await _controller.goForward();
  }

  @override
  Future<void> reload() async {
    if (!await _live()) return;
    await _controller.reload();
  }

  @override
  Future<void> stop() async {
    if (!await _live()) return;
    await _native.stop(_id);
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async {
    if (!await _live()) return;
    await _native.setForwardedChords(_id, chords);
  }

  @override
  Future<void> focusContent() async {
    if (!await _live()) return;
    await _native.focus(_id);
  }

  @override
  Future<void> releaseFocus() async {
    if (!await _live()) return;
    await _native.blur(_id);
  }

  @override
  Future<void> setVisible(bool visible) async {}

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _native.detach(_id);
    await _events.close();
  }
}
