import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shellx_mobile/features/tools/domain/tool_navigation.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// The web view platform the engine runs on in these tests: it records every call the engine makes on
/// the platform controller and the navigation delegate, and anything it was not written to expect is
/// recorded as `UNEXPECTED:<name>` (a JavaScript channel, a console hook, a script run …).
class _FakeController with MockPlatformInterfaceMixin implements PlatformWebViewController {
  final calls = <String>[];
  final loads = <Uri>[];
  JavaScriptMode? mode;
  void Function(PlatformWebViewPermissionRequest request)? permission;
  Future<void> Function(JavaScriptAlertDialogRequest)? alert;
  Future<bool> Function(JavaScriptConfirmDialogRequest)? confirm;
  Future<String> Function(JavaScriptTextInputDialogRequest)? prompt;
  int reloads = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    calls.add('setJavaScriptMode');
    mode = javaScriptMode;
  }

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {
    calls.add('setPlatformNavigationDelegate');
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    calls.add('setOnPlatformPermissionRequest');
    permission = onPermissionRequest;
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request) onJavaScriptAlertDialog,
  ) async {
    calls.add('setOnJavaScriptAlertDialog');
    alert = onJavaScriptAlertDialog;
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request) onJavaScriptConfirmDialog,
  ) async {
    calls.add('setOnJavaScriptConfirmDialog');
    confirm = onJavaScriptConfirmDialog;
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request) onJavaScriptTextInputDialog,
  ) async {
    calls.add('setOnJavaScriptTextInputDialog');
    prompt = onJavaScriptTextInputDialog;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    calls.add('loadRequest');
    loads.add(params.uri);
  }

  @override
  Future<void> reload() async {
    calls.add('reload');
    reloads++;
  }

  @override
  Future<bool> canGoBack() async {
    calls.add('canGoBack');
    return true;
  }

  @override
  Future<void> goBack() async {
    calls.add('goBack');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('UNEXPECTED:${invocation.memberName}');
    return Future<void>.value();
  }
}

class _FakeDelegate with MockPlatformInterfaceMixin implements PlatformNavigationDelegate {
  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  WebResourceErrorCallback? onWebResourceError;
  final calls = <String>[];

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {
    calls.add('setOnNavigationRequest');
    this.onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    calls.add('setOnPageStarted');
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    calls.add('setOnPageFinished');
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    calls.add('setOnProgress');
    this.onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {
    calls.add('setOnWebResourceError');
    this.onWebResourceError = onWebResourceError;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('UNEXPECTED:${invocation.memberName}');
    return Future<void>.value();
  }
}

class _FakePlatform extends WebViewPlatform {
  final controller = _FakeController();
  final delegate = _FakeDelegate();

  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) =>
      controller;

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) =>
      delegate;
}

/// A permission request that writes its answer to [answers].
class _PermissionRequest extends PlatformWebViewPermissionRequest {
  const _PermissionRequest({required super.types, required this.answers});

  final List<String> answers;

  @override
  Future<void> grant() async => answers.add('grant');

  @override
  Future<void> deny() async => answers.add('deny');
}

