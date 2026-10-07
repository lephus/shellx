import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/link_finder.dart';
import 'package:xterm/core.dart' show CellOffset;

DesktopTerminal term(String text, {int cols = 40}) =>
    DesktopTerminal(maxLines: 100)
      ..resize(cols, 6)
      ..write(text);

void main() {
  test('a URL in the text; the last character is part, the dot is not', () {
    final t = term('see https://example.com/a?b=1.');
    final hit = findLinkAt(t, const CellOffset(10, 0), paths: false)!;
    expect(hit.target, 'https://example.com/a?b=1');
    expect(hit.source, LinkSource.detected);
    expect(hit.begin, const CellOffset(4, 0));
    expect(hit.end, const CellOffset(29, 0));
    expect(findLinkAt(t, const CellOffset(29, 0), paths: false), isNull);
    expect(findLinkAt(t, const CellOffset(3, 0), paths: false), isNull);
  });

  test('a URL wrapped over rows is one link on every row', () {
    final t = term('https://example.com/a/very/long/path/that/wraps', cols: 20);
    final a = findLinkAt(t, const CellOffset(3, 0), paths: false)!;
    final b = findLinkAt(t, const CellOffset(3, 2), paths: false)!;
    expect(a.target, b.target);
    expect(a.begin, const CellOffset(0, 0));
    expect(b.end.y, 2);
  });

  test('a path is a link only when paths are asked for', () {
    final t = term('open /usr/local/bin/dart:12 now');
    expect(findLinkAt(t, const CellOffset(8, 0), paths: false), isNull);
    final hit = findLinkAt(t, const CellOffset(8, 0), paths: true)!;
    expect(hit.kind, TerminalLinkKind.path);
    expect(hit.target, '/usr/local/bin/dart');
  });

  test(
    'OSC 8: the address, the shown text, and a confirmation when they differ',
    () {
      final t = term(
        '\x1b]8;;https://example.com\x1b\\bấm vào đây\x1b]8;;\x1b\\ x',
      );
      final hit = findLinkAt(t, const CellOffset(2, 0), paths: false)!;
      expect(hit.source, LinkSource.hyperlink);
      expect(hit.target, 'https://example.com');
      expect(hit.visible, 'bấm vào đây');
      expect(hit.needsConfirm, isTrue);
    },
  );

  test('OSC 8 whose text is its own address needs no confirmation', () {
    final t = term(
      '\x1b]8;;https://example.com/a\x1b\\https://example.com/a\x1b]8;;\x1b\\',
    );
    expect(
      findLinkAt(t, const CellOffset(3, 0), paths: false)!.needsConfirm,
      isFalse,
    );
  });

  test('a cell past the text, or past the buffer, has none', () {
    final t = term('https://a.b');
    expect(findLinkAt(t, const CellOffset(30, 0), paths: true), isNull);
    expect(findLinkAt(t, const CellOffset(0, 500), paths: true), isNull);
    expect(findLinkAt(t, const CellOffset(0, -1), paths: true), isNull);
  });

  test('finding a link takes well under a millisecond-ish (5x slack)', () {
    final t = term('x ' * 100 + 'https://example.com/path');
    final w = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      findLinkAt(t, const CellOffset(5, 0), paths: true);
    }
    expect(w.elapsedMicroseconds / 200, lessThan(5000));
  });

  test('toString never shows the target', () {
    final t = term('https://secret.example');
    expect(
      findLinkAt(t, const CellOffset(1, 0), paths: false).toString(),
      isNot(contains('secret')),
    );
  });

  test('a link cut by the 8-row window is no link (never open half a URL)', () {
    final t = term('https://example.com/${'a' * 150}', cols: 10);
    expect(findLinkAt(t, const CellOffset(3, 1), paths: false), isNull);
    expect(findLinkAt(t, const CellOffset(3, 7), paths: false), isNull);
  });

  test('a hit is equal to the same hit', () {
    final t = term('see https://example.com/a');
    final a = findLinkAt(t, const CellOffset(10, 0), paths: false)!;
    final b = findLinkAt(t, const CellOffset(12, 0), paths: false)!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
