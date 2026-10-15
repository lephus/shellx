import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
// Stable: pubspec pins webview_flutter_wkwebview: 3.25.1 exactly (R15); its public API cannot remove every kind.
// ignore: implementation_imports
import 'package:webview_flutter_wkwebview/src/common/web_kit.g.dart' show WKWebsiteDataStore, WebsiteDataType;

/// What the tool page hears from its web view (V2-4 E12).
final class ToolWebCallbacks {
  const ToolWebCallbacks({
    required this.decide,
    required this.onProgress,
    required this.onPageStarted,
    required this.onPageFinished,
    required this.onLoadError,
    required this.onCrashed,
    required this.onFileChooser,
    required this.alert,
    required this.confirm,
    required this.prompt,
  });

  /// Where the web view may go ([toolNavigation]); the engine acts on the answer it gets.
  final ToolNavigation Function(String url, bool mainFrame) decide;
  final void Function(int percent) onProgress;
  final void Function() onPageStarted;
  final void Function() onPageFinished;

  /// A load failed: [mainFrame] is true for the page itself, false for something inside it (an image,
  /// a script). iOS tells a page that did not load only through this, never as finished.
  final void Function(bool mainFrame) onLoadError;

  /// The web content process stopped: the page reloads.
  final void Function() onCrashed;

  /// The page asked for a file (Android): none is given (E12).
  final void Function() onFileChooser;

  /// The page's `alert`, `confirm` and `prompt`, shown as the app's dialogs naming the tool.
  final Future<void> Function(String message) alert;
  final Future<bool> Function(String message) confirm;
  final Future<String?> Function(String message, String? value) prompt;
}

/// The tool page's web view: `webview_flutter` in the app, a fake in tests.
abstract interface class ToolWebEngine {
  void attach(ToolWebCallbacks callbacks);
  Future<void> load(Uri url);
  Future<void> reload();
  Future<bool> canGoBack();
  Future<void> goBack();

  /// Asks the user, then opens [url] in the phone's browser (set by the page).
  set askExternal(Future<void> Function(Uri url) ask);
  Widget view();

  /// The page shows this web view no more: a new serve has a web view of its own (NB1), or the page is left.
  void dispose();
}

/// V2-4 E12: `webview_flutter` with no JavaScript channel into the app, every permission request
/// (camera, microphone, location) denied, geolocation off, no file chooser, and the main frame kept
/// on the phone's own loopback ([ToolWebCallbacks.decide]).
@Injectable(as: ToolWebEngine)
final class WebViewToolEngine implements ToolWebEngine {
  WebViewToolEngine() : _controller = WebViewController(onPermissionRequest: (request) => request.deny());

  final WebViewController _controller;
  Future<void> Function(Uri url) _askExternal = (_) async {};

  @override
  set askExternal(Future<void> Function(Uri url) ask) => _askExternal = ask;

  @override
  void attach(ToolWebCallbacks callbacks) {
    unawaited(_controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            switch (callbacks.decide(request.url, request.isMainFrame)) {
              case ToolGo():
                return NavigationDecision.navigate;
              case ToolGoInstead(:final url):
                unawaited(_controller.loadRequest(url));
              case ToolAskExternal(:final url):
                unawaited(_askExternal(url));
              case ToolOtherLocal() || ToolBlock():
                break;
            }
            return NavigationDecision.prevent;
          },
          onProgress: callbacks.onProgress,
          onPageStarted: (_) => callbacks.onPageStarted(),
          onPageFinished: (_) => callbacks.onPageFinished(),
          onWebResourceError: (error) {
            if (error.errorType == WebResourceErrorType.webContentProcessTerminated) {
              callbacks.onCrashed();
            } else {
              // No frame given: the page's own, so that a load that would never end does end.
              callbacks.onLoadError(error.isForMainFrame ?? true);
            }
          },
        ),
      ),
    );
    unawaited(_controller.setOnJavaScriptAlertDialog((request) => callbacks.alert(request.message)));
    unawaited(_controller.setOnJavaScriptConfirmDialog((request) => callbacks.confirm(request.message)));
    unawaited(
      _controller.setOnJavaScriptTextInputDialog(
        (request) async => await callbacks.prompt(request.message, request.defaultText) ?? '',
      ),
    );
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setGeolocationEnabled(false));
      unawaited(
        platform.setOnShowFileSelector((_) async {
          callbacks.onFileChooser();
          return const <String>[];
        }),
      );
    }
  }

  @override
  Future<void> load(Uri url) => _controller.loadRequest(url);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<bool> canGoBack() => _controller.canGoBack();

  @override
  Future<void> goBack() => _controller.goBack();

  @override
  Widget view() => WebViewWidget(controller: _controller);

  @override
  void dispose() {}
}

/// Settings › "Xóa dữ liệu của tool" (V2-4 E12): the tool pages' cookies and storage.
abstract interface class ToolWebData {
  Future<void> clear();
}

/// R22's three public calls (cookies, cache, local storage) on both platforms, and on iOS I4: those reach
/// only some kinds of website data there (cookies; memory, disk and app caches; local storage), so a tool
/// that keeps its login in IndexedDB, WebSQL or session storage would stay signed in. WebKit's own data
/// store is asked to remove every kind. Android's storage call already clears every origin.
@LazySingleton(as: ToolWebData)
final class WebViewToolData implements ToolWebData {
  WebViewToolData()
    : this.using(isIOS: defaultTargetPlatform == TargetPlatform.iOS, removeWebsiteData: _removeFromStore);

  /// For tests: whether this is iOS, and what removes [WebsiteDataType]s from the web view's data store.
  @visibleForTesting
  WebViewToolData.using({
    required bool isIOS,
    required Future<void> Function(List<WebsiteDataType> types) removeWebsiteData,
  }) : _isIOS = isIOS,
       _removeWebsiteData = removeWebsiteData;

  final bool _isIOS;
  final Future<void> Function(List<WebsiteDataType> types) _removeWebsiteData;

  /// Everything of [types] since the beginning of time (0), from the store the tool pages use.
  static Future<void> _removeFromStore(List<WebsiteDataType> types) async {
    await WKWebsiteDataStore.defaultDataStore.removeDataOfTypes(types, 0);
  }

  @override
  Future<void> clear() async {
    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    await controller.clearCache();
    await controller.clearLocalStorage();
    if (_isIOS) await _removeWebsiteData(WebsiteDataType.values);
  }
}
