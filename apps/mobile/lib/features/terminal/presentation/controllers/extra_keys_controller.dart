import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/domain/terminal_input.dart';
import 'package:xterm/core.dart';

/// The extra keys row of spec §9.3, in order.
enum ExtraKey {
  esc,
  tab,
  ctrl,
  alt,
  up,
  down,
  left,
  right,
  pipe,
  tilde,
  slash,
  minus,
  home,
  end,
  pageUp,
  pageDown,
  paste,
}

/// Fixed key cap text; [ExtraKey.paste] is localised ("Dán" / "Paste") by the UI.
String? extraKeyLabel(ExtraKey key) => switch (key) {
  ExtraKey.esc => 'Esc',
  ExtraKey.tab => 'Tab',
  ExtraKey.ctrl => 'Ctrl',
  ExtraKey.alt => 'Alt',
  ExtraKey.up => '↑',
  ExtraKey.down => '↓',
  ExtraKey.left => '←',
  ExtraKey.right => '→',
  ExtraKey.pipe => '|',
  ExtraKey.tilde => '~',
  ExtraKey.slash => '/',
  ExtraKey.minus => '-',
  ExtraKey.home => 'Home',
  ExtraKey.end => 'End',
  ExtraKey.pageUp => 'PgUp',
  ExtraKey.pageDown => 'PgDn',
  ExtraKey.paste => null,
};

enum ModifierLatch { off, oneShot, locked }

/// Sticky modifiers that other input paths (soft keyboard, hardware keyboard)
/// must honour.
abstract interface class ModifierSource {
  bool get hasActiveModifiers;

  /// Returns the active modifiers and clears the one-shot ones.
  ({bool ctrl, bool alt}) consumeModifiers();

  /// [text] with the active modifiers applied; consumes one-shot modifiers.
  String applyModifiers(String text);
}

/// State of the extra keys bar: sticky Ctrl/Alt (as signals) and key dispatch.
///
/// Spec §9.3: tapping Ctrl/Alt once applies it to the next key only; a double
/// tap (second tap within [doubleTapWindow]) locks it until it is tapped
/// again. A slow second tap cancels a pending one-shot modifier.
class ExtraKeysController extends Controller implements ModifierSource {
  ExtraKeysController({
    DateTime Function()? now,
    this.doubleTapWindow = const Duration(milliseconds: 400),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration doubleTapWindow;
  final Signal<ModifierLatch> _ctrl = signal(ModifierLatch.off);
  final Signal<ModifierLatch> _alt = signal(ModifierLatch.off);
  DateTime? _ctrlTappedAt;
  DateTime? _altTappedAt;

  ReadonlySignal<ModifierLatch> get ctrl => _ctrl;
  ReadonlySignal<ModifierLatch> get alt => _alt;

  void tapModifier(ExtraKey key) {
    final now = _now();
    switch (key) {
      case ExtraKey.ctrl:
        _ctrl.value = _nextLatch(_ctrl.peek(), _ctrlTappedAt, now);
        _ctrlTappedAt = now;
      case ExtraKey.alt:
        _alt.value = _nextLatch(_alt.peek(), _altTappedAt, now);
        _altTappedAt = now;
      default:
        throw ArgumentError.value(key, 'key', 'not a modifier key');
    }
  }

  ModifierLatch _nextLatch(ModifierLatch current, DateTime? lastTap, DateTime now) => switch (current) {
    ModifierLatch.off => ModifierLatch.oneShot,
    ModifierLatch.oneShot =>
      lastTap != null && now.difference(lastTap) <= doubleTapWindow ? ModifierLatch.locked : ModifierLatch.off,
    ModifierLatch.locked => ModifierLatch.off,
  };

  @override
  bool get hasActiveModifiers => _ctrl.peek() != ModifierLatch.off || _alt.peek() != ModifierLatch.off;

  @override
  ({bool ctrl, bool alt}) consumeModifiers() {
    final active = (ctrl: _ctrl.peek() != ModifierLatch.off, alt: _alt.peek() != ModifierLatch.off);
    batch(() {
      if (_ctrl.peek() == ModifierLatch.oneShot) _ctrl.value = ModifierLatch.off;
      if (_alt.peek() == ModifierLatch.oneShot) _alt.value = ModifierLatch.off;
    });
    return active;
  }

  @override
  String applyModifiers(String text) {
    if (text.isEmpty || !hasActiveModifiers) return text;
    final active = consumeModifiers();
    return applyModifiersToText(text, ctrl: active.ctrl, alt: active.alt);
  }

  /// Sends a non-modifier, non-paste key to [terminal].
  ///
  /// Esc/Tab/arrows/Home/End/PgUp/PgDn go through [Terminal.keyInput] with
  /// the sticky modifiers, so xterm's application cursor mode and modifier
  /// encoding apply. Characters are emitted on [Terminal.onOutput] directly:
  /// `textInput` is where a ShellxTerminal applies modifiers again.
  void sendKey(ExtraKey key, Terminal terminal) {
    final terminalKey = switch (key) {
      ExtraKey.esc => TerminalKey.escape,
      ExtraKey.tab => TerminalKey.tab,
      ExtraKey.up => TerminalKey.arrowUp,
      ExtraKey.down => TerminalKey.arrowDown,
      ExtraKey.left => TerminalKey.arrowLeft,
      ExtraKey.right => TerminalKey.arrowRight,
      ExtraKey.home => TerminalKey.home,
      ExtraKey.end => TerminalKey.end,
      ExtraKey.pageUp => TerminalKey.pageUp,
      ExtraKey.pageDown => TerminalKey.pageDown,
      _ => null,
    };
    if (terminalKey != null) {
      final active = consumeModifiers();
      terminal.keyInput(terminalKey, ctrl: active.ctrl, alt: active.alt);
      return;
    }
    final char = switch (key) {
      ExtraKey.pipe => '|',
      ExtraKey.tilde => '~',
      ExtraKey.slash => '/',
      ExtraKey.minus => '-',
      _ => throw ArgumentError.value(key, 'key', 'use tapModifier() or paste instead'),
    };
    terminal.onOutput?.call(applyModifiers(char));
  }

  void dispose() {
    _ctrl.dispose();
    _alt.dispose();
  }
}
