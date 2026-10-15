import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/tools/tool_entry.dart';

String? ok(String input) => switch (parseToolUrl(input)) {
  ToolUrlOk(:final url) => url,
  ToolUrlBad() => null,
};

ToolUrlError? bad(String input) => switch (parseToolUrl(input)) {
  ToolUrlOk() => null,
  ToolUrlBad(:final error) => error,
};

ToolEntry tool(String url, {bool phone = false}) => ToolEntry(
  id: 'abcde12345',
  ws: 'default',
  name: 'Bảng việc',
  url: (parseToolUrl(url) as ToolUrlOk).url,
  phone: phone,
);

void main() {
  group('parseToolUrl (D1, Review Focus 5)', () {
    final good = <String, String>{
      'http://localhost:5173': 'http://localhost:5173/',
      'localhost:5173': 'http://localhost:5173/',
      '  localhost:5173/board?x=1#top  ': 'http://localhost:5173/board?x=1',
      'HTTPS://Example.COM/A': 'https://example.com/A',
      '[::1]:8080': 'http://[::1]:8080/',
      'http://[::1]:8080/x': 'http://[::1]:8080/x',
      '127.0.0.1:3000': 'http://127.0.0.1:3000/',
      'nas.lan:8080/admin': 'http://nas.lan:8080/admin',
      'grafana.example.com': 'http://grafana.example.com/',
      'http://localhost': 'http://localhost/',
      'http://localhost:5173/a b': 'http://localhost:5173/a%20b',
      'http://@localhost:5173/': 'http://localhost:5173/',
      'http://localhost:05173': 'http://localhost:5173/',
      'my_app:3000': 'http://my_app:3000/',
      'http://db_admin.lan/': 'http://db_admin.lan/',
    };
    good.forEach((input, expected) {
      test('"$input" → $expected', () => expect(ok(input), expected));
    });
    final refused = <String, ToolUrlError>{
      'javascript:alert(1)': ToolUrlError.notHttp,
      'file:///etc/passwd': ToolUrlError.notHttp,
      'data:text/html,hi': ToolUrlError.notHttp,
      'mailto:a@b.c': ToolUrlError.notHttp,
      'ftp://host/x': ToolUrlError.notHttp,
      'http://user:pass@localhost:5173/': ToolUrlError.userinfo,
      'https://google.com@evil.com/': ToolUrlError.userinfo,
      r'http://evil.com\@localhost': ToolUrlError.backslash,
      r'localhost:5173\x': ToolUrlError.backslash,
      '': ToolUrlError.noHost,
      '   ': ToolUrlError.noHost,
      'http://': ToolUrlError.noHost,
      'http:///x': ToolUrlError.noHost,
      'http://local host:5173': ToolUrlError.noHost,
      'http://exa\u0000mple.com/': ToolUrlError.noHost,
      'http://bücher.de/': ToolUrlError.noHost,
      'localhost:0': ToolUrlError.badPort,
      'http://localhost:0/': ToolUrlError.badPort,
      'localhost:65536': ToolUrlError.badPort,
      'http://localhost:99999': ToolUrlError.badPort,
      'http://localhost:abc': ToolUrlError.noHost,
    };
    refused.forEach((input, error) {
      test('"$input" → $error', () => expect(bad(input), error));
    });
    test('longer than 2048 characters is refused', () {
      expect(bad('http://a.com/${'x' * 2048}'), ToolUrlError.tooLong);
      expect(ok('http://a.com/${'x' * 2000}'), isNotNull);
    });
    test('never a scheme other than http or https', () {
      for (final input in [
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        ' vbscript:x',
        'about:blank',
        'chrome://settings',
        'shellx://x',
      ]) {
        final url = ok(input);
        expect(url == null || url.startsWith('http'), isTrue, reason: input);
      }
    });
    test('toString never shows the URL', () {
      expect(
        parseToolUrl('http://secret.example/x').toString(),
        'ToolUrlOk(…)',
      );
      expect(parseToolUrl('ftp://x').toString(), 'ToolUrlBad(notHttp)');
    });
  });

  group('ToolEntry', () {
    test('origin, port and host:port write the port (D11)', () {
      expect(tool('localhost:5173').origin, 'http://localhost:5173');
      expect(tool('http://localhost/').origin, 'http://localhost:80');
      expect(tool('https://example.com/x').origin, 'https://example.com:443');
      expect(tool('[::1]:8080').origin, 'http://[::1]:8080');
      expect(tool('[::1]:8080').hostPort, '[::1]:8080');
      expect(tool('https://example.com/x').port, 443);
      expect(tool('localhost:4000').hostPort, 'localhost:4000');
    });

    test('isLocal is A6 D11 local class (D11)', () {
      for (final local in [
        'localhost:1',
        'app.localhost:1',
        '127.0.0.1:1',
        '127.8.9.10:1',
        '[::1]:1',
        '0.0.0.0:1',
        'https://localhost/',
      ]) {
        expect(tool(local).isLocal, isTrue, reason: local);
      }
      for (final remote in [
        'example.com',
        '192.168.1.20:8080',
        '128.0.0.1',
        'localhost.example.com',
        'http://127.0.0.256/',
      ]) {
        expect(tool(remote).isLocal, isFalse, reason: remote);
      }
      expect(tool('example.com').unencrypted, isTrue);
      expect(tool('https://example.com').unencrypted, isFalse);
      expect(tool('localhost:5173').unencrypted, isFalse);
    });

    test('phoneAllowed: http on localhost, 127.0.0.1 or ::1 only (D15)', () {
      for (final allowed in [
        'localhost:5173',
        '127.0.0.1:3000',
        '[::1]:8080',
      ]) {
        expect(tool(allowed).phoneAllowed, isTrue, reason: allowed);
      }
      for (final refused in [
        'https://localhost:5173',
        'app.localhost:5173',
        '127.0.0.2:3000',
        '0.0.0.0:3000',
        '192.168.1.2:80',
        'example.com',
      ]) {
        expect(tool(refused).phoneAllowed, isFalse, reason: refused);
      }
      expect(tool('localhost:1', phone: true).phoneOn, isTrue);
      expect(tool('localhost:1').phoneOn, isFalse);
      expect(tool('https://localhost:1', phone: true).phoneOn, isFalse);
    });

    test('toJson and fromJson round-trip', () {
      final t = tool('localhost:5173/board', phone: true);
      expect(t.toJson(), {
        'id': 'abcde12345',
        'ws': 'default',
        'name': 'Bảng việc',
        'url': 'http://localhost:5173/board',
        'phone': true,
      });
      final back = ToolEntry.fromJson(t.toJson())!;
      expect(
        [back.id, back.ws, back.name, back.url, back.phone],
        [t.id, t.ws, t.name, t.url, t.phone],
      );
    });

    test('fromJson never throws; a bad entry is null (D2, §8)', () {
      final valid = tool('localhost:5173').toJson();
      final cases = <Object?>[
        null,
        42,
        'x',
        <Object?>[],
        {...valid, 'id': 'short'},
        {...valid, 'id': 'ABCDE12345'},
        {...valid, 'id': 7},
        {...valid, 'ws': ''},
        {...valid, 'ws': 'w' * 65},
        {...valid, 'ws': 3},
        {...valid, 'url': 'javascript:alert(1)'},
        {...valid, 'url': 'http://u:p@h/'},
        {...valid, 'url': null},
        <Object?, Object?>{1: 2},
      ];
      for (final c in cases) {
        expect(() => ToolEntry.fromJson(c), returnsNormally, reason: '$c');
        expect(ToolEntry.fromJson(c), isNull, reason: '$c');
      }
    });

    test('fromJson repairs a damaged name or flag', () {
      final valid = tool('localhost:5173').toJson();
      expect(
        ToolEntry.fromJson({...valid, 'name': ''})!.name,
        'localhost:5173',
      );
      expect(ToolEntry.fromJson({...valid, 'name': 5})!.name, 'localhost:5173');
      expect(
        ToolEntry.fromJson({...valid, 'name': 'n' * 80})!.name,
        'n' * kMaxToolNameLength,
      );
      expect(ToolEntry.fromJson({...valid, 'phone': 'yes'})!.phone, isFalse);
      expect(
        ToolEntry.fromJson({...valid, 'url': 'localhost:5173#x'})!.url,
        'http://localhost:5173/',
      );
    });

    test('toolNameFor: a blank name is host:port (D1)', () {
      expect(toolNameFor('  ', 'http://localhost:5173/'), 'localhost:5173');
      expect(toolNameFor(' Bảng việc ', 'http://localhost:5173/'), 'Bảng việc');
    });

    test('toString never shows the name or the URL (D24)', () {
      final t = tool('http://secret.example:4000/token=abc');
      expect(t.toString(), 'ToolEntry(…)');
    });
  });
}
