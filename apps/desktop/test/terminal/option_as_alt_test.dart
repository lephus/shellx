import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/terminal_input.dart';
import 'package:xterm/core.dart';

TerminalKeyboardEvent key(
  TerminalKey k, {
  bool alt = true,
  bool shift = false,
  bool ctrl = false,
  TerminalTargetPlatform platform = TerminalTargetPlatform.macos,
  bool altBuffer = false,
}) => TerminalKeyboardEvent(
  key: k,
  shift: shift,
  ctrl: ctrl,
  alt: alt,
  state: Terminal(),
  altBuffer: altBuffer,
  platform: platform,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('off (default): Option keys are left to the IME, as today', () {
    final h = OptionAsAltInputHandler(() => OptionAsAlt.off);
    expect(h(key(TerminalKey.keyF)), isNull);
  });

  test('both: ESC + the base character; Shift makes it upper case (D19)', () {
    final h = OptionAsAltInputHandler(() => OptionAsAlt.both);
    expect(h(key(TerminalKey.keyF)), '\x1bf');
    expect(h(key(TerminalKey.keyF, shift: true)), '\x1bF');
    expect(h(key(TerminalKey.digit1)), '\x1b1');
    expect(h(key(TerminalKey.digit1, shift: true)), '\x1b!');
    expect(h(key(TerminalKey.period)), '\x1b.');
    expect(h(key(TerminalKey.keyF, alt: false)), isNull);
    expect(h(key(TerminalKey.keyF, ctrl: true)), isNull);
    expect(
      h(key(TerminalKey.keyF, platform: TerminalTargetPlatform.windows)),
      isNull,
    );
    expect(h(key(TerminalKey.arrowLeft)), isNull);
  });

  test('left / right follow the Option key held', () {
    var pressed = <LogicalKeyboardKey>{LogicalKeyboardKey.altLeft};
    final left = OptionAsAltInputHandler(
      () => OptionAsAlt.left,
      pressed: () => pressed,
    );
    final right = OptionAsAltInputHandler(
      () => OptionAsAlt.right,
      pressed: () => pressed,
    );
    expect(left(key(TerminalKey.keyB)), '\x1bb');
    expect(right(key(TerminalKey.keyB)), isNull);
    pressed = {LogicalKeyboardKey.altRight};
    expect(left(key(TerminalKey.keyB)), isNull);
    expect(right(key(TerminalKey.keyB)), '\x1bb');
  });

  test('the cascade keeps Option+←/→ moving by word at the shell', () {
    final cascade = desktopInputHandlerWith(() => OptionAsAlt.both);
    expect(cascade(key(TerminalKey.arrowLeft)), '\x1bb');
    expect(cascade(key(TerminalKey.keyX)), '\x1bx');
  });

  test('a held Cmd makes it a Cmd chord: never Meta text', () {
    final h = OptionAsAltInputHandler(
      () => OptionAsAlt.both,
      pressed: () => {LogicalKeyboardKey.metaLeft},
    );
    expect(h(key(TerminalKey.keyF)), isNull);
    final right = OptionAsAltInputHandler(
      () => OptionAsAlt.both,
      pressed: () => {LogicalKeyboardKey.metaRight},
    );
    expect(right(key(TerminalKey.keyF)), isNull);
  });

  test('left / right with both Option keys held: either counts as Alt', () {
    final both = {LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight};
    final left = OptionAsAltInputHandler(
      () => OptionAsAlt.left,
      pressed: () => both,
    );
    final right = OptionAsAltInputHandler(
      () => OptionAsAlt.right,
      pressed: () => both,
    );
    expect(left(key(TerminalKey.keyB)), '\x1bb');
    expect(right(key(TerminalKey.keyB)), '\x1bb');
  });
}
