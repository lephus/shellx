import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/browser/engines/win_floating_engine.dart';
import 'package:shellx_desktop/src/tools/tool_navigation.dart';
import 'package:webview_win_floating/webview_win_floating.dart'
    show WinWebViewWidget;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WebView2 error statuses map to the D13 kinds', () {
    expect(winErrorKind(12), BrowserLoadErrorKind.refused);
    for (final s in [6, 9, 10, 11]) {
      expect(winErrorKind(s), BrowserLoadErrorKind.unreachable, reason: '$s');
    }
    expect(winErrorKind(13), BrowserLoadErrorKind.dns);
    expect(winErrorKind(7), BrowserLoadErrorKind.timeout);
    for (final s in [1, 2, 3, 4, 5]) {
      expect(winErrorKind(s), BrowserLoadErrorKind.certificate, reason: '$s');
    }
    expect(winErrorKind(14), isNull, reason: 'cancelled');
    expect(winErrorKind(16), BrowserLoadErrorKind.other);
    expect(winErrorKind(0), BrowserLoadErrorKind.other);
  });

  test('the data folder is %LOCALAPPDATA%\\ShellX\\tools, never elsewhere '
      '(D8)', () {
    expect(
      toolDataFolder({'LOCALAPPDATA': r'C:\Users\me\AppData\Local'}),
      r'C:\Users\me\AppData\Local\ShellX\tools',
    );
    expect(toolDataFolder({}), isNull);
    expect(toolDataFolder({'LOCALAPPDATA': ''}), isNull);
    expect(kToolProfileName, 'tools');
  });

  test('with no page alive, clearing deletes the folder (D22)', () async {
    final root = await Directory.systemTemp.createTemp('tools');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final folder = Directory('${root.path}/tools');
    await File('${folder.path}/EBWebView/x').create(recursive: true);
    await WinFloatingDataStore(folder.path).clearAll();
    expect(await folder.exists(), isFalse);
    await WinFloatingDataStore(null).clearAll(); // nothing to clear
    await WinFloatingDataStore(folder.path).clearAll(); // already gone
  });

  test('without a data folder no WebView2 starts: every call answers '
      'unavailable, nothing reaches the plugin, and clearing deletes the '
      'folder (F1, D8)', () async {
    final plugin = _Plugin();
    final engine = WinFloatingEngine(policy: toolNavigation, dataFolder: '');
    addTearDown(engine.dispose);
    final events = _listen(engine);
    await engine.load(_page);
    await engine.reload();
    await engine.setVisible(false);
    await pumpEventQueue();
    expect(events, List.filled(3, _failed(BrowserLoadErrorKind.unavailable)));
    // Never one of the live pages: clearing deletes the folder.
    final folder = await _toolsFolder();
    await WinFloatingDataStore(folder.path).clearAll();
    expect(await folder.exists(), isFalse);
    // The plugin makes its view in WinWebViewController's constructor
    // (`create` on its channel, after `init` the first time): never here.
    expect(plugin.calls, isEmpty);
  });

  test('WebView2 gets the tools folder and profile (D8); a page URL is a '
      'URL with a scheme or nothing; requests follow D9 and new windows go '
      'outside', () async {
    final plugin = _Plugin();
    final engine = WinFloatingEngine(
      policy: toolNavigation,
      dataFolder: _folder,
    );
    addTearDown(engine.dispose);
    final events = _listen(engine);
    await engine.load(_page);
    expect(
      _args(plugin.calls.firstWhere((c) => c.method == 'create')),
      allOf(
        containsPair('userDataFolder', _folder),
        containsPair('profileName', 'tools'),
      ),
    );
    // The plugin always passes a string (its channel handler insists).
    for (final url in ['', 'not a url', 'http://127.0.0.1:5173/x']) {
      await plugin.send('onUrlChange', {'url': url});
    }
    var request = 0;
    Future<void> ask(String url, {bool newWindow = false}) => plugin.send(
      'onNavigationRequest',
      {'requestId': ++request, 'url': url, 'isNewWindow': newWindow},
    );
    await ask('');
    await ask('http://localhost:5173/next');
    await ask('https://docs.example.com/', newWindow: true);
    await ask('mailto:a@b.c');
    await pumpEventQueue();
    expect(events, [
      isA<UrlChanged>().having(
        (e) => e.url,
        'url',
        Uri.parse('http://127.0.0.1:5173/x'),
      ),
      isA<NavigationBlocked>(),
      isA<OpenOutside>()
          .having((e) => e.url, 'url', Uri.parse('https://docs.example.com/'))
          .having((e) => e.newWindow, 'newWindow', isTrue),
      isA<OpenOutside>()
          .having((e) => e.url, 'url', Uri.parse('mailto:a@b.c'))
          .having((e) => e.newWindow, 'newWindow', isFalse),
    ]);
    expect(
      {
        for (final c in plugin.calls)
          if (c.method == 'allowNavigationRequest')
            _args(c)['requestId']: _args(c)['isAllowed'],
      },
      {1: false, 2: true, 3: false, 4: false},
    );
  });

  test('a disposed engine calls nothing and says nothing: neither a call '
      'made after dispose nor one still waiting for WebView2 (dispose '
      'rule)', () async {
    // A page that was up.
    var plugin = _Plugin();
    var engine = WinFloatingEngine(policy: toolNavigation, dataFolder: _folder);
    var events = _listen(engine);
    await engine.load(_page);
    await engine.dispose();
    expect(plugin.methods.last, 'dispose');
    final freed = plugin.calls.length;
    await engine.load(_page);
    await engine.reload();
    await engine.goBack();
    await engine.goForward();
    await engine.stop();
    await engine.focusContent();
    await engine.setVisible(true);
    await engine.dispose();
    await pumpEventQueue();
    expect(plugin.methods.skip(freed), isEmpty);
    expect(events, isEmpty);

    // A page still waiting for WebView2 when it was disposed: its load
    // never goes out, and setup stops at the call already in flight.
    plugin = _Plugin();
    final created = Completer<bool>();
    plugin.created = () => created.future;
    engine = WinFloatingEngine(policy: toolNavigation, dataFolder: _folder);
    events = _listen(engine);
    final waiting = engine.load(_page);
    final disposing = engine.dispose();
    created.complete(true);
    await waiting;
    await disposing;
    await pumpEventQueue();
    expect(plugin.methods.where((m) => m != 'init'), [
      'create',
      'enableJavascript',
      'dispose',
    ]);
    expect(events, isEmpty);
  });

  test('a failed load ends failed: the "finished" WebView2 sends after a '
      'failure is dropped, and a 4xx/5xx page finishes (ruling a, '
      'D13)', () async {
    final plugin = _Plugin();
    final engine = WinFloatingEngine(
      policy: toolNavigation,
      dataFolder: _folder,
    );
    addTearDown(engine.dispose);
    final events = _listen(engine);
    await engine.load(_page);
    const url = {'url': 'http://localhost:5173/'};
    // As the plugin's my_webview.cpp reports a completed navigation: the
    // failure (if any), then "finished".
    Future<void> navigation(
      String? failure, [
      Map<String, Object?> args = const {},
    ]) async {
      await plugin.send('onPageStarted', url);
      if (failure != null) await plugin.send(failure, {...url, ...args});
      await plugin.send('onPageFinished', url);
      await pumpEventQueue();
    }

    await navigation('onWebResourceError', {
      'errCode': 12,
      'errType': 'connect',
    });
    await navigation('onSslAuthError');
    await navigation('onHttpError', {'errCode': 404});
    // A failure without its "finished": the next start clears it.
    await plugin.send('onWebResourceError', {
      ...url,
      'errCode': 7,
      'errType': 'timeout',
    });
    await pumpEventQueue();
    await navigation(null);
    expect(events, [
      isA<LoadStarted>(),
      _failed(BrowserLoadErrorKind.refused),
      isA<LoadStarted>(),
      _failed(BrowserLoadErrorKind.certificate),
      isA<LoadStarted>(),
      isA<LoadFinished>(),
      isA<HistoryChanged>(),
      _failed(BrowserLoadErrorKind.timeout),
      isA<LoadStarted>(),
      isA<LoadFinished>(),
      isA<HistoryChanged>(),
    ]);
  });

  test('without the WebView2 Runtime every call answers unavailable, the '
      'failure is logged once by its type, and clearing deletes the folder '
      '(§8, ruling b, R16)', () async {
    final plugin = _Plugin()..created = () async => false;
    final folder = await _toolsFolder();
    final logged = <String?>[];
    final saved = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    addTearDown(() => debugPrint = saved);
    final engine = WinFloatingEngine(
      policy: toolNavigation,
      dataFolder: folder.path,
    );
    _neverCollected.add(engine);
    addTearDown(engine.dispose);
    final events = _listen(engine);
    await engine.load(_page);
    await engine.goBack();
    await engine.setVisible(true);
    // Its WebView2 never started: nothing holds the folder.
    await WinFloatingDataStore(folder.path).clearAll();
    await pumpEventQueue();
    expect(events, List.filled(3, _failed(BrowserLoadErrorKind.unavailable)));
    expect(logged, ['tool page: engine unavailable (PlatformException)']);
    expect(await folder.exists(), isFalse);
    expect(plugin.methods.where((m) => m != 'init'), ['create']);
  });

  testWidgets('the plugin\'s view mounts only once WebView2 started, and the '
      'controller is freed only after the view left the tree (ruling '
      'c)', (tester) async {
    final plugin = _Plugin();
    final created = Completer<bool>();
    plugin.created = () => created.future;
    final engine = WinFloatingEngine(
      policy: toolNavigation,
      dataFolder: _folder,
    );
    final events = _listen(engine);
    await tester.pumpWidget(engine.buildView());
    expect(find.byType(WinWebViewWidget), findsNothing);
    created.complete(true);
    await tester.pump();
    await tester.pump();
    expect(find.byType(WinWebViewWidget), findsOneWidget);
    expect(
      plugin.methods,
      containsAllInOrder([
        'create',
        'enableJavascript',
        'setHasNavigationDecision',
        'resume',
        'updateBounds',
      ]),
    );

    // Disposed, and its view unmounted, in one frame. Until the view goes
    // the page still runs: what it reports meanwhile reaches no one and
    // makes the engine call nothing.
    final disposed = engine.dispose();
    await plugin.send('onHistoryChanged');
    await tester.pumpWidget(const SizedBox());
    await disposed;
    expect(tester.takeException(), isNull);
    expect(plugin.methods.last, 'dispose');
    expect(plugin.methods, containsAllInOrder(['suspend', 'dispose']));
    expect(plugin.methods, isNot(contains('canGoBack')));
    expect(events, isEmpty);
  });

  testWidgets('without WebView2 (no data folder, or no Runtime) the view '
      'stays empty and calls nothing (F1, ruling c)', (tester) async {
    final plugin = _Plugin()..created = () async => false;
    final logged = <String?>[];
    final saved = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);
    try {
      final noFolder = WinFloatingEngine(
        policy: toolNavigation,
        dataFolder: '',
      );
      final noRuntime = WinFloatingEngine(
        policy: toolNavigation,
        dataFolder: _folder,
      );
      _neverCollected.add(noRuntime);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              Expanded(child: noFolder.buildView()),
              Expanded(child: noRuntime.buildView()),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(WinWebViewWidget), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await noFolder.dispose();
      await noRuntime.dispose();
      expect(tester.takeException(), isNull);
      expect(plugin.methods.where((m) => m != 'init'), ['create']);
      expect(logged, ['tool page: engine unavailable (PlatformException)']);
    } finally {
      debugPrint = saved;
    }
  });
}

