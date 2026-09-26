import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late List<String> out;

  setUp(() {
    keys = ExtraKeysController();
    out = [];
    terminal = ShellxTerminal(modifiers: keys)..onOutput = out.add;
  });

  tearDown(() => keys.dispose());

  /// What TerminalView does with a soft-keyboard character.
  void typeOnSoftKeyboard(String char, TerminalKey key) {
    if (!terminal.keyInput(key)) terminal.textInput(char);
  }

  test('soft keyboard: sticky Ctrl turns "c" into ^C', () {
    keys.tapModifier(ExtraKey.ctrl);
    typeOnSoftKeyboard('c', TerminalKey.keyC);
    expect(out, ['\x03']);
    expect(keys.hasActiveModifiers, isFalse);
  });

  test('soft keyboard: sticky Alt keeps the typed case', () {
    keys.tapModifier(ExtraKey.alt);
    typeOnSoftKeyboard('B', TerminalKey.keyB);
    expect(out, ['\x1bB']);
    keys.tapModifier(ExtraKey.alt);
    typeOnSoftKeyboard('b', TerminalKey.keyB);
    expect(out.last, '\x1bb');
  });

  test('soft keyboard without modifiers sends the text, Return as CR', () {
    typeOnSoftKeyboard('q', TerminalKey.keyQ);
    terminal.textInput('\n');
    terminal.textInput('xin chào');
    expect(out, ['q', '\r', 'xin chào']);
  });

  test('sticky Alt applies to non-text keys such as arrows', () {
    keys.tapModifier(ExtraKey.alt);
    expect(terminal.keyInput(TerminalKey.arrowLeft), isTrue);
    expect(out, ['\x1b[1;3D']);
    expect(keys.hasActiveModifiers, isFalse);
  });

  test('hardware Ctrl works on its own and leaves sticky modifiers alone', () {
    keys.tapModifier(ExtraKey.alt);
    expect(terminal.keyInput(TerminalKey.keyC, ctrl: true), isTrue);
    expect(out, ['\x03']);
    expect(keys.alt.value, ModifierLatch.oneShot);
  });

  test('application cursor mode comes from DECCKM', () {
    terminal.write('\x1b[?1h');
    terminal.keyInput(TerminalKey.arrowUp);
    expect(out, ['\x1bOA']);
  });

  test('textInput (IME/clipboard chip) strips ESC and C1, so it cannot inject sequences', () {
    terminal.textInput('echo harmless\x1b[201~rm -rf ~/x\n');
    terminal.textInput('a\u009b201~b');
    expect(out, ['echo harmless[201~rm -rf ~/x\r', 'a201~b']);
  });

  test('paste: bracketed when enabled, CR line breaks, never modified', () {
    keys.tapModifier(ExtraKey.ctrl);
    terminal.paste('echo 1\necho 2');
    terminal.write('\x1b[?2004h');
    terminal.paste('a\r\nb');
    expect(out, ['echo 1\recho 2', '\x1b[200~a\rb\x1b[201~']);
    expect(keys.ctrl.value, ModifierLatch.oneShot);
  });

  test('paste: an embedded end marker cannot escape bracketed paste', () {
    terminal.write('\x1b[?2004h');
    terminal.paste('echo harmless\x1b[201~rm -rf ~/x\n');
    final sent = out.join();
    expect('\x1b[200~'.allMatches(sent), hasLength(1));
    expect('\x1b[201~'.allMatches(sent), hasLength(1));
    expect(sent, startsWith('\x1b[200~'));
    expect(sent, endsWith('\x1b[201~'));
    final inner = sent.substring('\x1b[200~'.length, sent.length - '\x1b[201~'.length);
    expect(inner.contains('\x1b'), isFalse);
    expect(inner, 'echo harmless[201~rm -rf ~/x\r');
  });

  test('paste: the 8-bit CSI (U+009B) is stripped as well', () {
    terminal.write('\x1b[?2004h');
    terminal.paste('a\u009b201~b');
    expect(out, ['\x1b[200~a201~b\x1b[201~']);
  });

  test('paste without bracketed mode strips ESC too, so no key sequence is injected', () {
    terminal.paste('ls\x1b[A\x1bOB\tx\r\n');
    expect(out, ['ls[AOB\tx\r']);
  });

  group('hardware keyboard (TerminalView.keyInput has no textInput fallback)', () {
    // TerminalView's raw KeyEvent path (`_handleKeyEvent`) calls only
    // Terminal.keyInput and never falls back to textInput() the way the soft
    // keyboard's `_onInsert` does, so a text key must be handled inside
    // keyInput() itself when it truly comes from a physical key press.
    Future<void> pumpTerminalView(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Material(child: TerminalView(terminal, autofocus: true))));
      await tester.pump();
    }

    testWidgets('sticky Ctrl + a real KeyEvent for "c" sends ^C', (tester) async {
      await pumpTerminalView(tester);
      keys.tapModifier(ExtraKey.ctrl);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      expect(out, ['\x03']);
      expect(keys.hasActiveModifiers, isFalse);
    });

    testWidgets('sticky Alt + a real KeyEvent for "x" sends ESC x', (tester) async {
      await pumpTerminalView(tester);
      keys.tapModifier(ExtraKey.alt);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      expect(out, ['\x1bx']);
      expect(keys.hasActiveModifiers, isFalse);
    });

    testWidgets('the soft-keyboard path is unaffected: no KeyEvent means no hardware key is down', (tester) async {
      await pumpTerminalView(tester);
      keys.tapModifier(ExtraKey.alt);
      // Calling keyInput() directly, like TerminalView's soft-keyboard
      // `_onInsert` does, without a real KeyEvent: HardwareKeyboard reports
      // the key as not pressed, so this must still fall back to textInput()
      // and keep the real typed case.
      typeOnSoftKeyboard('B', TerminalKey.keyB);
      expect(out, ['\x1bB']);
    });
  });
}
