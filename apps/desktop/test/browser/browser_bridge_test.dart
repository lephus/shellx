import 'dart:convert';

import 'package:shellx_desktop/src/browser/browser_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBridgeMessage (D21)', () {
    test('console', () {
      final m =
          parseBridgeMessage(
                jsonEncode({
                  't': 'console',
                  'level': 'warn',
                  'text': 'xin chào',
                  'url': 'http://localhost/',
                }),
              )!
              as ConsoleMessage;
      expect(m.level, 'warn');
      expect(m.text, 'xin chào');
      expect(m.url, 'http://localhost/');
    });

    test('console text is cut to 2 KiB; unknown level dropped', () {
      final long =
          parseBridgeMessage(
                jsonEncode({
                  't': 'console',
                  'level': 'log',
                  'text': 'x' * 5000,
                }),
              )!
              as ConsoleMessage;
      expect(long.text.length, kConsoleTextMax);
      expect(long.url, '');
      expect(
        parseBridgeMessage(
          jsonEncode({'t': 'console', 'level': 'trace', 'text': 'a'}),
        ),
        isNull,
      );
    });

    test('net keeps only known fields, numbers non-negative', () {
      final m =
          parseBridgeMessage(
                jsonEncode({
                  't': 'net',
                  'url': 'http://localhost/api',
                  'type': 'fetch',
                  'method': 'post',
                  'status': 201,
                  'dur': 12.6,
                  'size': -1,
                  'headers': {'a': 'b'},
                }),
              )!
              as NetworkMessage;
      expect(m.method, 'POST');
      expect(m.status, 201);
      expect(m.durationMs, 13);
      expect(m.size, isNull);
      expect(
        parseBridgeMessage(jsonEncode({'t': 'net', 'url': '', 'type': 'x'})),
        isNull,
      );
    });

    test('eval ok / failed / too large / bad code', () {
      final ok =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': true,
                  'json': '"hi"',
                }),
              )!
              as EvalResultMessage;
      expect(ok.ok, isTrue);
      expect(ok.json, '"hi"');
      final failed =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': false,
                  'code': 'eval_error',
                  'message': 'boom',
                }),
              )!
              as EvalResultMessage;
      expect(failed.code, 'eval_error');
      expect(failed.message, 'boom');
      final big =
          parseBridgeMessage(
                jsonEncode({
                  't': 'eval',
                  'n': 'abc',
                  'ok': true,
                  'json': jsonEncode('é' * 30000),
                }),
              )!
              as EvalResultMessage;
      expect(big.code, 'result_too_large');
      expect(
        parseBridgeMessage(
          jsonEncode({'t': 'eval', 'n': 'abc', 'ok': false, 'code': 'rm -rf'}),
        ),
        isNull,
      );
    });

    test('malformed, oversized, unknown → null', () {
      expect(parseBridgeMessage('not json'), isNull);
      expect(parseBridgeMessage('[1,2]'), isNull);
      expect(
        parseBridgeMessage(jsonEncode({'t': 'exec', 'cmd': 'ls'})),
        isNull,
      );
      expect(parseBridgeMessage('"${'a' * (kBridgeMessageMax + 1)}"'), isNull);
    });
  });

  group('buildEvalScript (D19, D20)', () {
    String script({
      bool any = false,
      BridgeTransport t = BridgeTransport.webkit,
    }) => buildEvalScript(
      nonce: 'n0nce',
      body: 'return document.title;',
      allowAnyOrigin: any,
      transport: t,
    );

    test('carries the nonce, the body, the origin check and the transport', () {
      final s = script();
      expect(s, contains('"n0nce"'));
      expect(s, contains('return document.title;'));
      expect(s, contains("code: 'forbidden_origin'"));
      expect(s, contains('var allowed = false ||'));
      expect(s, contains('window.webkit.messageHandlers.ShellxBrowser'));
      expect(script(any: true), contains('var allowed = true ||'));
      expect(
        script(t: BridgeTransport.webview2),
        contains('window.chrome.webview'),
      );
    });

    test('JSON.stringify and postMessage are captured at injection (S8)', () {
      for (final t in BridgeTransport.values) {
        final s = script(t: t);
        expect(s, contains('var stringify = JSON.stringify;'));
        expect(s, contains('.postMessage;'));
        // Every use after the prologue goes through the cached copies.
        expect(
          'JSON.stringify'.allMatches(s).length,
          1,
          reason: 'only the capture may name JSON.stringify',
        );
        expect(s, isNot(contains('.postMessage(')));
      }
    });

    test('never uses eval or new Function (CSP)', () {
      final s = script();
      expect(s, isNot(contains('eval(')));
      expect(s, isNot(contains('new Function')));
    });

    test('a nonce with quotes stays a string literal', () {
      final s = buildEvalScript(
        nonce: 'a"b',
        body: '',
        allowAnyOrigin: false,
        transport: BridgeTransport.webkit,
      );
      expect(s, contains(r'var n = "a\"b";'));
    });
  });

  test('the in-page origin check matches D11 (Review Focus 3)', () {
    final s = buildEvalScript(
      nonce: 'n',
      body: 'return 1;',
      allowAnyOrigin: false,
      transport: BridgeTransport.webkit,
    );
    for (final part in [
      "h === 'localhost'",
      "h === '[::1]'",
      r"/^127\.\d+\.\d+\.\d+$/.test(h)",
      "location.href === 'about:blank'",
      "(p === 'http:' || p === 'https:')",
    ]) {
      expect(s, contains(part));
    }
    // S5: no *.localhost, no 0.0.0.0.
    expect(s, isNot(contains('.localhost')));
    expect(s, isNot(contains('0.0.0.0')));
  });
}
