import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart' show Intent;

import '../config/keybind_actions.dart';
import '../config/keybind_trigger.dart';
import '../config/keybindings.dart';

/// D10: actions whose chords stay with the page — copy, paste and select
/// all (the spec), and ruling R7: what only acts on a terminal that has the
/// keyboard (prompt editing ⌘←/⌘→/⌘⌫/⌥⌫/⌥⌦, typed text, `ignore`), which
/// would only take the page's own editing keys away.
const Set<String> kToolPageActions = {
  'copy_to_clipboard',
  'paste_from_clipboard',
  'select_all',
  'edit_line',
  'text',
  'csi',
  'esc',
  'ignore',
};

/// D10: cut, undo and redo stay with the page whatever they are bound to.
Set<KeyChord> _pageChords(TargetPlatform platform) =>
    platform == TargetPlatform.macOS
    ? {
        const KeyChord(LogicalKeyboardKey.keyX, meta: true),
        const KeyChord(LogicalKeyboardKey.keyZ, meta: true),
        const KeyChord(LogicalKeyboardKey.keyZ, meta: true, shift: true),
      }
    : {
        const KeyChord(LogicalKeyboardKey.keyX, control: true),
        const KeyChord(LogicalKeyboardKey.keyZ, control: true),
        const KeyChord(LogicalKeyboardKey.keyY, control: true),
        const KeyChord(LogicalKeyboardKey.keyZ, control: true, shift: true),
      };

/// D10: the chords a page hands back to ShellX while it has the keyboard,
/// in the config spelling BrowserNative.swift compares (`chordConfigText`):
/// every window binding of the live keymap — the user's own included — and
/// the first step of every two-step sequence, but none of [kToolPageActions]
/// and no cut/undo/redo chord.
List<String> toolForwardedChords(KeyBindings bindings) {
  final keep = _pageChords(bindings.platform);
  final out = <String>{};
  for (final b in bindings.all) {
    if (b.scope != KeyScope.window) continue;
    if (kToolPageActions.contains(b.action.name)) continue;
    final chord = b.sequence.first;
    if (keep.contains(chord)) continue;
    final text = chordConfigText(chord);
    if (text != null) out.add(text);
  }
  return out.toList()..sort();
}

/// What a chord the page handed back does: a binding's intent, or the
/// first step of a sequence ([prefix]); null when it is neither any more (a
/// reload changed the keys meanwhile).
sealed class ToolChord {
  const ToolChord();
}

final class ToolChordIntent extends ToolChord {
  const ToolChordIntent(this.intent);
  final Intent intent;
}

final class ToolChordPrefix extends ToolChord {
  const ToolChordPrefix(this.prefix);
  final KeyChord prefix;
}

ToolChord? resolveToolChord(KeyBindings bindings, String text) {
  final chord = parseKeyChord(text);
  if (chord == null) return null;
  for (final b in bindings.all) {
    if (b.scope == KeyScope.window &&
        b.sequence.length == 1 &&
        b.sequence.single == chord &&
        !kToolPageActions.contains(b.action.name)) {
      return ToolChordIntent(intentForAction(b.action));
    }
  }
  if (bindings.sequences.any((b) => b.sequence.first == chord)) {
    return ToolChordPrefix(chord);
  }
  return null;
}
