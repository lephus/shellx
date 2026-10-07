import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_links.dart';
import 'package:xterm/core.dart';

Terminal term(String text, {int cols = 40}) => Terminal(maxLines: 100)
  ..resize(cols, 6)
  ..write(text);

void main() {
  test('the address under a cell; the full stop after it is not part', () {
    final t = term('see https://example.com/a?b=1.');
    expect(urlAt(t, const CellOffset(10, 0)), 'https://example.com/a?b=1');
    expect(urlAt(t, const CellOffset(3, 0)), isNull);
    expect(urlAt(t, const CellOffset(29, 0)), isNull);
  });

  test('an address that wraps over rows is one address on every row', () {
    final t = term('https://example.com/a/long/path/that/wraps/over', cols: 20);
    const url = 'https://example.com/a/long/path/that/wraps/over';
    expect(urlAt(t, const CellOffset(2, 0)), url);
    expect(urlAt(t, const CellOffset(2, 2)), url);
  });

  test('wide characters before the address do not shift the answer', () {
    final t = term('日本語 https://example.com/x');
    expect(urlAt(t, const CellOffset(12, 0)), 'https://example.com/x');
    expect(urlAt(t, const CellOffset(1, 0)), isNull);
  });

  test('only http and https; no paths', () {
    final t = term('file:///etc/passwd /usr/bin ftp://x.y javascript:alert(1)');
    for (var x = 0; x < 40; x += 3) {
      expect(urlAt(t, CellOffset(x, 0)), isNull);
    }
  });

  test('cells outside the buffer have none', () {
    final t = term('https://a.b');
    expect(urlAt(t, const CellOffset(0, 99)), isNull);
    expect(urlAt(t, const CellOffset(0, -1)), isNull);
    expect(urlAt(t, const CellOffset(30, 0)), isNull);
  });
}
