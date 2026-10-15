import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// V2-4 E9, E11: the request and header rules both ends apply.
void main() {
  group('method (E9)', () {
    test('a token of at most 16 characters', () {
      for (final ok in ['GET', 'POST', 'PROPFIND', 'patch', 'M-SEARCH']) {
        expect(isToolMethod(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'GET POST', 'G\r\nET', 'A' * 17, 'GÉT', 'G(ET']) {
        expect(isToolMethod(bad), isFalse, reason: bad);
      }
    });

    test('never CONNECT, TRACE or TRACK, in any case', () {
      for (final bad in ['CONNECT', 'connect', 'TRACE', 'Trace', 'TRACK']) {
        expect(isToolMethod(bad), isFalse, reason: bad);
      }
    });
  });

  group('target (E9, RF 4)', () {
    test('origin form only', () {
      for (final ok in ['/', '/src/main.ts?t=1', '/@vite/client', '/a@b']) {
        expect(isToolTarget(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '',
        '*',
        'http://evil.com/',
        '@evil.com/',
        '//evil.com/x',
        'evil.com:80',
      ]) {
        expect(isToolTarget(bad), isFalse, reason: bad);
      }
    });

    test('no CR, LF, NUL, space, #, backslash or DEL; at most 8 KiB', () {
      for (final bad in [
        '/a\r\nHost: evil',
        '/a\nb',
        '/a\u0000',
        '/a b',
        '/a#frag',
        '/a\\..\\b',
        '/a\u007f',
        '/${'x' * kToolMaxTargetBytes}',
      ]) {
        expect(isToolTarget(bad), isFalse, reason: bad);
      }
      expect(isToolTarget('/${'x' * (kToolMaxTargetBytes - 1)}'), isTrue);
    });
  });

  group('head (E9)', () {
    test('pairs of a token name and a value without CR, LF or NUL', () {
      expect(isToolHead(['accept', '*/*', 'x-a', '']), isTrue);
      expect(isToolHead(['accept']), isFalse);
      expect(isToolHead(['bad name', 'v']), isFalse);
      expect(isToolHead(['x', 'a\r\nInjected: 1']), isFalse);
      expect(isToolHead(['x', 'a\u0000']), isFalse);
      expect(isToolHead(['x', 'Bảng việc']), isTrue); // carried; see writable
    });

    test('at most 100 headers and 32 KiB', () {
      final hundred = [
        for (var i = 0; i < 100; i++) ...['h$i', 'v'],
      ];
      expect(isToolHead(hundred), isTrue);
      expect(isToolHead([...hundred, 'one', 'more']), isFalse);
      expect(isToolHead(['big', 'x' * (kToolMaxHeadBytes - 3)]), isTrue);
      expect(isToolHead(['big', 'x' * (kToolMaxHeadBytes - 2)]), isFalse);
    });

    test('dart:io writes only visible ASCII, space and tab', () {
      expect(isWritableHeaderValue('text/html; charset=utf-8\t'), isTrue);
      expect(isWritableHeaderValue('attachment; filename="résumé"'), isFalse);
      expect(isWritableHeaderValue('a\u0001'), isFalse);
    });
  });

  test('hop-by-hop, forwarding headers and what Connection names are '
      'dropped (E9)', () {
    final dropped = toolDroppedNames([
      'Connection',
      'keep-alive, X-Secret',
      'X-Forwarded-For',
      '10.0.0.1',
      'accept',
      '*/*',
    ]);
    for (final name in [
      'connection',
      'keep-alive',
      'transfer-encoding',
      'te',
      'trailer',
      'upgrade',
      'proxy-authorization',
      'forwarded',
      'via',
      'x-forwarded-for',
      'x-secret',
      'expect',
    ]) {
      expect(dropped, contains(name));
    }
    expect(dropped, isNot(contains('accept')));
  });

  group('gate cookie (E11)', () {
    test('its name carries the port', () {
      expect(toolGateCookieName(5173), '__shellx_5173');
    });

    test('every __shellx_ pair is stripped from Cookie', () {
      expect(
        stripToolGateCookies('a=1; __shellx_5173=s3cr3t; b=2'),
        'a=1; b=2',
      );
      expect(stripToolGateCookies('__shellx_5173=s; __shellx_80=t'), isNull);
      expect(stripToolGateCookies('sid=__shellx_5173'), 'sid=__shellx_5173');
    });

    test('a tool cannot set a __shellx_ cookie', () {
      expect(setsToolGateCookie('__shellx_5173=x; Path=/'), isTrue);
      expect(setsToolGateCookie(' __shellx_1=x'), isTrue);
      expect(setsToolGateCookie('sid=1; Path=/'), isFalse);
    });
  });

  test('values of a header, in order, whatever the case', () {
    expect(
      toolHeadValues([
        'Cookie',
        'a=1',
        'accept',
        '*/*',
        'cookie',
        'b=2',
      ], 'cookie'),
      ['a=1', 'b=2'],
    );
  });

  group('loopback spellings (E2, E3)', () {
    test(
      'localhost, 127.0.0.1 and [::1] with the port; 80 may be left out',
      () {
        for (final ok in [
          'localhost:5173',
          '127.0.0.1:5173',
          '[::1]:5173',
          'LOCALHOST:5173',
        ]) {
          expect(isToolLoopbackAuthority(ok, 5173), isTrue, reason: ok);
        }
        for (final bad in [
          'localhost:5174',
          'evil.com:5173',
          'localhost',
          '::1:5173',
          'localhost.evil.com:5173',
        ]) {
          expect(isToolLoopbackAuthority(bad, 5173), isFalse, reason: bad);
        }
        expect(isToolLoopbackAuthority('localhost', 80), isTrue);
      },
    );

    test('the origin at the start of a URL, for the rewrite of E3', () {
      expect(
        toolLoopbackPrefix('http://localhost:49152/a?b#c', 49152),
        'http://localhost:49152',
      );
      expect(
        toolLoopbackPrefix('http://localhost:49152', 49152),
        'http://localhost:49152',
      );
      expect(
        toolLoopbackPrefix('http://127.0.0.1:5173?x', 5173),
        'http://127.0.0.1:5173',
      );
      expect(toolLoopbackPrefix('https://localhost:5173/', 5173), isNull);
      expect(toolLoopbackPrefix('http://localhost:5174/', 5173), isNull);
      expect(
        toolLoopbackPrefix('http://localhost:5173@evil.com/', 5173),
        isNull,
      );
    });
  });
}
