import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/cursor_blinker.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
import 'package:xterm/xterm.dart';

/// A realistic Claude Code session against the text-input channel: every
/// platform call the terminal makes while a Vietnamese word is composed
/// (marked text) is recorded, with the blinker running, the cursor toggled
/// and frames wrapped in synchronized output arriving in several pty reads.
/// On macOS each of those calls reaches the input method (IMKit), so a call
/// that is not needed is a call that can disturb the composition.
void main() {
  const modes = '\x1b[?2004h\x1b[?1004h\x1b[>1u\x1b[>4;2m\x1b[?25l';
  late DesktopTerminal terminal;
  late DesktopTerminalController controller;
  late CursorBlinker blinker;
  late List<String> sent;
  late FocusNode focus;

  Future<void> pump(WidgetTester tester) async {
    sent = [];
    terminal = DesktopTerminal()..onUserInput = sent.add;
    controller = DesktopTerminalController();
    blinker = CursorBlinker(terminal: terminal, controller: controller)
      ..start();
    focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ImeComposeReset(
          child: TerminalView(
            terminal,
            controller: controller,
            focusNode: focus,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TextEditingValue marked(String t) => TextEditingValue(
    text: t,
    selection: TextSelection.collapsed(offset: t.length),
    composing: TextRange(start: 0, end: t.length),
  );
  TextEditingValue committed(String t) => TextEditingValue(
    text: t,
    selection: TextSelection.collapsed(offset: t.length),
  );

  /// One Ink frame: erase the old one, redraw spinner, input box and footer,
  /// park the cursor, all inside `?2026h ... ?2026l` and split in three pty
  /// reads (a read is a few KB at most; frames are not aligned to it).
  Future<void> frame(WidgetTester tester, int n) async {
    terminal.write('\x1b[?2026h\x1b[3A\x1b[2K\x1b[1G* Thinking $n\n');
    await tester.pump(const Duration(milliseconds: 3));
    terminal.write('\x1b[2K> hello wor\n\x1b[2K? for shortcuts');
    await tester.pump(const Duration(milliseconds: 3));
    terminal.write('\x1b[1A\x1b[12G\x1b[?25l\x1b[?2026l');
  }

  /// Rows for the frame's cursor-up to go to, and Claude's modes.
  Future<void> seed(WidgetTester tester) async {
    terminal.write('one\r\ntwo\r\nthree\r\nfour');
    terminal.write(modes);
    await tester.pump();
  }

  /// testWidgets that stops the blinker's periodic timer before the test's
  /// own invariants run.
  void session(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        blinker.dispose();
        await tester.pumpWidget(const SizedBox());
      });

  Map<String, int> counts(WidgetTester tester) {
    final m = <String, int>{};
    for (final c in tester.testTextInput.log) {
      m[c.method] = (m[c.method] ?? 0) + 1;
    }
    return m;
  }

  session('no connection churn or editing-state push while composing '
      'under a Claude session (blink, cursor toggles, frames, resize, '
      'scrollback)', (tester) async {
    await pump(tester);
    await seed(tester);
    tester.testTextInput.updateEditingValue(marked('viê'));
    await tester.pump();
    tester.testTextInput.log.clear();
    for (var i = 0; i < 40; i++) {
      await frame(tester, i);
      terminal.write(i.isEven ? '\x1b[?25h' : '\x1b[?25l');
      if (i == 10) terminal.resize(70, 20);
      if (i == 20) terminal.write('line\r\n' * 12000);
      await tester.pump(const Duration(milliseconds: 80));
    }
    final calls = counts(tester).keys.toSet();
    for (final bad in [
      'TextInput.setClient',
      'TextInput.clearClient',
      'TextInput.setEditingState',
      'TextInput.show',
      'TextInput.hide',
    ]) {
      expect(calls, isNot(contains(bad)), reason: bad);
    }
    expect(sent, isEmpty);
  });

  session('frames split over several reads tell the input method nothing '
      'while the cursor ends where it was', (tester) async {
    await pump(tester);
    await seed(tester);
    tester.testTextInput.updateEditingValue(marked('viê'));
    await tester.pump();
    await frame(tester, 0);
    await tester.pump(const Duration(milliseconds: 80));
    tester.testTextInput.log.clear();
    for (var i = 1; i <= 20; i++) {
      await frame(tester, i);
      await tester.pump(const Duration(milliseconds: 80));
    }
    final m = counts(tester);
    // Each call makes the input method invalidate its character
    // coordinates (and the caret/candidate window jumps to a half-drawn
    // row).
    expect(m['TextInput.setCaretRect'] ?? 0, 0);
    expect(m['TextInput.setEditableSizeAndTransform'] ?? 0, 0);
  });

  session('a frame whose end never comes is still shown', (tester) async {
    await pump(tester);
    terminal.write('\x1b[?2026hhalf frame');
    await tester.pump(const Duration(seconds: 1));
    var seen = false;
    terminal.addListener(() => seen = true);
    terminal.write('x');
    await tester.pump(const Duration(seconds: 1));
    expect(seen, isTrue);
    expect(terminal.buffer.lines[0].getText(), contains('half frame'));
    terminal.write('\x1b[?2026l');
    await tester.pump(const Duration(seconds: 1));
  });

  session('a hidden cursor does not stop the input method', (tester) async {
    await pump(tester);
    await seed(tester);
    expect(terminal.cursorVisibleMode, isFalse);
    tester.testTextInput.updateEditingValue(marked('v'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(committed('v'));
    await tester.pump();
    expect(sent.join(), 'v');
  });

  session('a Telex word typed while output streams commits "việt " once', (
    tester,
  ) async {
    await pump(tester);
    await seed(tester);
    tester.testTextInput.log.clear();
    var n = 0;
    for (final step in ['v', 'vi', 'vie', 'viê', 'việ', 'việt']) {
      tester.testTextInput.updateEditingValue(marked(step));
      await frame(tester, n++);
      terminal.write(n.isEven ? '\x1b[?25h' : '\x1b[?25l');
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(sent, isEmpty, reason: 'nothing leaves before the commit');
    tester.testTextInput.updateEditingValue(committed('việt '));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await frame(tester, n++);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(sent, ['việt ']);
    // xterm hands the platform an empty value back after the commit.
    final resets = tester.testTextInput.log
        .where((c) => c.method == 'TextInput.setEditingState')
        .length;
    expect(resets, 1);
  });
}