/// A tools folder as Task 10's factory passes it on Windows.
const _folder = r'C:\Users\me\AppData\Local\ShellX\tools';

final _page = Uri.parse('http://localhost:5173/');

/// Engines whose WebView2 never started. The plugin's finalizer would
/// dispose such a view (its `dispose` throws before it detaches): kept, so
/// that never happens in the middle of a later test.
final _neverCollected = <Object>[];

List<BrowserEngineEvent> _listen(BrowserEngine engine) {
  final events = <BrowserEngineEvent>[];
  engine.events.listen(events.add);
  return events;
}

Matcher _failed(BrowserLoadErrorKind kind) =>
    isA<LoadFailed>().having((e) => e.kind, 'kind', kind);

Map<Object?, Object?> _args(MethodCall call) =>
    call.arguments as Map<Object?, Object?>;

/// A tools folder with WebView2 data in it, removed after the test.
Future<Directory> _toolsFolder() async {
  final root = await Directory.systemTemp.createTemp('tools');
  addTearDown(() => root.delete(recursive: true));
  final folder = Directory('${root.path}/tools');
  await File('${folder.path}/EBWebView/x').create(recursive: true);
  return folder;
}

/// webview_win_floating 3.0.3's channel, answered as its Windows side
/// answers (windows/webview_win_floating_plugin.cpp): `create` makes a view
/// or fails (no WebView2 Runtime); any other call for a view that is not
/// there, never made or disposed, is an error.
final class _Plugin {
  _Plugin() {
    _messenger.setMockMethodCallHandler(_channel, _answer);
  }

