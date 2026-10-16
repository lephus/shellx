import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_shortcuts.dart';
import 'package:xterm/core.dart';

void main() {
  group('shellxInputHandler', () {
    late List<String> out;
    late Terminal terminal;

    setUp(() {
      out = [];
      terminal = Terminal(inputHandler: shellxInputHandler, onOutput: out.add);
    });

    String press(TerminalKey key, {bool shift = false, bool alt = false, bool ctrl = false}) {
      out.clear();
      terminal.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
      return out.join();
    }

    test('arrows follow DECCKM (application cursor mode)', () {
      expect(press(TerminalKey.arrowUp), '\x1b[A');
      terminal.write('\x1b[?1h');
      expect(press(TerminalKey.arrowUp), '\x1bOA');
      expect(press(TerminalKey.arrowLeft), '\x1bOD');
      expect(press(TerminalKey.home), '\x1bOH');
      terminal.write('\x1b[?1l');
      expect(press(TerminalKey.arrowDown), '\x1b[B');
      expect(press(TerminalKey.end), '\x1b[F');
    });

    test('modifier parameter is 1 + shift + 2*alt + 4*ctrl', () {
      expect(press(TerminalKey.arrowUp, shift: true), '\x1b[1;2A');
      expect(press(TerminalKey.arrowLeft, alt: true), '\x1b[1;3D');
      expect(press(TerminalKey.arrowRight, ctrl: true), '\x1b[1;5C');
      expect(press(TerminalKey.arrowLeft, ctrl: true, alt: true), '\x1b[1;7D');
      terminal.write('\x1b[?1h');
      expect(press(TerminalKey.arrowUp, alt: true), '\x1b[1;3A');
    });

    test('other keys still use xterm defaults', () {
      expect(press(TerminalKey.pageUp), '\x1b[5~');
      expect(press(TerminalKey.pageDown, alt: true), '\x1b[6;3~');
      expect(press(TerminalKey.escape), '\x1b');
      expect(press(TerminalKey.tab), '\t');
      expect(press(TerminalKey.enter), '\r');
      expect(press(TerminalKey.keyC, ctrl: true), '\x03');
    });
  });

  test('controlCharacterFor', () {
    expect(controlCharacterFor('c'), '\x03');
    expect(controlCharacterFor('C'), '\x03');
    expect(controlCharacterFor('['), '\x1b');
    expect(controlCharacterFor('\\'), '\x1c');
    expect(controlCharacterFor('_'), '\x1f');
    expect(controlCharacterFor('@'), '\x00');
    expect(controlCharacterFor(' '), '\x00');
    expect(controlCharacterFor('/'), '\x1f');
    expect(controlCharacterFor('?'), '\x7f');
    expect(controlCharacterFor('|'), isNull);
    expect(controlCharacterFor('ab'), isNull);
  });

  test('applyModifiersToText', () {
    expect(applyModifiersToText('c', ctrl: true, alt: false), '\x03');
    expect(applyModifiersToText('b', ctrl: false, alt: true), '\x1bb');
    expect(applyModifiersToText('B', ctrl: false, alt: true), '\x1bB');
    expect(applyModifiersToText('x', ctrl: true, alt: true), '\x1b\x18');
    expect(applyModifiersToText('ab', ctrl: true, alt: false), '\x01b');
    expect(applyModifiersToText('|', ctrl: true, alt: false), '|');
    expect(applyModifiersToText('ệ', ctrl: false, alt: true), '\x1bệ');
    expect(applyModifiersToText('😀x', ctrl: false, alt: true), '\x1b😀x');
    expect(applyModifiersToText('', ctrl: true, alt: true), '');
    expect(applyModifiersToText('q', ctrl: false, alt: false), 'q');
  });

  test('newline normalisation', () {
    expect(normalizeTypedText('ls\n'), 'ls\r');
    expect(normalizePastedText('a\r\nb\nc'), 'a\rb\rc');
  });

  group('typed text (IME) is sanitised', () {
    // Gboard's clipboard chip and IME commit text reach `normalizeTypedText` via
    // `TerminalView._onInsert` -> `Terminal.textInput`, with no sanitising of their own.

    test('ESC is stripped, so IME text cannot end bracketed paste on its own', () {
      expect(normalizeTypedText('echo harmless\x1b[201~rm -rf ~/x\n'), 'echo harmless[201~rm -rf ~/x\r');
    });

    test('the 8-bit CSI (U+009B) is stripped as well', () {
      expect(normalizeTypedText('a\u009b201~b'), 'a201~b');
    });

    test('C0 controls other than tab and line breaks are stripped, and so is DEL', () {
      expect(normalizeTypedText('a\x00b\x03c\x07d\x08e\x7ff'), 'abcdef');
    });

    test('tabs and CR survive, LF still becomes CR', () {
      expect(normalizeTypedText('a\tb\rc\nd'), 'a\tb\rc\rd');
    });

    test('Vietnamese and emoji text survive', () {
      expect(normalizeTypedText('xin chào 😀 ¡ÿ'), 'xin chào 😀 ¡ÿ');
    });

    test('sticky Ctrl still maps the typed character after sanitising', () {
      expect(applyModifiersToText(normalizeTypedText('c'), ctrl: true, alt: false), '\x03');
    });
  });

  group('pasted text is sanitised', () {
    test('ESC is stripped, so a paste cannot close bracketed paste itself', () {
      expect(normalizePastedText('echo harmless\x1b[201~rm -rf ~/x\n'), 'echo harmless[201~rm -rf ~/x\r');
    });

    test('C0 controls other than tab and line breaks are stripped, and so is DEL', () {
      expect(normalizePastedText('a\x00b\x03c\x07d\x08e\x7ff'), 'abcdef');
      expect(normalizePastedText('\x01\x02\x04\x05\x06\x0b\x0c\x0e\x0f\x10\x1a\x1c\x1d\x1e\x1f'), '');
    });

    test('C1 controls are stripped, CSI (U+009B) included', () {
      expect(normalizePastedText('a\u009b201~b\u0080c\u0085d\u009fe'), 'a201~bcde');
    });

    test('tabs survive and CRLF/LF/CR all become CR', () {
      expect(normalizePastedText('a\tb\r\nc\nd\re'), 'a\tb\rc\rd\re');
    });

    test('printable text outside ASCII is kept', () {
      expect(normalizePastedText('xin chào 😀 ¡ÿ'), 'xin chào 😀 ¡ÿ');
    });
  });

  group('terminalShortcuts', () {
    Iterable<SingleActivator> activators(TargetPlatform platform) =>
        terminalShortcuts(platform).keys.cast<SingleActivator>();

    test('Android never captures Ctrl+A or Ctrl+V', () {
      final android = activators(TargetPlatform.android);
      expect(android.where((a) => a.control && !a.shift), isEmpty);
      expect(
        android.where((a) => a.trigger == LogicalKeyboardKey.keyV && a.control && a.shift),
        hasLength(1),
      );
    });

    test('iOS uses the Command key', () {
      final ios = activators(TargetPlatform.iOS);
      expect(ios.every((a) => a.meta && !a.control), isTrue);
      expect(terminalShortcuts(TargetPlatform.iOS).values.whereType<ShellxPasteIntent>(), hasLength(1));
    });

    test('shortcuts use ShellX intents, not Flutter built-ins', () {
      for (final platform in TargetPlatform.values) {
        final shortcuts = terminalShortcuts(platform);
        expect(
          shortcuts.values.whereType<PasteTextIntent>(),
          isEmpty,
          reason: '$platform should not use Flutter PasteTextIntent',
        );
        expect(
          shortcuts.values.whereType<CopySelectionTextIntent>(),
          isEmpty,
          reason: '$platform should not use Flutter CopySelectionTextIntent',
        );
        expect(
          shortcuts.values.whereType<ShellxPasteIntent>(),
          hasLength(1),
          reason: '$platform should have exactly one ShellxPasteIntent',
        );
        expect(
          shortcuts.values.whereType<ShellxCopyIntent>(),
          hasLength(1),
          reason: '$platform should have exactly one ShellxCopyIntent',
        );
      }
    });
  });
}
