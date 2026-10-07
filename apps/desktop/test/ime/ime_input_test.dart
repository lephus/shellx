import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/xterm.dart';

/// Vietnamese input on macOS (Telex built in, EVKey, OpenKey) composes with
/// marked text; an input-source switch can close or restart the platform
/// text-input connection. These drive the platform side of the connection
/// and assert on what the terminal writes to the pty.
void main() {
  late Terminal terminal;
  late StringBuffer out;
  late FocusNode focus;

  Future<void> pump(WidgetTester tester) async {
    out = StringBuffer();
    terminal = Terminal()..onOutput = out.write;
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

  testWidgets('marked text then commit reaches the pty', (tester) async {
    await pump(tester);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    expect(out.toString(), '');
    tester.testTextInput.updateEditingValue(committed('ă'));
    await tester.pump();
    expect(out.toString(), 'ă');
  });

  testWidgets('typing still works after the platform closes the connection', (
    tester,
  ) async {
    await pump(tester);
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        const MethodCall('TextInputClient.onConnectionClosed', [1]),
      ),
      (_) {},
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(committed('b'));
    await tester.pump();
    expect(out.toString(), 'b');
  });

  testWidgets('a composition left open by an input-source switch does not '
      'swallow later keys', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    tester.testTextInput.updateEditingValue(TextEditingValue.empty);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(out.toString(), contains('\r'));
  });

  testWidgets('a composition left open when focus leaves does not swallow '
      'keys after focus returns', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(out.toString(), 'a\r');
  });

  testWidgets('a composition left open when the app goes inactive does not '
      'swallow keys when it returns', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(out.toString(), 'a\r');
  });

  testWidgets('a finished composition and plain focus changes write nothing', (
    tester,
  ) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    tester.testTextInput.updateEditingValue(committed('â'));
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    focus.requestFocus();
    await tester.pump();
    expect(out.toString(), 'â');
  });

  CustomTextEditState clientOf(WidgetTester tester, [int index = 0]) =>
      tester.state<CustomTextEditState>(find.byType(CustomTextEdit).at(index));

  testWidgets('focus loss commits the marked text once, typing goes on', (
    tester,
  ) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('việ'));
    await tester.pump();
    focus.unfocus();
    await tester.pump();
    expect(out.toString(), 'việ');
    focus.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(committed('t'));
    await tester.pump();
    expect(out.toString(), 'việt');
  });

  testWidgets('no input connection: the composition is dropped, no throw', (
    tester,
  ) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('việ'));
    await tester.pump();
    clientOf(tester).closeKeyboard();
    expect(clientOf(tester).hasInputConnection, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(out.toString(), '');
    expect(
      clientOf(tester).currentTextEditingValue!.composing.isCollapsed,
      isTrue,
    );
  });

  testWidgets('stale composition: a key the input method ignores commits it, '
      'the next Enter reaches the pty', (tester) async {
    await pump(tester);
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      out.clear();
      tester.testTextInput.updateEditingValue(marked('việ'));
      await tester.pump();
      await tester.sendKeyEvent(key);
      expect(out.toString(), '', reason: 'not before the watchdog: $key');
      await tester.pump(kImeStaleAfter + const Duration(milliseconds: 20));
      expect(out.toString(), 'việ', reason: '$key');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(kImeStaleAfter + const Duration(milliseconds: 20));
      expect(out.toString(), 'việ\r', reason: '$key');
    }
  });

  testWidgets('a Telex sequence where every key changes the value never '
      'trips the watchdog; neither does a modifier alone', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    tester.testTextInput.updateEditingValue(marked('â'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    tester.testTextInput.updateEditingValue(marked('ân'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 300));
    expect(out.toString(), '');
    tester.testTextInput.updateEditingValue(committed('ân'));
    await tester.pump();
    expect(out.toString(), 'ân');
  });

  testWidgets('the watchdog is removed with the widget', (tester) async {
    await pump(tester);
    tester.testTextInput.updateEditingValue(marked('a'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(out.toString(), '');
  });

  testWidgets('a lifecycle change resets only the focused pane', (
    tester,
  ) async {
    final outB = StringBuffer();
    final outA = StringBuffer();
    final termA = Terminal()..onOutput = outA.write;
    final termB = Terminal()..onOutput = outB.write;
    final fa = FocusNode(), fb = FocusNode();
    addTearDown(fa.dispose);
    addTearDown(fb.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: ImeComposeReset(
                child: TerminalView(termA, focusNode: fa, autofocus: true),
              ),
            ),
            Expanded(
              child: ImeComposeReset(child: TerminalView(termB, focusNode: fb)),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(marked('xy'));
    clientOf(tester, 1).updateEditingValue(marked('zz'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(outA.toString(), 'xy');
    expect(outB.toString(), '');
    expect(
      clientOf(tester, 1).currentTextEditingValue!.composing.isCollapsed,
      isFalse,
    );
  });
}
