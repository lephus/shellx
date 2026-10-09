import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../browser_bridge.dart';
import '../browser_engine.dart';
import '../browser_profile.dart';
import '../browser_url.dart';

const String browserNativeChannelName = 'pro.shellx.desktop/browser';

/// D14: NSURLErrorDomain codes → error page kinds; `null` = not an error
/// to show (-999: cancelled because a newer navigation started).
BrowserLoadErrorKind? macErrorKind(int code, {bool processTerminated = false}) {
  if (processTerminated) return BrowserLoadErrorKind.crashed;
  return switch (code) {
    -999 => null,
    -1004 => BrowserLoadErrorKind.refused,
    -1003 || -1006 => BrowserLoadErrorKind.dns,
    -1001 => BrowserLoadErrorKind.timeout,
    -1009 || -1005 || -1018 || -1020 => BrowserLoadErrorKind.unreachable,
    >= -1206 && <= -1200 => BrowserLoadErrorKind.certificate,
    _ => BrowserLoadErrorKind.other,
  };
}

/// WebKitErrorDomain 102 "Frame load interrupted": WebKit stopped a
/// navigation it cannot display — a download (D10).
bool isMacInterruptedLoad(int code) => code == 102;

enum BrowserJsDialogKind { alert, confirm, prompt }

final class BrowserJsDialog {
  const BrowserJsDialog({
    required this.kind,
    required this.host,
    required this.message,
    this.defaultText,
  });
  final BrowserJsDialogKind kind;
  final String host;
  final String message;
  final String? defaultText;
}

/// D32: shows the A1 dialog; returns null (alert), bool (confirm) or
/// String? (prompt). Not wired yet (the dialog UI is deferred): without a
/// presenter alerts are dismissed, confirms answer no, prompts answer "".
typedef BrowserDialogPresenter =
    Future<Object?> Function(BrowserJsDialog dialog);

/// The app's one `pro.shellx.desktop/browser` channel (BrowserNative.swift).
final class BrowserNativeMac implements WebsiteDataClearer {
  BrowserNativeMac([
    MethodChannel channel = const MethodChannel(browserNativeChannelName),
  ]) : _channel = channel;

  final MethodChannel _channel;
  final Map<int, void Function(BrowserEngineEvent)> _sinks = {};
  bool _listening = false;

  void attach(int webViewId, void Function(BrowserEngineEvent) sink) {
    // Lazily, so merely constructing it (a provider) needs no binding.
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler(_onCall);
    }
    _sinks[webViewId] = sink;
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
    final sink = _sinks[args['id']];
    if (sink == null) return;
    switch (call.method) {
      case 'shortcut':
        final chord = args['chord'];
        if (chord is String) sink(ShortcutForwarded(chord));
      case 'pointerDown':
        sink(const ContentClicked());
    }
  }

  Future<Uint8List> snapshot(int id) async =>
      (await _channel.invokeMethod<Uint8List>('snapshot', {'id': id}))!;
  Future<void> stop(int id) => _channel.invokeMethod<void>('stop', {'id': id});
  Future<void> focus(int id) =>
      _channel.invokeMethod<void>('focus', {'id': id});
  Future<void> blur(int id) => _channel.invokeMethod<void>('blur', {'id': id});
  Future<void> addBootstrap(int id, String source) =>
      _channel.invokeMethod<void>('addBootstrap', {'id': id, 'source': source});
  Future<void> setForwardedChords(int id, List<String> chords) => _channel
      .invokeMethod<void>('setForwardedChords', {'id': id, 'chords': chords});
  @override
  Future<void> clearWebsiteData() =>
      _channel.invokeMethod<void>('clearWebsiteData');
}

/// The app's one native channel (macOS); its handler registers lazily.
final browserNativeMacProvider = Provider<BrowserNativeMac>(
  (ref) => BrowserNativeMac(),
);

