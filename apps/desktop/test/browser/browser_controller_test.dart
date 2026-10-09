import 'dart:convert';

import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import '../support/fake_browser_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

late FakeBrowserEngine engine;
late BrowserController controller;
late List<BrowserPaneState> states;
late List<BrowserNotice> notices;
late List<String> chords;
late int clicks;
bool anyOrigin = false;
DateTime now = DateTime(2026, 10, 7, 9);
int nonces = 0;

void boot({String url = 'http://localhost:8000/'}) {
  engine = FakeBrowserEngine();
  states = [];
  notices = [];
  chords = [];
  clicks = 0;
  anyOrigin = false;
  nonces = 0;
  controller = BrowserController(
    paneId: -1,
    engine: engine,
    initialUrl: Uri.parse(url),
    allowAnyOrigin: () => anyOrigin,
    onState: states.add,
    onNotice: notices.add,
    onShortcut: chords.add,
    onContentClicked: () => clicks++,
    clock: () => now,
    nonce: () => 'nonce${++nonces}',
  );
}

void bridge(Map<String, Object?> m) =>
    engine.emit(BridgeReceived(jsonEncode(m)));

void answer(String nonce, Object? value) =>
    bridge({'t': 'eval', 'n': nonce, 'ok': true, 'json': jsonEncode(value)});

Matcher browserError(String code) =>
    isA<BrowserError>().having((e) => e.code, 'code', code);