/// V2-4 E12, Review Focus 5: the real [WebViewToolEngine] on a fake web view platform. The page tests
/// use a stand-in engine, so these are the only tests of the safeguards the plan's "Never" rules ask
/// for: no JavaScript channel into the app, no permission granted, the main frame kept on the phone's
/// own loopback, the page's dialogs handed to the app.
void main() {
  late _FakePlatform platform;
  late WebViewToolEngine engine;
  late List<String> events;
  late List<Uri> asked;
  const served = {'http://localhost:5173'};

  setUp(() {
    platform = _FakePlatform();
    WebViewPlatform.instance = platform;
    engine = WebViewToolEngine();
    events = [];
    asked = [];
    engine.askExternal = (url) async => asked.add(url);
    engine.attach(
      ToolWebCallbacks(
        decide: (url, mainFrame) => toolNavigation(url, mainFrame: mainFrame, origins: served),
        onProgress: (percent) => events.add('progress:$percent'),
        onPageStarted: () => events.add('started'),
        onPageFinished: () => events.add('finished'),
        onLoadError: (mainFrame) => events.add(mainFrame ? 'error:page' : 'error:inside'),
        onCrashed: () => events.add('crashed'),
        onFileChooser: () => events.add('fileChooser'),
        alert: (message) async => events.add('alert:$message'),
        confirm: (message) async {
          events.add('confirm:$message');
          return true;
        },
        prompt: (message, value) async {
          events.add('prompt:$message:$value');
          return value == 'cancel' ? null : 'typed';
        },
      ),
    );
  });

  test('JavaScript is on, and the engine asks the web view for nothing else: no channel, no console hook', () {
    expect(platform.controller.mode, JavaScriptMode.unrestricted);
    expect(platform.controller.calls.where((call) => call.startsWith('UNEXPECTED')), isEmpty);
    expect(platform.delegate.calls.where((call) => call.startsWith('UNEXPECTED')), isEmpty);
    expect(platform.controller.calls, isNot(contains('addJavaScriptChannel')));
    expect(platform.controller.calls.toSet(), {
      'setOnPlatformPermissionRequest',
      'setJavaScriptMode',
      'setPlatformNavigationDelegate',
      'setOnJavaScriptAlertDialog',
      'setOnJavaScriptConfirmDialog',
      'setOnJavaScriptTextInputDialog',
    });
  });

  test('every permission request is denied, camera and microphone included, and none is granted', () async {
    final answers = <String>[];
    for (final types in [
      {WebViewPermissionResourceType.camera},
      {WebViewPermissionResourceType.microphone},
      {WebViewPermissionResourceType.camera, WebViewPermissionResourceType.microphone},
    ]) {
      platform.controller.permission!(_PermissionRequest(types: types, answers: answers));
    }
    await Future<void>.delayed(Duration.zero);
    expect(answers, ['deny', 'deny', 'deny']);
  });

  test(
    'navigation: served pages go on; another loopback spelling is loaded as localhost; the rest is stopped',
    () async {
      final navigate = platform.delegate.onNavigationRequest!;
      Future<NavigationDecision> go(String url, {bool mainFrame = true}) =>
          Future.value(navigate(NavigationRequest(url: url, isMainFrame: mainFrame)));

      expect(await go('http://localhost:5173/'), NavigationDecision.navigate);
      expect(await go('about:blank'), NavigationDecision.navigate);
      expect(await go('data:text/html,hi', mainFrame: false), NavigationDecision.navigate);

      // Another spelling of a served port: stopped here, loaded as `localhost` (where the gate cookie is).
      expect(await go('http://127.0.0.1:5173/login?x=1'), NavigationDecision.prevent);
      expect(platform.controller.loads.single.toString(), 'http://localhost:5173/login?x=1');

      // Another site: stopped here, the app asks (and opens it in the browser if the user agrees).
      expect(await go('https://accounts.example.com/sso'), NavigationDecision.prevent);
      expect(asked.single.toString(), 'https://accounts.example.com/sso');

      // A local port that is not served, and every other scheme at the top: stopped, nothing loaded or asked.
      expect(await go('http://localhost:9000/'), NavigationDecision.prevent);
      expect(await go('javascript:alert(1)'), NavigationDecision.prevent);
      expect(await go('file:///etc/hosts'), NavigationDecision.prevent);
      expect(await go('intent://x#Intent;end'), NavigationDecision.prevent);
      expect(platform.controller.loads.length, 1, reason: 'only the loopback spelling was loaded');
      expect(asked.length, 1, reason: 'only the other site was asked');
    },
  );

  test('the page\'s alert, confirm and prompt reach the app; a cancelled prompt answers an empty text', () async {
    await platform.controller.alert!(const JavaScriptAlertDialogRequest(message: 'hi', url: 'http://localhost:5173/'));
    expect(
      await platform.controller.confirm!(const JavaScriptConfirmDialogRequest(message: 'sure?', url: 'u')),
      isTrue,
    );
    expect(
      await platform.controller.prompt!(
        const JavaScriptTextInputDialogRequest(message: 'name?', url: 'u', defaultText: 'An'),
      ),
      'typed',
    );
    expect(
      await platform.controller.prompt!(
        const JavaScriptTextInputDialogRequest(message: 'name?', url: 'u', defaultText: 'cancel'),
      ),
      '',
    );
    expect(events, ['alert:hi', 'confirm:sure?', 'prompt:name?:An', 'prompt:name?:cancel']);
  });

  test('page events reach the app', () {
    platform.delegate.onPageStarted!('u');
    platform.delegate.onProgress!(40);
    platform.delegate.onPageFinished!('u');
    expect(events, ['started', 'progress:40', 'finished']);
  });

  test('a stopped web content process asks for a reload, and is not a failed page', () {
    platform.delegate.onWebResourceError!(
      const WebResourceError(
        errorCode: 2,
        description: 'd',
        errorType: WebResourceErrorType.webContentProcessTerminated,
        isForMainFrame: true,
      ),
    );
    expect(events, ['crashed']);
  });

  test('a page that failed to load is told as such (iOS never says finished); an error inside it is told apart', () {
    platform.delegate.onWebResourceError!(
      const WebResourceError(
        errorCode: 3,
        description: 'd',
        errorType: WebResourceErrorType.connect,
        isForMainFrame: true,
      ),
    );
    platform.delegate.onWebResourceError!(
      const WebResourceError(
        errorCode: 4,
        description: 'd',
        errorType: WebResourceErrorType.connect,
        isForMainFrame: false,
      ),
    );
    // No frame given: the page's own, which ends a load that would otherwise never end.
    platform.delegate.onWebResourceError!(
      const WebResourceError(errorCode: 5, description: 'd', errorType: WebResourceErrorType.hostLookup),
    );
    expect(events, ['error:page', 'error:inside', 'error:page']);
  });

  test('load, reload and back go to the web view', () async {
    await engine.load(Uri.parse('http://localhost:5173/__shellx/enter?n=x&to=%2F'));
    await engine.reload();
    expect(await engine.canGoBack(), isTrue);
    await engine.goBack();
    expect(platform.controller.loads.last.path, '/__shellx/enter');
    expect(platform.controller.reloads, 1);
    expect(platform.controller.calls, containsAll(['loadRequest', 'reload', 'canGoBack', 'goBack']));
  });
}
