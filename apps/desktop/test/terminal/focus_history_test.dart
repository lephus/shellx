import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';

FocusEntry e(int tab, [int? pane]) => FocusEntry(tab, pane ?? tab);
bool alwaysAlive(FocusEntry _) => true;

void main() {
  test('A → B → C: back goes C→B→A, forward returns', () {
    final h = FocusHistory()
      ..visit(e(1))
      ..visit(e(2))
      ..visit(e(3));
    expect(h.back(alwaysAlive), e(2));
    expect(h.back(alwaysAlive), e(1));
    expect(h.back(alwaysAlive), isNull, reason: 'at the start: nothing');
    expect(h.forward(alwaysAlive), e(2));
    expect(h.forward(alwaysAlive), e(3));
    expect(h.forward(alwaysAlive), isNull);
  });

  test('visiting the same place twice does not add an entry', () {
    final h = FocusHistory()
      ..visit(e(1))
      ..visit(e(1))
      ..visit(e(2));
    expect(h.back(alwaysAlive), e(1));
    expect(h.back(alwaysAlive), isNull);
  });

  test('a new visit after going back cuts the forward part (as a browser)', () {
    final h = FocusHistory()
      ..visit(e(1))
      ..visit(e(2))
      ..visit(e(3));
    h.back(alwaysAlive);
    h.visit(e(9));
    expect(h.forward(alwaysAlive), isNull);
    expect(h.back(alwaysAlive), e(2));
  });

  test('dead entries are skipped in both directions', () {
    final h = FocusHistory()
      ..visit(e(1))
      ..visit(e(2))
      ..visit(e(3));
    bool noTwo(FocusEntry x) => x.tabId != 2;
    expect(h.back(noTwo), e(1));
    expect(h.forward(noTwo), e(3));
  });

  test('with only dead entries ahead the position does not move', () {
    final h = FocusHistory()
      ..visit(e(1))
      ..visit(e(2));
    expect(h.back((x) => false), isNull);
    expect(h.current, e(2));
  });

  test('keeps at most 50 entries', () {
    final h = FocusHistory(max: 50);
    for (var i = 0; i < 80; i++) {
      h.visit(e(i));
    }
    var n = 0;
    while (h.back(alwaysAlive) != null) {
      n++;
    }
    expect(n, 49);
  });

  test('a pane of the same tab is another place', () {
    final h = FocusHistory()
      ..visit(e(1, 10))
      ..visit(e(1, 11));
    expect(h.back(alwaysAlive), e(1, 10));
  });

  test('toString never shows ids of what the user looked at', () {
    expect(e(1).toString(), '…');
    expect(FocusHistory().toString(), '…');
  });
}
