import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/cursor_shift.dart';

void main() {
  test('no keyboard: no shift', () {
    expect(cursorShift(cursorBottom: 700, viewportHeight: 800, keyboardInset: 0), 0);
  });

  test('the cursor row above the keyboard needs no shift', () {
    expect(cursorShift(cursorBottom: 400, viewportHeight: 800, keyboardInset: 300), 0);
  });

  test('the cursor hidden by the keyboard shifts the view up just enough (margin 8)', () {
    // visible bottom = 800 - 300 = 500; the cursor ends at 700 → needs 700 - 492 = 208
    expect(cursorShift(cursorBottom: 700, viewportHeight: 800, keyboardInset: 300), 208);
  });

  test('never shifts more than the keyboard covers', () {
    expect(cursorShift(cursorBottom: 1200, viewportHeight: 800, keyboardInset: 300), 300);
  });

  test('never negative', () {
    expect(cursorShift(cursorBottom: 10, viewportHeight: 800, keyboardInset: 300), 0);
  });

  test('a cursor just inside the margin does not move the view', () {
    expect(cursorShift(cursorBottom: 492, viewportHeight: 800, keyboardInset: 300), 0);
    expect(cursorShift(cursorBottom: 493, viewportHeight: 800, keyboardInset: 300), 1);
  });
}