void main() {
  setUp(boot);

  test('engine events drive the pane state', () {
    engine.emit(const LoadStarted());
    expect(controller.state.loading, isTrue);
    expect(controller.state.progress, isNull);
    engine.emit(const LoadProgress(40));
    engine.emit(UrlChanged(Uri.parse('http://localhost:8000/docs')));
    engine.emit(const TitleChanged('Docs'));
    engine.emit(const HistoryChanged(canGoBack: true, canGoForward: false));
    engine.emit(const LoadFinished());
    final s = controller.state;
    expect(s.loading, isFalse);
    expect(s.progress, 100);
    expect(s.url.toString(), 'http://localhost:8000/docs');
    expect(s.title, 'Docs');
    expect(s.canGoBack, isTrue);
    expect(states, isNotEmpty);
  });

  test(
    'navigate refuses non-web schemes; user navigation is flagged (D10, D17)',
    () async {
      expect(
        () => controller.navigate(Uri.parse('file:///etc/passwd')),
        throwsA(browserError('navigation_blocked')),
      );
      await controller.navigate(
        Uri.parse('http://localhost:3000/'),
        byUser: true,
      );
      expect(engine.loads.single.toString(), 'http://localhost:3000/');
      expect(controller.state.userNavigation, isTrue);
    },
  );

  group('evalJs (D19)', () {
    test('returns the decoded JSON value for its own nonce', () async {
      final result = controller.evalJs('return document.title;');
      await Future<void>.delayed(Duration.zero);
      expect(engine.scripts.single, contains('"nonce1"'));
      answer('nonce1', {'a': 1});
      expect(await result, {'a': 1});
    });

    test('a forged result for another nonce is ignored', () async {
      final result = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      answer('someone-else', 'forged');
      answer('nonce1', 1);
      expect(await result, 1);
    });

    test('page errors map to codes', () async {
      final result = controller.evalJs('throw 1;');
      await Future<void>.delayed(Duration.zero);
      bridge({
        't': 'eval',
        'n': 'nonce1',
        'ok': false,
        'code': 'not_serializable',
        'message': 'cyclic',
      });
      await expectLater(result, throwsA(browserError('not_serializable')));
    });

    test('engine rejecting the script → eval_error', () async {
      engine.scriptError = StateError('syntax');
      await expectLater(
        controller.evalJs('return ('),
        throwsA(browserError('eval_error')),
      );
    });

    test('times out (default 10 s, capped at 30 s)', () {
      fakeAsync((async) {
        Object? error;
        controller
            .evalJs('return 1;', timeout: const Duration(minutes: 5))
            .catchError((Object e) {
              error = e;
              return null;
            });
        async.elapse(const Duration(seconds: 29));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, browserError('timeout'));
      });
    });

    test('oversized body → bad_request', () {
      expect(
        () => controller.evalJs('x' * (32 * 1024 + 1)),
        throwsA(browserError('bad_request')),
      );
    });
  });

  group('origin gate (D20)', () {
    setUp(() => boot(url: 'https://example.com/'));

    test('content reads refused on a non-local page by default', () async {
      await expectLater(
        controller.evalJs('return 1;'),
        throwsA(browserError('forbidden_origin')),
      );
      await expectLater(
        controller.screenshot(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(
        () => controller.console(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(
        () => controller.network(),
        throwsA(browserError('forbidden_origin')),
      );
      expect(engine.scripts, isEmpty);
    });

    test('allowed when the setting is on; the script carries it', () async {
      anyOrigin = true;
      final result = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      expect(engine.scripts.single, contains('var allowed = true ||'));
      answer('nonce1', 1);
      expect(await result, 1);
    });

    test('navigation and waiting are always allowed', () async {
      await controller.navigate(Uri.parse('https://example.org/'));
      final wait = controller.waitForLoad();
      engine.emit(const LoadFinished());
      expect(await wait, isA<BrowserPageInfo>());
    });
  });

  test(
    'screenshot discarded when the page left for a non-local origin',
    () async {
      engine.onCapture = () =>
          engine.emit(UrlChanged(Uri.parse('https://bank.example/')));
      await expectLater(
        controller.screenshot(),
        throwsA(browserError('forbidden_origin')),
      );
      engine.onCapture = null;
      boot();
      expect(await controller.screenshot(), engine.png);
    },
  );

  group('console and network (D22, D23)', () {
    test('ring of 500, since/limit paging, level filter', () {
      for (var i = 0; i < 520; i++) {
        now = now.add(const Duration(seconds: 1)); // stay under the rate limit
        bridge({
          't': 'console',
          'level': i.isEven ? 'log' : 'error',
          'text': 'm$i',
        });
      }
      final first = controller.console();
      expect(first.length, 200);
      expect(first.first.text, 'm20'); // the 20 oldest fell out
      final next = controller.console(since: first.last.seq);
      expect(next.first.text, 'm220');
      expect(controller.console(level: 'error', limit: 5).map((e) => e.text), [
        'm21',
        'm23',
        'm25',
        'm27',
        'm29',
      ]);
    });

    test('network entries', () {
      bridge({
        't': 'net',
        'url': 'http://localhost:8000/',
        'type': 'navigation',
        'method': 'GET',
        'status': 200,
      });
      final e = controller.network().single;
      expect(e.method, 'GET');
      expect(e.status, 200);
    });

    test(
      'more than 200 messages a second: the excess is dropped and counted',
      () {
        for (var i = 0; i < 250; i++) {
          bridge({'t': 'console', 'level': 'log', 'text': 'flood $i'});
        }
        expect(controller.console(limit: 200).length, 200);
        now = now.add(const Duration(seconds: 2));
        bridge({'t': 'console', 'level': 'log', 'text': 'after'});
        final tail = controller.console(since: 200).map((e) => e.text).toList();
        expect(tail, ['[shellx] dropped 50', 'after']);
      },
    );
  });

  group('waitForLoad (D24)', () {
    test(
      'resolves on finish, fails on load error, at once when idle',
      () async {
        expect(
          (await controller.waitForLoad()).url.toString(),
          'http://localhost:8000/',
        );
        engine.emit(const LoadStarted());
        final ok = controller.waitForLoad();
        engine.emit(const TitleChanged('Hi'));
        engine.emit(const LoadFinished());
        expect((await ok).title, 'Hi');
        engine.emit(const LoadStarted());
        final failed = controller.waitForLoad();
        engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
        await expectLater(failed, throwsA(browserError('load_failed')));
      },
    );

    test('times out', () {
      fakeAsync((async) {
        engine.emit(const LoadStarted());
        Object? error;
        controller.waitForLoad(timeout: const Duration(seconds: 2)).catchError((
          Object e,
        ) {
          error = e;
          return BrowserPageInfo(url: Uri(), title: '');
        });
        async.elapse(const Duration(seconds: 3));
        expect(error, browserError('timeout'));
      });
    });
  });

  test(
    'agent mark lasts 10 s after the last command; announced once a burst (D25)',
    () {
      fakeAsync((async) {
        controller.agentCommand();
        expect(controller.state.agentActive, isTrue);
        expect(notices, [BrowserNotice.agentStarted]);
        async.elapse(const Duration(seconds: 6));
        controller.agentCommand();
        async.elapse(const Duration(seconds: 6));
        expect(controller.state.agentActive, isTrue);
        async.elapse(const Duration(seconds: 5));
        expect(controller.state.agentActive, isFalse);
        now = now.add(const Duration(seconds: 30));
        controller.agentCommand();
        expect(notices, [
          BrowserNotice.agentStarted,
        ]); // < 60 s since the last one
        now = now.add(const Duration(seconds: 61));
        async.elapse(const Duration(seconds: 11));
        controller.agentCommand();
        expect(notices, [
          BrowserNotice.agentStarted,
          BrowserNotice.agentStarted,
        ]);
      });
    },
  );

  test('notices and forwarded shortcuts', () {
    engine.emit(const NavigationBlocked());
    engine.emit(const DownloadBlocked());
    engine.emit(const ShortcutForwarded('meta+l'));
    engine.emit(const ContentClicked());
    expect(clicks, 1);
    expect(notices, [
      BrowserNotice.schemeBlocked,
      BrowserNotice.downloadBlocked,
    ]);
    expect(chords, ['meta+l']);
  });

  test(
    'dispose fails pending calls with not_found and disposes the engine',
    () async {
      final pending = controller.evalJs('return 1;');
      await Future<void>.delayed(Duration.zero);
      final check = expectLater(pending, throwsA(browserError('not_found')));
      await controller.dispose();
      await check;
      expect(engine.disposed, isTrue);
      expect(() => controller.reload(), throwsA(browserError('not_found')));
    },
  );
}
