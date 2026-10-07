import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/copy_mode.dart';

class ListBuffer implements CopyModeBuffer {
  ListBuffer(this.rows, {this.columns = 20});
  final List<String> rows;
  @override
  final int columns;
  @override
  int get rowCount => rows.length;
  @override
  String rowText(int row) => rows[row];
  @override
  bool isWrapped(int row) => false;
}

CopyKey k(LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) =>
    CopyKey(key, ctrl: ctrl, shift: shift);

CopyModeState at(int row, int col) => CopyModeState(row: row, col: col);

CopyModeState stay(CopyResult r) => (r as Stay).state;

void main() {
  final b = ListBuffer(['alpha beta  gamma', 'one two', '', 'last line here']);

  test('h j k l move and clamp at the edges', () {
    var s = at(0, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyL), pageRows: 4));
    expect((s.row, s.col), (0, 1));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyH), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyH), pageRows: 4));
    expect(s.col, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyJ), pageRows: 4));
    expect(s.row, 1);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyK), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyK), pageRows: 4));
    expect(s.row, 0);
  });

  test('w b e move by word (letters, digits and _ make a word)', () {
    var s = at(0, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyW), pageRows: 4));
    expect(s.col, 6); // beta
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyE), pageRows: 4));
    expect(s.col, 9); // end of beta
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyB), pageRows: 4));
    expect(s.col, 6);
  });

  test('w and b cross rows; an empty row is a stop', () {
    var s = at(0, 12);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyW), pageRows: 4));
    expect((s.row, s.col), (1, 0));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyW), pageRows: 4));
    expect((s.row, s.col), (1, 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyW), pageRows: 4));
    expect((s.row, s.col), (2, 0));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyW), pageRows: 4));
    expect((s.row, s.col), (3, 0));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyB), pageRows: 4));
    expect((s.row, s.col), (2, 0));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyB), pageRows: 4));
    expect((s.row, s.col), (1, 4));
  });

  test('0 ^ \$ jump within the line', () {
    var s = at(0, 8);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.digit0), pageRows: 4));
    expect(s.col, 0);
    s = stay(
      applyCopyKey(
        b,
        s,
        k(LogicalKeyboardKey.digit4, shift: true),
        pageRows: 4,
      ),
    );
    expect(s.col, 16); // last non-blank of 'alpha beta  gamma'
    final indented = ListBuffer(['   x y']);
    s = stay(
      applyCopyKey(
        indented,
        at(0, 5),
        k(LogicalKeyboardKey.digit6, shift: true),
        pageRows: 4,
      ),
    );
    expect(s.col, 3);
  });

  test('gg and G; a lone g waits for the second key', () {
    var s = at(2, 3);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyG), pageRows: 4));
    expect(s.pending, 'g');
    expect(s.row, 2);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyG), pageRows: 4));
    expect((s.row, s.pending), (0, ''));
    s = stay(
      applyCopyKey(b, s, k(LogicalKeyboardKey.keyG, shift: true), pageRows: 4),
    );
    expect(s.row, 3);
  });

  test('any other key after g clears it and is handled', () {
    var s = at(0, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyG), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyJ), pageRows: 4));
    expect((s.row, s.pending), (1, ''));
  });

  test('Ctrl-d / Ctrl-u move half a page, Ctrl-f / Ctrl-b a page', () {
    final tall = ListBuffer([for (var i = 0; i < 100; i++) 'row $i']);
    var s = at(10, 0);
    s = stay(
      applyCopyKey(
        tall,
        s,
        k(LogicalKeyboardKey.keyD, ctrl: true),
        pageRows: 20,
      ),
    );
    expect(s.row, 20);
    s = stay(
      applyCopyKey(
        tall,
        s,
        k(LogicalKeyboardKey.keyF, ctrl: true),
        pageRows: 20,
      ),
    );
    expect(s.row, 40);
    s = stay(
      applyCopyKey(
        tall,
        s,
        k(LogicalKeyboardKey.keyU, ctrl: true),
        pageRows: 20,
      ),
    );
    expect(s.row, 30);
    s = stay(
      applyCopyKey(
        tall,
        s,
        k(LogicalKeyboardKey.keyB, ctrl: true),
        pageRows: 20,
      ),
    );
    expect(s.row, 10);
  });

  test(
    'v starts a character selection that follows the cursor; y yanks it',
    () {
      var s = at(0, 0);
      s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyV), pageRows: 4));
      expect(s.kind, SelectKind.char);
      s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyE), pageRows: 4));
      final r = applyCopyKey(b, s, k(LogicalKeyboardKey.keyY), pageRows: 4);
      expect(r, isA<Yank>());
      final y = (r as Yank).state;
      expect(selectedText(b, y), 'alpha');
    },
  );

  test('a selection made backwards reads the same', () {
    var s = at(0, 4);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyV), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyH), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyH), pageRows: 4));
    expect(selectedText(b, s), 'pha');
  });

  test('y with nothing selected yanks the character under the cursor', () {
    final r = applyCopyKey(
      b,
      at(0, 1),
      k(LogicalKeyboardKey.keyY),
      pageRows: 4,
    );
    expect(selectedText(b, (r as Yank).state), 'l');
  });

  test('the same selection key ends the selection; another switches it', () {
    var s = at(0, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyV), pageRows: 4));
    s = stay(
      applyCopyKey(b, s, k(LogicalKeyboardKey.keyV, shift: true), pageRows: 4),
    );
    expect(s.kind, SelectKind.line);
    s = stay(
      applyCopyKey(b, s, k(LogicalKeyboardKey.keyV, shift: true), pageRows: 4),
    );
    expect(s.kind, SelectKind.none);
  });

  test('V selects whole lines, Ctrl-v a block', () {
    var s = at(0, 2);
    s = stay(
      applyCopyKey(b, s, k(LogicalKeyboardKey.keyV, shift: true), pageRows: 4),
    );
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyJ), pageRows: 4));
    expect(selectedText(b, s), 'alpha beta  gamma\none two');
    var t = at(0, 2);
    t = stay(
      applyCopyKey(b, t, k(LogicalKeyboardKey.keyV, ctrl: true), pageRows: 4),
    );
    t = stay(applyCopyKey(b, t, k(LogicalKeyboardKey.keyL), pageRows: 4));
    t = stay(applyCopyKey(b, t, k(LogicalKeyboardKey.keyJ), pageRows: 4));
    expect(selectedText(b, t), 'ph\ne ');
  });

  test('Esc clears the selection first, then leaves; q leaves', () {
    var s = at(0, 0);
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyV), pageRows: 4));
    s = stay(applyCopyKey(b, s, k(LogicalKeyboardKey.escape), pageRows: 4));
    expect(s.kind, SelectKind.none);
    expect(
      applyCopyKey(b, s, k(LogicalKeyboardKey.escape), pageRows: 4),
      isA<Exit>(),
    );
    expect(
      applyCopyKey(b, s, k(LogicalKeyboardKey.keyQ), pageRows: 4),
      isA<Exit>(),
    );
  });

  test('/ opens the find bar, n and N step its matches', () {
    expect(
      applyCopyKey(b, at(0, 0), k(LogicalKeyboardKey.slash), pageRows: 4),
      isA<OpenFind>(),
    );
    expect(
      applyCopyKey(b, at(0, 0), k(LogicalKeyboardKey.keyN), pageRows: 4),
      isA<FindNext>(),
    );
    expect(
      applyCopyKey(
        b,
        at(0, 0),
        k(LogicalKeyboardKey.keyN, shift: true),
        pageRows: 4,
      ),
      isA<FindPrev>(),
    );
  });

  test('an unknown key is swallowed and changes nothing', () {
    final s = at(1, 2);
    expect(
      stay(applyCopyKey(b, s, k(LogicalKeyboardKey.keyZ), pageRows: 4)),
      s,
    );
  });

  test('keys are matched by physical key: the character is irrelevant', () {
    // A Telex/Hangul layout can deliver another character for the H key;
    // CopyKey carries only the LogicalKeyboardKey.
    final s = stay(
      applyCopyKey(b, at(0, 3), k(LogicalKeyboardKey.keyH), pageRows: 4),
    );
    expect(s.col, 2);
  });

  test('toString never shows text', () {
    expect(at(1, 2).toString(), contains('…'));
    expect(k(LogicalKeyboardKey.keyH).toString(), contains('…'));
  });
}
