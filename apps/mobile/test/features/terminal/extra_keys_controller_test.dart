import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' show effect;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:xterm/core.dart';

void main() {
  late DateTime now;
  late ExtraKeysController keys;
  late List<String> out;
  late Terminal terminal;

  void advance(int milliseconds) => now = now.add(Duration(milliseconds: milliseconds));

  String send(ExtraKey key) {
    out.clear();
    keys.sendKey(key, terminal);
    return out.join();
  }

  setUp(() {
    now = DateTime(2026, 9, 25);
    keys = ExtraKeysController(now: () => now);
    out = [];
    terminal = Terminal(inputHandler: shellxInputHandler, onOutput: out.add);
  });

  tearDown(() => keys.dispose());

  test('the row matches spec §9.3', () {
    expect(
      ExtraKey.values.map((k) => extraKeyLabel(k) ?? 'Dán').join(' '),
      'Esc Tab Ctrl Alt ↑ ↓ ← → | ~ / - Home End PgUp PgDn Dán',
    );
  });

  group('sticky modifiers', () {
    test('one tap applies Ctrl to the next key only', () {
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.oneShot);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.ctrl.value, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('a double tap locks until tapped again', () {
      keys.tapModifier(ExtraKey.ctrl);
      advance(200);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.locked);
      expect(keys.applyModifiers('c'), '\x03');
      expect(keys.applyModifiers('d'), '\x04');
      expect(keys.ctrl.value, ModifierLatch.locked);
      advance(5000);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.off);
      expect(keys.applyModifiers('c'), 'c');
    });

    test('the second tap must land inside the double-tap window', () {
      keys.tapModifier(ExtraKey.alt);
      advance(400);
      keys.tapModifier(ExtraKey.alt);
      expect(keys.alt.value, ModifierLatch.locked);

      keys.tapModifier(ExtraKey.alt); // unlock
      advance(1000);
      keys.tapModifier(ExtraKey.alt);
      advance(401);
      keys.tapModifier(ExtraKey.alt); // slow second tap cancels
      expect(keys.alt.value, ModifierLatch.off);
    });

    test('a quick tap after the one-shot was used arms a new one-shot, not a lock', () {
      keys.tapModifier(ExtraKey.ctrl);
      keys.applyModifiers('a');
      advance(100);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.ctrl.value, ModifierLatch.oneShot);
    });

    test('Ctrl and Alt are independent and combine', () {
      keys.tapModifier(ExtraKey.ctrl);
      keys.tapModifier(ExtraKey.alt);
      expect(keys.applyModifiers('x'), '\x1b\x18');
      expect(keys.hasActiveModifiers, isFalse);
    });

    test('a locked Alt stays while a one-shot Ctrl is consumed', () {
      keys.tapModifier(ExtraKey.alt);
      keys.tapModifier(ExtraKey.alt);
      keys.tapModifier(ExtraKey.ctrl);
      expect(keys.consumeModifiers(), (ctrl: true, alt: true));
      expect(keys.consumeModifiers(), (ctrl: false, alt: true));
    });

    test('the latch signals change on taps and when a one-shot is consumed', () {
      final seen = <ModifierLatch>[];
      final stop = effect(() => seen.add(keys.ctrl.value));
      addTearDown(stop);
      keys.tapModifier(ExtraKey.ctrl);
      keys.consumeModifiers();
      keys.consumeModifiers();
      expect(seen, [ModifierLatch.off, ModifierLatch.oneShot, ModifierLatch.off]);
    });

    test('only Ctrl and Alt are modifiers', () {
      expect(() => keys.tapModifier(ExtraKey.esc), throwsArgumentError);
    });
  });

  group('sendKey through xterm key handling', () {
    test('navigation keys in normal and application cursor mode', () {
      expect(send(ExtraKey.up), '\x1b[A');
      expect(send(ExtraKey.down), '\x1b[B');
      expect(send(ExtraKey.right), '\x1b[C');
      expect(send(ExtraKey.left), '\x1b[D');
      expect(send(ExtraKey.home), '\x1b[H');
      expect(send(ExtraKey.end), '\x1b[F');
      expect(send(ExtraKey.pageUp), '\x1b[5~');
      expect(send(ExtraKey.pageDown), '\x1b[6~');
      expect(send(ExtraKey.esc), '\x1b');
      expect(send(ExtraKey.tab), '\t');

      terminal.write('\x1b[?1h'); // vim/htop/less enter application cursor mode
      expect(send(ExtraKey.up), '\x1bOA');
      expect(send(ExtraKey.left), '\x1bOD');
      expect(send(ExtraKey.home), '\x1bOH');
    });

    test('sticky modifiers reach navigation keys and are consumed', () {
      keys.tapModifier(ExtraKey.alt);
      expect(send(ExtraKey.left), '\x1b[1;3D');
      expect(send(ExtraKey.left), '\x1b[D');

      keys.tapModifier(ExtraKey.ctrl);
      advance(100);
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.right), '\x1b[1;5C');
      expect(send(ExtraKey.right), '\x1b[1;5C');
    });

    test('character keys', () {
      expect(send(ExtraKey.pipe), '|');
      expect(send(ExtraKey.tilde), '~');
      expect(send(ExtraKey.slash), '/');
      expect(send(ExtraKey.minus), '-');
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.slash), '\x1f');
      keys.tapModifier(ExtraKey.alt);
      expect(send(ExtraKey.tilde), '\x1b~');
      keys.tapModifier(ExtraKey.ctrl);
      expect(send(ExtraKey.pipe), '|');
      expect(keys.hasActiveModifiers, isFalse);
    });

    test('Ctrl, Alt and Paste are not sent as keys', () {
      expect(() => keys.sendKey(ExtraKey.ctrl, terminal), throwsArgumentError);
      expect(() => keys.sendKey(ExtraKey.paste, terminal), throwsArgumentError);
    });
  });
}
