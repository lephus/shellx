import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/core.dart';

/// A key whose typed text must normally reach [ShellxTerminal.textInput] so
/// sticky modifiers keep the typed character's case (see [_textKeys]).
///
/// [char] is the base (lower-case for letters, unshifted for digits/symbols)
/// character; [logicalKey] is what a *physical* press of this key reports on
/// [HardwareKeyboard], used to tell a real hardware key event apart from the
/// soft keyboard (see [ShellxTerminal.keyInput]).
class _TextKey {
  const _TextKey(this.char, this.logicalKey);

  final String char;
  final LogicalKeyboardKey logicalKey;
}

/// Keys whose soft-keyboard text must reach [ShellxTerminal.textInput] so the
/// sticky modifiers keep the typed character's case.
const Map<TerminalKey, _TextKey> _textKeys = {
  TerminalKey.keyA: _TextKey('a', LogicalKeyboardKey.keyA),
  TerminalKey.keyB: _TextKey('b', LogicalKeyboardKey.keyB),
  TerminalKey.keyC: _TextKey('c', LogicalKeyboardKey.keyC),
  TerminalKey.keyD: _TextKey('d', LogicalKeyboardKey.keyD),
  TerminalKey.keyE: _TextKey('e', LogicalKeyboardKey.keyE),
  TerminalKey.keyF: _TextKey('f', LogicalKeyboardKey.keyF),
  TerminalKey.keyG: _TextKey('g', LogicalKeyboardKey.keyG),
  TerminalKey.keyH: _TextKey('h', LogicalKeyboardKey.keyH),
  TerminalKey.keyI: _TextKey('i', LogicalKeyboardKey.keyI),
  TerminalKey.keyJ: _TextKey('j', LogicalKeyboardKey.keyJ),
  TerminalKey.keyK: _TextKey('k', LogicalKeyboardKey.keyK),
  TerminalKey.keyL: _TextKey('l', LogicalKeyboardKey.keyL),
  TerminalKey.keyM: _TextKey('m', LogicalKeyboardKey.keyM),
  TerminalKey.keyN: _TextKey('n', LogicalKeyboardKey.keyN),
  TerminalKey.keyO: _TextKey('o', LogicalKeyboardKey.keyO),
  TerminalKey.keyP: _TextKey('p', LogicalKeyboardKey.keyP),
  TerminalKey.keyQ: _TextKey('q', LogicalKeyboardKey.keyQ),
  TerminalKey.keyR: _TextKey('r', LogicalKeyboardKey.keyR),
  TerminalKey.keyS: _TextKey('s', LogicalKeyboardKey.keyS),
  TerminalKey.keyT: _TextKey('t', LogicalKeyboardKey.keyT),
  TerminalKey.keyU: _TextKey('u', LogicalKeyboardKey.keyU),
  TerminalKey.keyV: _TextKey('v', LogicalKeyboardKey.keyV),
  TerminalKey.keyW: _TextKey('w', LogicalKeyboardKey.keyW),
  TerminalKey.keyX: _TextKey('x', LogicalKeyboardKey.keyX),
  TerminalKey.keyY: _TextKey('y', LogicalKeyboardKey.keyY),
  TerminalKey.keyZ: _TextKey('z', LogicalKeyboardKey.keyZ),
  TerminalKey.digit0: _TextKey('0', LogicalKeyboardKey.digit0),
  TerminalKey.digit1: _TextKey('1', LogicalKeyboardKey.digit1),
  TerminalKey.digit2: _TextKey('2', LogicalKeyboardKey.digit2),
  TerminalKey.digit3: _TextKey('3', LogicalKeyboardKey.digit3),
  TerminalKey.digit4: _TextKey('4', LogicalKeyboardKey.digit4),
  TerminalKey.digit5: _TextKey('5', LogicalKeyboardKey.digit5),
  TerminalKey.digit6: _TextKey('6', LogicalKeyboardKey.digit6),
  TerminalKey.digit7: _TextKey('7', LogicalKeyboardKey.digit7),
  TerminalKey.digit8: _TextKey('8', LogicalKeyboardKey.digit8),
  TerminalKey.digit9: _TextKey('9', LogicalKeyboardKey.digit9),
  TerminalKey.space: _TextKey(' ', LogicalKeyboardKey.space),
  TerminalKey.minus: _TextKey('-', LogicalKeyboardKey.minus),
  TerminalKey.equal: _TextKey('=', LogicalKeyboardKey.equal),
  TerminalKey.bracketLeft: _TextKey('[', LogicalKeyboardKey.bracketLeft),
  TerminalKey.bracketRight: _TextKey(']', LogicalKeyboardKey.bracketRight),
  TerminalKey.backslash: _TextKey('\\', LogicalKeyboardKey.backslash),
  TerminalKey.semicolon: _TextKey(';', LogicalKeyboardKey.semicolon),
  TerminalKey.quote: _TextKey("'", LogicalKeyboardKey.quote),
  TerminalKey.backquote: _TextKey('`', LogicalKeyboardKey.backquote),
  TerminalKey.comma: _TextKey(',', LogicalKeyboardKey.comma),
  TerminalKey.period: _TextKey('.', LogicalKeyboardKey.period),
  TerminalKey.slash: _TextKey('/', LogicalKeyboardKey.slash),
};

