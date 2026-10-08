import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
import 'package:xterm/xterm.dart';

/// Claude Code (Ink) turns on bracketed paste, focus reports, the kitty
/// keyboard protocol and modifyOtherKeys, hides the cursor, and redraws its
/// spinner and title while the user composes a Vietnamese word. These feed
/// that traffic and drive the platform side of the text-input connection
/// with a Telex composition ("việt "), and assert on the exact bytes the
/// pty receives.
void main() {
  const modes =
      '\x1b[?2004h\x1b[?1004h\x1b[>1u\x1b[>4;2m\x1b[?25l\x1b[?2026h\x1b[?2026l';
  late DesktopTerminal terminal;
  late List<String> sent;
  late FocusNode focus;

  Future<void> pump(WidgetTester tester) async {
    sent = [];
    terminal = DesktopTerminal()..onUserInput = sent.add;
    focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ImeComposeReset(
          child: TerminalView(terminal, focusNode: focus, autofocus: true),
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

  /// v, i, e, e -> ê, j -> ệ, t, then space commits.
  Future<void> telex(WidgetTester tester, {bool redraw = false}) async {
    for (final step in ['v', 'vi', 'vie', 'viê', 'việ', 'việt']) {
      tester.testTextInput.updateEditingValue(marked(step));
      if (redraw) terminal.write('\x1b[2K\x1b[1G✳ Thinking… ${step.length}');
      await tester.pump(const Duration(milliseconds: 30));
    }
    tester.testTextInput.updateEditingValue(committed('việt '));
    await tester.pump();
  }

  testWidgets(
    'Telex after Claude Code\'s modes: plain UTF-8, no paste, no CSI u',
    (tester) async {
      await pump(tester);
      terminal.write(modes);
      expect(terminal.bracketedPasteMode, isTrue);
      await tester.pump();
      await telex(tester);
      expect(sent.join(), 'việt ');
    },
  );

  testWidgets('Telex while Claude Code redraws every 30 ms', (tester) async {
    await pump(tester);
    terminal.write(modes);
    await telex(tester, redraw: true);
    expect(sent.join(), 'việt ');
  });

  testWidgets('output while composing never resets the platform value', (
    tester,
  ) async {
    await pump(tester);
    terminal.write(modes);
    tester.testTextInput.updateEditingValue(marked('viê'));
    await tester.pump();
    tester.testTextInput.log.clear();
    for (var i = 0; i < 20; i++) {
      terminal.write('\x1b[2K\x1b[1G✳ Thinking… $i');
      await tester.pump(const Duration(milliseconds: 30));
    }
    final calls = tester.testTextInput.log.map((c) => c.method).toSet();
    // A setEditingState / setClient / clearClient here would drop the marked
    // text on macOS.
    expect(calls, isNot(contains('TextInput.setEditingState')));
    expect(calls, isNot(contains('TextInput.clearClient')));
    expect(calls, isNot(contains('TextInput.setClient')));
    expect(sent, isEmpty);
  });

  testWidgets('a word of five letters one by one, after the modes', (
    tester,
  ) async {
    await pump(tester);
    terminal.write(modes);
    for (final ch in ['x', 'y', 'z']) {
      tester.testTextInput.updateEditingValue(committed(ch));
      await tester.pump();
    }
    expect(sent.join(), 'xyz');
  });
}
