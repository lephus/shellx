import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/cursor_blinker.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';

void main() {
  test("blinks every 530 ms and the program's hidden cursor stays hidden", () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      final ctl = DesktopTerminalController();
      final b = CursorBlinker(terminal: term, controller: ctl)..start();
      expect(term.cursorVisibleMode, isTrue);
      async.elapse(const Duration(milliseconds: 530));
      expect(term.cursorVisibleMode, isFalse);
      async.elapse(const Duration(milliseconds: 530));
      expect(term.cursorVisibleMode, isTrue);
      term.write('\x1b[?25l');
      async.elapse(const Duration(seconds: 2));
      expect(term.cursorVisibleMode, isFalse);
      term.write('\x1b[?25h');
      b.stop();
      expect(
        term.cursorVisibleMode,
        isTrue,
        reason: 'stop restores what the program wants',
      );
      b.dispose();
    });
  });

  test('stop while the program hides the cursor keeps it hidden', () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      final b = CursorBlinker(
        terminal: term,
        controller: DesktopTerminalController(),
      )..start();
      term.write('\x1b[?25l');
      async.elapse(const Duration(milliseconds: 530));
      b.stop();
      expect(term.cursorVisibleMode, isFalse);
    });
  });

  test('typing makes the cursor solid again at once', () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      final b = CursorBlinker(
        terminal: term,
        controller: DesktopTerminalController(),
      )..start();
      async.elapse(const Duration(milliseconds: 530));
      expect(term.cursorVisibleMode, isFalse);
      b.bump();
      expect(term.cursorVisibleMode, isTrue);
      async.elapse(const Duration(milliseconds: 529));
      expect(term.cursorVisibleMode, isTrue, reason: 'solid for a full period');
      async.elapse(const Duration(milliseconds: 2));
      expect(term.cursorVisibleMode, isFalse);
      b.dispose();
    });
  });

  test('at most 2 repaint requests per second (criterion 6)', () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      final ctl = DesktopTerminalController();
      var n = 0;
      ctl.addListener(() => n++);
      final b = CursorBlinker(terminal: term, controller: ctl)..start();
      async.elapse(const Duration(seconds: 10));
      expect(n, lessThanOrEqualTo(20));
      b.dispose();
    });
  });

  test('stopped means no timer: nothing happens, nothing repaints', () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      final ctl = DesktopTerminalController();
      var n = 0;
      ctl.addListener(() => n++);
      CursorBlinker(terminal: term, controller: ctl)
        ..start()
        ..stop();
      final after = n;
      async.elapse(const Duration(seconds: 5));
      expect(n, after);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the find session does not re-search because the cursor blinked', () {
    fakeAsync((async) {
      final term = DesktopTerminal();
      var notified = 0;
      term.addListener(() => notified++);
      final b = CursorBlinker(
        terminal: term,
        controller: DesktopTerminalController(),
      )..start();
      async.elapse(const Duration(seconds: 3));
      expect(notified, 0);
      b.dispose();
    });
  });
}