/// xterm [Terminal] that honours the extra keys bar's sticky Ctrl/Alt for
/// soft-keyboard and hardware-keyboard input.
///
/// `TerminalView` feeds soft-keyboard text as `keyInput(key)` first and falls
/// back to `textInput(text)` when that returns false; hardware keys arrive as
/// `keyInput(key, ctrl:, alt:, shift:)` with **no** fallback to `textInput`
/// (`TerminalView._handleKeyEvent` uses the boolean result directly), so a
/// text key must be fully handled inside [keyInput] when it really is a
/// hardware key, or the keystroke is silently dropped whenever a sticky
/// modifier is armed.
///
/// [paste] is the single place normalization (CR line breaks) and bracketed
/// paste markers are applied: callers (e.g. the terminal page's
/// `ShellxPasteIntent` handler) only need to read the clipboard and call
/// `terminal.paste(text)`. Pasted text never picks up the sticky modifiers.
class ShellxTerminal extends Terminal {
  ShellxTerminal({required this.modifiers, super.maxLines = 2000}) : super(inputHandler: shellxInputHandler);

  final ModifierSource modifiers;

  @override
  bool keyInput(TerminalKey key, {bool shift = false, bool alt = false, bool ctrl = false}) {
    if (!ctrl && !alt && modifiers.hasActiveModifiers) {
      final textKey = _textKeys[key];
      if (textKey != null) {
        // The soft keyboard's `_onInsert` and the hardware `_handleKeyEvent`
        // both end up calling keyInput(key) with the same (false, false,
        // false) modifiers when no hardware modifier is held, so we cannot
        // tell them apart from the arguments alone. HardwareKeyboard reports
        // only genuine physical key presses, so we use it as the source of
        // truth: a real hardware key is handled right here (there is no
        // second chance); anything else falls through to `return false` so
        // TerminalView calls textInput() with the actually-typed, correctly
        // cased character.
        if (HardwareKeyboard.instance.isLogicalKeyPressed(textKey.logicalKey)) {
          final char = shift ? textKey.char.toUpperCase() : textKey.char;
          onOutput?.call(modifiers.applyModifiers(char));
          return true;
        }
        return false;
      }
      final active = modifiers.consumeModifiers();
      return super.keyInput(key, shift: shift, ctrl: active.ctrl, alt: active.alt);
    }
    return super.keyInput(key, shift: shift, alt: alt, ctrl: ctrl);
  }

  @override
  void textInput(String text) => super.textInput(modifiers.applyModifiers(normalizeTypedText(text)));

  /// Spec §9.4: bracketed paste when the application enabled it. Pasted text
  /// never picks up sticky modifiers.
  @override
  void paste(String text) {
    final normalized = normalizePastedText(text);
    if (bracketedPasteMode) {
      super.paste(normalized);
    } else {
      super.textInput(normalized);
    }
  }
}
