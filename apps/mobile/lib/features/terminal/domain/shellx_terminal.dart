import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:xterm/core.dart';

/// Keys whose soft-keyboard text must reach [ShellxTerminal.textInput] so the
/// sticky modifiers keep the typed character's case.
const Set<TerminalKey> _textKeys = {
  TerminalKey.keyA,
  TerminalKey.keyB,
  TerminalKey.keyC,
  TerminalKey.keyD,
  TerminalKey.keyE,
  TerminalKey.keyF,
  TerminalKey.keyG,
  TerminalKey.keyH,
  TerminalKey.keyI,
  TerminalKey.keyJ,
  TerminalKey.keyK,
  TerminalKey.keyL,
  TerminalKey.keyM,
  TerminalKey.keyN,
  TerminalKey.keyO,
  TerminalKey.keyP,
  TerminalKey.keyQ,
  TerminalKey.keyR,
  TerminalKey.keyS,
  TerminalKey.keyT,
  TerminalKey.keyU,
  TerminalKey.keyV,
  TerminalKey.keyW,
  TerminalKey.keyX,
  TerminalKey.keyY,
  TerminalKey.keyZ,
  TerminalKey.digit0,
  TerminalKey.digit1,
  TerminalKey.digit2,
  TerminalKey.digit3,
  TerminalKey.digit4,
  TerminalKey.digit5,
  TerminalKey.digit6,
  TerminalKey.digit7,
  TerminalKey.digit8,
  TerminalKey.digit9,
  TerminalKey.space,
  TerminalKey.minus,
  TerminalKey.equal,
  TerminalKey.bracketLeft,
  TerminalKey.bracketRight,
  TerminalKey.backslash,
  TerminalKey.semicolon,
  TerminalKey.quote,
  TerminalKey.backquote,
  TerminalKey.comma,
  TerminalKey.period,
  TerminalKey.slash,
};

/// xterm [Terminal] that honours the extra keys bar's sticky Ctrl/Alt for
/// soft-keyboard and hardware-keyboard input.
///
/// `TerminalView` feeds soft-keyboard text as `keyInput(key)` first and falls
/// back to `textInput(text)` when that returns false; hardware keys arrive as
/// `keyInput(key, ctrl:, alt:, shift:)`.
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
      // Let TerminalView fall back to textInput() with the typed character.
      if (_textKeys.contains(key)) return false;
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
