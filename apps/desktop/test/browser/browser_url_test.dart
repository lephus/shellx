import 'package:shellx_desktop/src/browser/browser_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAddressInput (D9)', () {
    final cases = <String, String?>{
      '3000': 'http://localhost:3000/',
      ' 8000 ': 'http://localhost:8000/',
      '0': null,
      '65536': null,
      'localhost:3000': 'http://localhost:3000/',
      'localhost:3000/docs?x=1': 'http://localhost:3000/docs?x=1',
      'localhost': 'http://localhost/',
      'app.localhost:5173': 'http://app.localhost:5173/',
      '127.0.0.1:8080': 'http://127.0.0.1:8080/',
      '[::1]:3000': 'http://[::1]:3000/',
      '192.168.1.20:8080': 'http://192.168.1.20:8080/',
      'example.com': 'https://example.com/',
      'example.com/a b': null,
      'http://example.com': 'http://example.com/',
      'HTTPS://Example.com/x': 'https://example.com/x',
      'about:blank': 'about:blank',
      'hello world': null,
      'hello': null,
      'javascript:alert(1)': null,
      'file:///etc/passwd': null,
      'data:text/html,hi': null,
      'mailto:a@b.c': null,
      'http://': null,
      'localhost:99999': null,
      '': null,
    };
    cases.forEach((input, expected) {
      test('"$input"', () {
        expect(parseAddressInput(input)?.toString(), expected);
      });
    });
    test('longer than 2048 characters is refused', () {
      expect(parseAddressInput('https://a.com/${'x' * 2048}'), isNull);
    });
  });

  group('classifyOrigin (D11)', () {
    final cases = <String, BrowserOrigin>{
      'http://localhost:3000/': BrowserOrigin.local,
      'https://localhost/': BrowserOrigin.local,
      'http://app.localhost/': BrowserOrigin.local,
      'http://127.0.0.1/': BrowserOrigin.local,
      'http://127.8.9.10/': BrowserOrigin.local,
      'http://[::1]:8000/': BrowserOrigin.local,
      'http://0.0.0.0:8000/': BrowserOrigin.local,
      'https://example.com/': BrowserOrigin.secure,
      'http://example.com/': BrowserOrigin.insecure,
      'http://localhost.example.com/': BrowserOrigin.insecure,
      'http://128.0.0.1/': BrowserOrigin.insecure,
      'about:blank': BrowserOrigin.none,
      'file:///tmp/x': BrowserOrigin.none,
    };
    cases.forEach((url, expected) {
      test(url, () => expect(classifyOrigin(Uri.parse(url)), expected));
    });
    test('null', () => expect(classifyOrigin(null), BrowserOrigin.none));
  });

  test('isNavigable (D10)', () {
    expect(isNavigable(Uri.parse('http://localhost/')), isTrue);
    expect(isNavigable(Uri.parse('https://a.com/')), isTrue);
    expect(isNavigable(aboutBlank), isTrue);
    expect(isNavigable(Uri.parse('about:srcdoc')), isFalse);
    expect(isNavigable(Uri.parse('file:///x')), isFalse);
    expect(isNavigable(Uri.parse('mailto:a@b.c')), isFalse);
    expect(isNavigable(Uri.parse('javascript:void(0)')), isFalse);
  });

  test('urlForRestore strips credentials and fragment (D29)', () {
    expect(
      urlForRestore(Uri.parse('http://u:p@localhost:8888/lab?token=abc#cell')),
      'http://localhost:8888/lab?token=abc',
    );
    expect(urlForRestore(aboutBlank), isNull);
    expect(urlForRestore(Uri.parse('file:///x')), isNull);
    expect(urlForRestore(null), isNull);
    expect(urlForRestore(Uri.parse('https://a.com/${'x' * 2048}')), isNull);
  });

  test('displayAddress (UI-A6 §2.1)', () {
    expect(
      displayAddress(Uri.parse('http://localhost:5173/about')),
      'localhost:5173/about',
    );
    expect(
      displayAddress(Uri.parse('https://example.com/a%20b')),
      'example.com/a b',
    );
    expect(
      displayAddress(Uri.parse('http://example.com/')),
      'http://example.com/',
    );
    expect(displayAddress(aboutBlank), '');
  });
}
