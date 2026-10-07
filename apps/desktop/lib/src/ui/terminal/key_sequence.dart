import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/keybind_actions.dart';
import '../../config/keybind_trigger.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';

final keySequenceProvider = NotifierProvider<KeySequence, KeyChord?>(
  KeySequence.new,
);

/// A9 D28: the pending first step of a two-step binding (null: none).
///
/// No timeout, like Ghostty and tmux; Esc, another focus, a click, a menu or
/// a reload ends the wait. Sequences have two steps at most (the parser
/// refuses longer ones), and a prefix that is also a single-chord binding
/// has already dropped that binding (spec D27), so the first step never
/// competes with one.
class KeySequence extends Notifier<KeyChord?> {
  /// The last event looked at: the terminal and the window both see a key
  /// that nobody handled, and the second look must not be a second step.
  KeyEvent? _seen;

  @override
  KeyChord? build() {
    ref.listen(
      shellxConfigProvider.select((s) => s.bindings),
      (_, _) => cancel(),
    );
    return null;
  }

  void cancel() {
    if (state != null) state = null;
  }

  /// Handles one key. Handled: swallowed (a prefix, the step that ran, Esc,
  /// the prefix typed). Ignored: it goes on to the shell or to the other
  /// shortcuts as if no sequence were pending.
  KeyEventResult handle(
    KeyEvent event, {
    required bool Function(Intent intent) invoke,
    required void Function(KeyChord prefix) sendPrefix,
    HardwareKeyboard? keyboard,
  }) {
    if (event is KeyUpEvent || identical(event, _seen)) {
      return KeyEventResult.ignored;
    }
    _seen = event;
    final pending = state;
    if (pending != null && event is KeyRepeatEvent) {
      // Holding the prefix neither re-sends nor re-arms it.
      return KeyEventResult.handled;
    }
    final hk = keyboard ?? HardwareKeyboard.instance;
    // D26: AltGr's characters are the layout's, pending or not. An input
    // method's key (Windows' "process" key) is the composition's: neither
    // starts, ends nor answers a sequence, and nothing is swallowed.
    if (altGrHeld(hk.logicalKeysPressed, defaultTargetPlatform) ||
        event.logicalKey == LogicalKeyboardKey.process) {
      cancel();
      return KeyEventResult.ignored;
    }
    final chord = chordOfEvent(event, hk);
    if (chord == null) return KeyEventResult.ignored; // a modifier alone
    final sequences = ref.read(shellxConfigProvider).bindings.sequences;
    if (pending == null) {
      if (event is KeyRepeatEvent) return KeyEventResult.ignored;
      if (sequences.any((b) => b.sequence.first == chord)) {
        state = chord;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    state = null;
    if (chord.key == LogicalKeyboardKey.escape &&
        !chord.hasCommandModifier &&
        !chord.shift) {
      return KeyEventResult.handled;
    }
    if (chord == pending) {
      sendPrefix(pending);
      return KeyEventResult.handled;
    }
    final match = sequences
        .where((b) => b.sequence.first == pending && b.sequence[1] == chord)
        .firstOrNull;
    if (match != null && invoke(intentForAction(match.action))) {
      return KeyEventResult.handled;
    }
    // Not a second step (or its action does not apply now): the key goes on.
    return KeyEventResult.ignored;
  }
}

/// What "the prefix twice" types: Ctrl+letter is its control character,
/// Alt+letter is ESC and the letter (tmux and screen prefixes); other
/// prefixes are only consumed.
String? prefixText(KeyChord c) {
  final id = c.key.keyId;
  final letter = id >= 0x61 && id <= 0x7a;
  if (!letter || c.meta || c.shift) return null;
  if (c.control && !c.alt) return String.fromCharCode(id - 0x60);
  if (c.alt && !c.control) return '\x1b${String.fromCharCode(id)}';
  return null;
}

/// UI-A9 §5: "⌃A …" at the bottom right of the terminal area while pending.
class SequenceIndicator extends ConsumerWidget {
  const SequenceIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(keySequenceProvider);
    if (pending == null) return const SizedBox.shrink();
    final label = chordLabel(pending, mac: isMacDesktop);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          height: ShellxSizes.sequenceIndicatorHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s8 + ShellxSpace.s2,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.pill),
            border: Border.all(color: ShellxDesktopColors.accent),
          ),
          child: Text(
            AppLocalizations.of(context).sequencePending(label),
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