/// A6 D1: WKWebView through webview_flutter_wkwebview, as a platform view.
/// [bootstrap] (may be empty) runs at document start in the top frame; any
/// script it holds must capture `JSON.stringify` and the bridge's
/// `postMessage` at injection, like `buildEvalScript`.
final class WkWebViewEngine implements BrowserEngine {
  WkWebViewEngine({
    required BrowserNativeMac native,
    required String bootstrap,
    BrowserDialogPresenter? dialogs,
  }) : _native = native,
       _dialogs = dialogs {
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(),
    );
    _platform = _controller.platform as WebKitWebViewController;
    _id = _platform.webViewIdentifier;
    _native.attach(_id, _emit);
    _ready = _setup(bootstrap);
  }

  final BrowserNativeMac _native;
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

  Future<void> _setup(String bootstrap) async {
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _platform.setInspectable(true);
    await _controller.addJavaScriptChannel(
      'ShellxBrowser',
      onMessageReceived: (m) => _emit(BridgeReceived(m.message)),
    );
    if (bootstrap.isNotEmpty) await _native.addBootstrap(_id, bootstrap);
    await _native.setForwardedChords(_id, const []);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri != null && isNavigable(uri)) {
            return NavigationDecision.navigate;
          }
          _emit(const NavigationBlocked());
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => _emit(const LoadStarted()),
        onProgress: (p) => _emit(LoadProgress(p)),
        onPageFinished: (_) async {
          _emit(const LoadFinished());
          await _history();
          final title = await _controller.getTitle();
          if (title != null) _emit(TitleChanged(title));
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (uri != null) _emit(UrlChanged(uri));
          unawaited(_history());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == false) return;
          if (isMacInterruptedLoad(error.errorCode)) {
            _emit(const DownloadBlocked());
            return;
          }
          final kind = macErrorKind(
            error.errorCode,
            processTerminated:
                error.errorType ==
                WebResourceErrorType.webContentProcessTerminated,
          );
          if (kind != null) _emit(LoadFailed(kind));
        },
      ),
    );
    await _controller.setOnJavaScriptAlertDialog((r) async {
      await _dialogs?.call(
        _dialog(BrowserJsDialogKind.alert, r.url, r.message),
      );
    });
    await _controller.setOnJavaScriptConfirmDialog((r) async {
      final ok = await _dialogs?.call(
        _dialog(BrowserJsDialogKind.confirm, r.url, r.message),
      );
      return ok == true;
    });
    await _controller.setOnJavaScriptTextInputDialog((r) async {
      final text = await _dialogs?.call(
        BrowserJsDialog(
          kind: BrowserJsDialogKind.prompt,
          host: Uri.tryParse(r.url)?.host ?? '',
          message: r.message,
          defaultText: r.defaultText,
        ),
      );
      return text is String ? text : '';
    });
  }

  BrowserJsDialog _dialog(
    BrowserJsDialogKind kind,
    String url,
    String message,
  ) => BrowserJsDialog(
    kind: kind,
    host: Uri.tryParse(url)?.host ?? '',
    message: message,
  );

  Future<void> _history() async => _emit(
    HistoryChanged(
      canGoBack: await _controller.canGoBack(),
      canGoForward: await _controller.canGoForward(),
    ),
  );

  @override
  Stream<BrowserEngineEvent> get events => _events.stream;

  @override
  BridgeTransport get transport => BridgeTransport.webkit;

  @override
  Future<void> load(Uri url) async {
    await _ready;
    if (url == aboutBlank) {
      await _controller.loadHtmlString('');
    } else {
      await _controller.loadRequest(url);
    }
  }

  @override
  Future<void> goBack() async {
    await _ready;
    await _controller.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ready;
    await _controller.goForward();
  }

  @override
  Future<void> reload() async {
    await _ready;
    await _controller.reload();
  }

  @override
  Future<void> stop() async {
    await _ready;
    await _native.stop(_id);
  }

  @override
  Future<void> runScript(String script) async {
    await _ready;
    await _controller.runJavaScript(script);
  }

  @override
  Future<Uint8List> capturePng() async {
    await _ready;
    return _native.snapshot(_id);
  }

  @override
  Future<void> setForwardedChords(List<String> chords) async {
    await _ready;
    await _native.setForwardedChords(_id, chords);
  }

  @override
  Future<void> focusContent() async {
    await _ready;
    await _native.focus(_id);
  }

  @override
  Future<void> releaseFocus() async {
    await _ready;
    await _native.blur(_id);
  }

  @override
  Widget buildView() => WebViewWidget(controller: _controller);

  @override
  Future<void> dispose() async {
    _native.detach(_id);
    await _events.close();
  }
}
