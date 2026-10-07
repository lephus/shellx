import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/xterm.dart';

/// A10 D30 (gap analysis §2, cmux #15432): whatever the soft keyboard or an
/// IME sends reaches the terminal exactly once.
void main() {
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late FocusNode focus;
  late List<String> out;

  setUp(() {
    keys = ExtraKeysController();
    terminal = ShellxTerminal(modifiers: keys);
    out = [];
    terminal.onOutput = out.add;
    focus = FocusNode();
  });

  tearDown(() => keys.dispose());

  Future<void> pumpView(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, focusNode: focus, autofocus: true, deleteDetection: true),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    });
    focus.requestFocus();
    await tester.pump();
    await tester.pump();
  }

  /// What the platform's keyboard says after the user typed: the two guard spaces the view
  /// plants, then [typed], [composing] marking the part still being composed.
  TextEditingValue keyboard(String typed, {TextRange composing = TextRange.empty}) => TextEditingValue(
    text: '  $typed',
    selection: TextSelection.collapsed(offset: 2 + typed.length),
    composing: composing,
  );

  testWidgets('a plain letter from the soft keyboard is sent once', (tester) async {
    await pumpView(tester);
    tester.testTextInput.updateEditingValue(keyboard('a'));
    await tester.pump();
    expect(out, ['a']);
  });

  testWidgets('a Telex word is held while it is composed and sent once when it is committed', (tester) async {
    await pumpView(tester);
    for (final stage in ['v', 'vi', 'viê']) {
      tester.testTextInput.updateEditingValue(keyboard(stage, composing: TextRange(start: 2, end: 2 + stage.length)));
      await tester.pump();
    }
    expect(out, isEmpty, reason: 'nothing leaves the phone while the word is still being composed');
    tester.testTextInput.updateEditingValue(keyboard('viê'));
    await tester.pump();
    expect(out, ['viê']);
  });

  testWidgets('a committed word is not sent again when the keyboard repeats the state', (tester) async {
    await pumpView(tester);
    tester.testTextInput.updateEditingValue(keyboard('xin'));
    await tester.pump();
    // After a commit the view resets the field to its two guard spaces; a keyboard that repeats
    // the reset state (no text after them) must send nothing.
    tester.testTextInput.updateEditingValue(keyboard(''));
    await tester.pump();
    expect(out, ['xin']);
  });

  testWidgets('a physical key that also arrives as text is sent once', (tester) async {
    await pumpView(tester);
    // Hardware keyboards deliver the character through the text channel; the key event for a
    // plain letter must not send it a second time.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
    tester.testTextInput.updateEditingValue(keyboard('a'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(out.join(), 'a');
  });

  testWidgets('Enter from a physical keyboard is one carriage return', (tester) async {
    await pumpView(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(out, ['\r']);
  });

  testWidgets('Backspace is one DEL', (tester) async {
    await pumpView(tester);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: ' ', selection: TextSelection.collapsed(offset: 1)),
    );
    await tester.pump();
    expect(out, ['\x7f']);
  });

  testWidgets('an empty keyboard reset does not consume a one-shot Ctrl', (tester) async {
    await pumpView(tester);
    keys.tapModifier(ExtraKey.ctrl);
    tester.testTextInput.updateEditingValue(keyboard(''));
    await tester.pump();
    expect(out, isEmpty);
    expect(keys.hasActiveModifiers, isTrue);
  });
}
