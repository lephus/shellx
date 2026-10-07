import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/ime_compose_reset.dart';
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
    expect(out.toString(), '\r');
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
    expect(out.toString(), '\r');
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
}
