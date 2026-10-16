import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/config/keybindings.dart';

void main() {
  group('parseKeyChord (D22)', () {
    test('modifier aliases', () {
      const d = KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true);
      expect(parseKeyChord('super+shift+d'), d);
      expect(parseKeyChord('cmd+shift+d'), d);
      expect(parseKeyChord('Command+Shift+D'), d);
      expect(
        parseKeyChord('control+opt+x'),
        const KeyChord(LogicalKeyboardKey.keyX, control: true, alt: true),
      );
      expect(parseKeyChord('ctrl+option+x'), parseKeyChord('control+alt+x'));
    });

    test('characters and names', () {
      expect(
        parseKeyChord('super+='),
        const KeyChord(LogicalKeyboardKey.equal, meta: true),
      );
      expect(parseKeyChord('super+equal'), parseKeyChord('super+='));
      expect(
        parseKeyChord('ctrl++'),
        const KeyChord(LogicalKeyboardKey.add, control: true),
      );
      expect(parseKeyChord('ctrl+plus'), parseKeyChord('ctrl++'));
      expect(parseKeyChord('super+,'), parseKeyChord('super+comma'));
      expect(
        parseKeyChord('arrow_left'),
        const KeyChord(LogicalKeyboardKey.arrowLeft),
      );
      expect(parseKeyChord('left'), parseKeyChord('arrow_left'));
      expect(
        parseKeyChord('kp_enter'),
        const KeyChord(LogicalKeyboardKey.numpadEnter),
      );
      expect(parseKeyChord('f12'), const KeyChord(LogicalKeyboardKey.f12));
      expect(parseKeyChord('digit_1'), parseKeyChord('1'));
      expect(parseKeyChord('return'), parseKeyChord('enter'));
      expect(parseKeyChord('ctrl+ö')!.key.keyId, 0xf6);
      expect(parseKeyChord('ctrl+Ö'), parseKeyChord('ctrl+ö'));
    });

    test('invalid', () {
      for (final bad in [
        '',
        'ctrl+',
        'hyper+a',
        'ctrl+foo',
        'ctrl+a+b',
        'ctrl+ab',
      ]) {
        expect(parseKeyChord(bad), isNull, reason: bad);
      }
    });
  });

  group('labels (D29; same text as A1–A6 labels)', () {
    String mac(String t) => chordLabel(parseKeyChord(t)!, mac: true);
    String win(String t) => chordLabel(parseKeyChord(t)!, mac: false);
    test('macOS', () {
      expect(mac('super+t'), '⌘T');
      expect(mac('super+shift+d'), '⌘⇧D');
      expect(mac('super+ctrl+='), '⌘⌃=');
      expect(mac('super+shift+enter'), '⌘⇧↩');
      expect(mac('alt+up'), '⌥↑');
      expect(mac('ctrl+a'), '⌃A');
      expect(mac('super+,'), '⌘,');
      expect(
        sequenceLabel([
          parseKeyChord('ctrl+a')!,
          parseKeyChord('c')!,
        ], mac: true),
        '⌃A C',
      );
    });
    test('Windows', () {
      expect(win('ctrl+shift+t'), 'Ctrl+Shift+T');
      expect(win('ctrl+shift+alt+d'), 'Ctrl+Shift+Alt+D');
      expect(win('ctrl+shift+alt+='), 'Ctrl+Shift+Alt+=');
      expect(win('ctrl+shift+enter'), 'Ctrl+Shift+Enter');
      expect(win('alt+up'), 'Alt+↑');
      expect(win('ctrl+,'), 'Ctrl+,');
      expect(win('f5'), 'F5');
    });
  });

  test('config text round-trips every default chord', () {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      for (final b in defaultKeyBindings(platform)) {
        for (final c in b.sequence) {
          final text = chordConfigText(c);
          expect(text, isNotNull, reason: '$c');
          expect(parseKeyChord(text!), c, reason: text);
        }
      }
    }
    expect(
      chordConfigText(
        const KeyChord(LogicalKeyboardKey.keyN, control: true, alt: true),
      ),
      'ctrl+alt+n',
    );
    expect(
      chordConfigText(
        const KeyChord(LogicalKeyboardKey.comma, meta: true, shift: true),
      ),
      'shift+super+comma',
    );
  });

  test('chordActivator carries the modifiers and the repeat flag', () {
    final a = chordActivator(
      const KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true),
      repeats: false,
    );
    expect(
      (a.trigger, a.meta, a.shift, a.control, a.alt, a.includeRepeats),
      (LogicalKeyboardKey.keyD, true, true, false, false, false),
    );
    expect(describeActivator(a), 'shift+meta+64 norepeat');
  });

  test('key classes', () {
    expect(isFunctionKey(LogicalKeyboardKey.f6), isTrue);
    expect(isFunctionKey(LogicalKeyboardKey.keyF), isFalse);
    expect(isPrintableKey(LogicalKeyboardKey.keyQ), isTrue);
    expect(isPrintableKey(LogicalKeyboardKey.comma), isTrue);
    expect(isPrintableKey(LogicalKeyboardKey.arrowLeft), isFalse);
  });

  group('altGrHeld (D26)', () {
    const right = LogicalKeyboardKey.altRight;
    const left = LogicalKeyboardKey.controlLeft;
    test('needs Ctrl and the right Alt, on Windows', () {
      expect(altGrHeld({left, right}, TargetPlatform.windows), isTrue);
      expect(altGrHeld({right}, TargetPlatform.windows), isFalse);
      expect(altGrHeld({left}, TargetPlatform.windows), isFalse);
      expect(
        altGrHeld({left, LogicalKeyboardKey.altLeft}, TargetPlatform.windows),
        isFalse,
      );
      expect(altGrHeld({left, right}, TargetPlatform.macOS), isFalse);
    });
  });
}