  static const _channel = MethodChannel('webview_win_floating');

  static TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// What the plugin sent, in order.
  final calls = <MethodCall>[];
  final _views = <int>{};

  /// WebView2's answer to `create`; false: there is no WebView2 Runtime.
  Future<bool> Function() created = () async => true;

  List<String> get methods => [for (final c in calls) c.method];

  /// The view this test made.
  int get _id =>
      _args(calls.firstWhere((c) => c.method == 'create'))['webviewId']! as int;

  Future<Object?> _answer(MethodCall call) async {
    calls.add(call);
    if (call.method == 'init') return null;
    final id = _args(call)['webviewId']! as int;
    if (call.method == 'create') {
      if (!await created()) {
        throw PlatformException(
          code: 'error',
          message: '[webview] native create failed.',
        );
      }
      _views.add(id);
      return true;
    }
    if (!_views.contains(id)) {
      throw PlatformException(code: 'error', message: "webview hasn't created");
    }
    return switch (call.method) {
      'dispose' => _views.remove(id),
      'canGoBack' || 'canGoForward' => false,
      _ => null,
    };
  }

  /// What WebView2 reports, sent the way the plugin's Windows side sends it.
  Future<void> send(String method, [Map<String, Object?> args = const {}]) =>
      _messenger.handlePlatformMessage(
        _channel.name,
        _channel.codec.encodeMethodCall(
          MethodCall(method, {'webviewId': _id, ...args}),
        ),
        (_) {},
      );
}
