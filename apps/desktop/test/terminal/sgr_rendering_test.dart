import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:xterm/xterm.dart';

/// What the cells of the first row would paint like: the attribute flags and
/// colours the xterm painter reads. Claude Code (Ink, chalk) turns the
/// terminal's modifyOtherKeys on with `ESC[>4;2m` and off with `ESC[>4m`;
/// xterm 4.0.0 reads those as SGR 4 and 2 (underline, faint) and never
/// clears them, so every line was underlined.
CellData _cell(Terminal t, int x, [int y = 0]) {
  final c = CellData.empty();
  t.buffer.lines[y].getCellData(x, c);
  return c;
}

bool _has(CellData c, int flag) => c.flags & flag != 0;

String _text(Terminal t) => t.buffer.lines[0].getText(0, 20).trimRight();

void main() {
  late DesktopTerminal t;
  setUp(() => t = DesktopTerminal());

  group('modifyOtherKeys / kitty keyboard requests are not SGR', () {
    test('ESC[>4;2m (enable) leaves the next text plain', () {
      t.write('\x1b[>4;2mhello');
      final c = _cell(t, 0);
      expect(_has(c, CellFlags.underline), isFalse);
      expect(_has(c, CellFlags.faint), isFalse);
      expect(_text(t), 'hello');
    });

    test('ESC[>4m (disable) does not underline', () {
      t.write('\x1b[>4mhello');
      expect(_has(_cell(t, 0), CellFlags.underline), isFalse);
    });

    test('ESC[?4m does not underline', () {
      t.write('\x1b[?4mhello');
      expect(_has(_cell(t, 0), CellFlags.underline), isFalse);
    });

    test('kitty push and pop leave no text behind', () {
      t.write('\x1b[>1u\x1b[<u\x1b[>5uok');
      expect(_text(t), 'ok');
    });

    test('a real SGR after the request still applies', () {
      t.write('\x1b[>4;2m\x1b[1mb\x1b[22m');
      expect(_has(_cell(t, 0), CellFlags.bold), isTrue);
      expect(_has(_cell(t, 0), CellFlags.underline), isFalse);
    });
  });

  group('colon sub-parameters', () {
    test('4:0 is underline off, not a black background', () {
      t.write('\x1b[4mu\x1b[4:0mx');
      expect(_has(_cell(t, 0), CellFlags.underline), isTrue);
      final x = _cell(t, 1);
      expect(_has(x, CellFlags.underline), isFalse);
      expect(x.background, 0);
    });

    test('4:3 (curly) underlines and does not set a yellow background', () {
      t.write('\x1b[4:3mx\x1b[4:0my');
      final x = _cell(t, 0);
      expect(_has(x, CellFlags.underline), isTrue);
      expect(x.background, 0);
      expect(_has(_cell(t, 1), CellFlags.underline), isFalse);
    });

    test('38:2::R:G:B equals 38;2;R;G;B', () {
      final a = DesktopTerminal()..write('\x1b[38;2;153;153;153mg');
      t.write('\x1b[38:2::153:153:153mg');
      expect(_cell(t, 0).foreground, _cell(a, 0).foreground);
      expect(_cell(t, 0).foreground, isNot(0));
    });

    test('38:2:R:G:B (no colour space) and 38:5:N work', () {
      final a = DesktopTerminal()..write('\x1b[38;2;1;2;3ma');
      final b = DesktopTerminal()..write('\x1b[38;5;244mb');
      t.write('\x1b[38:2:1:2:3ma\x1b[38:5:244mb');
      expect(_cell(t, 0).foreground, _cell(a, 0).foreground);
      expect(_cell(t, 1).foreground, _cell(b, 0).foreground);
    });

    test('58 (underline colour) is dropped in both forms, nothing leaks', () {
      t.write('\x1b[58:2::255:0:0mx\x1b[58;2;255;0;0my\x1b[58;5;9mz\x1b[59mw');
      for (var i = 0; i < 4; i++) {
        final c = _cell(t, i);
        expect(c.flags, 0, reason: 'cell $i');
        expect(c.foreground, 0, reason: 'cell $i');
        expect(c.background, 0, reason: 'cell $i');
      }
      expect(_text(t), 'xyzw');
    });
  });

  group('SGR basics stay as they were', () {
    test('2 then 22 and 1 then 22', () {
      t.write('\x1b[2md\x1b[22mn\x1b[1mb\x1b[22mn');
      expect(_has(_cell(t, 0), CellFlags.faint), isTrue);
      expect(_has(_cell(t, 1), CellFlags.faint), isFalse);
      expect(_has(_cell(t, 2), CellFlags.bold), isTrue);
      expect(_has(_cell(t, 3), CellFlags.bold), isFalse);
    });

    test('4 then 24', () {
      t.write('\x1b[4mu\x1b[24mn');
      expect(_has(_cell(t, 0), CellFlags.underline), isTrue);
      expect(_has(_cell(t, 1), CellFlags.underline), isFalse);
    });

    test('a Claude Code like line', () {
      t.write(
        '\x1b[?2004h\x1b[>1u\x1b[>4;2m'
        '\x1b[1mClaude Code\x1b[22m \x1b[2mv2.1.294\x1b[22m'
        '\x1b[38;2;153;153;153m grey\x1b[39m \x1b[7mINV\x1b[27m\x1b[24m',
      );
      for (var i = 0; i < 20; i++) {
        expect(_has(_cell(t, i), CellFlags.underline), isFalse, reason: '$i');
      }
      expect(_has(_cell(t, 0), CellFlags.bold), isTrue);
      expect(_has(_cell(t, 12), CellFlags.bold), isFalse);
      expect(_has(_cell(t, 13), CellFlags.faint), isTrue);
    });

    test('a sequence split across writes is still understood', () {
      t.write('\x1b[>');
      t.write('4;2mhi\x1b[4');
      t.write(':0mx');
      expect(_text(t), 'hix');
      expect(_has(_cell(t, 0), CellFlags.underline), isFalse);
      expect(_cell(t, 2).background, 0);
    });
  });
}
