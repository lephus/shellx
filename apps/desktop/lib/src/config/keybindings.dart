import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'config_problem.dart';
import 'config_syntax.dart';
import 'keybind_actions.dart';
import 'keybind_trigger.dart';
import 'shellx_config.dart';

/// One trigger (one chord, or a two-step sequence, D28) and its action.
@immutable
final class KeyBinding {
  KeyBinding(List<KeyChord> sequence, this.action, {this.origin})
    : sequence = List.unmodifiable(sequence);
  final List<KeyChord> sequence;
  final KeyAction action;

  /// The config line; null for a default.
  final ConfigEntry? origin;

  ActionSpec get spec => kActionSpecs[action.name]!;
  KeyScope get scope => spec.scope;
}

/// The effective table of one platform (spec §3.2).
final class KeyBindings {
  KeyBindings(this.platform, Iterable<KeyBinding> all)
    : all = List.unmodifiable(all);

  factory KeyBindings.defaults(TargetPlatform platform) =>
      _defaults.putIfAbsent(
        platform,
        () => KeyBindings(platform, defaultKeyBindings(platform)),
      );

  static final Map<TargetPlatform, KeyBindings> _defaults = {};

  final TargetPlatform platform;
  final List<KeyBinding> all;

  bool get _mac => platform == TargetPlatform.macOS;

  Map<ShortcutActivator, Intent> map(KeyScope scope) => {
    for (final b in all)
      if (b.sequence.length == 1 && b.scope == scope)
        chordActivator(b.sequence.single, repeats: b.spec.repeats):
            intentForAction(b.action),
  };

  List<KeyBinding> get sequences => [
    for (final b in all)
      if (b.sequence.length == 2) b,
  ];

  List<List<KeyChord>> triggersOf(KeyAction a) => [
    for (final b in all)
      if (b.action == a) b.sequence,
  ];

  /// D29 with the controller's rulings: the user's own single chord, else
  /// a default single chord still bound, else the user's sequence, else a
  /// default sequence (file order within each); null when unbound.
  String? labelOf(KeyAction a) {
    final bound = all.where((b) => b.action == a).toList();
    final first =
        bound
            .where((b) => b.origin != null && b.sequence.length == 1)
            .firstOrNull ??
        bound.where((b) => b.sequence.length == 1).firstOrNull ??
        bound.where((b) => b.origin != null).firstOrNull ??
        bound.firstOrNull;
    return first == null ? null : sequenceLabel(first.sequence, mac: _mac);
  }

  KeyBinding? find(List<KeyChord> sequence, KeyScope scope) => all
      .where((b) => b.scope == scope && listEquals(b.sequence, sequence))
      .firstOrNull;
}

/// D29: the table shortcut labels read. The config controller sets it after
/// every load and clears it when disposed; null = the platform defaults.
KeyBindings? labelBindings;

const _arrows = [
  (LogicalKeyboardKey.arrowLeft, 'left'),
  (LogicalKeyboardKey.arrowRight, 'right'),
  (LogicalKeyboardKey.arrowUp, 'up'),
  (LogicalKeyboardKey.arrowDown, 'down'),
];

const _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// D24: A1–A4's tables, chord for chord (pinned by the golden fixtures),
/// then A9's three chords. Plain F6 / Shift+F6 are not bindings (D25):
/// `desktopShortcuts` adds them. A6's browser chords join when A6 merges.
List<KeyBinding> defaultKeyBindings(TargetPlatform platform) {
  final mac = platform == TargetPlatform.macOS;
  KeyChord primary(LogicalKeyboardKey k) =>
      mac ? KeyChord(k, meta: true) : KeyChord(k, control: true, shift: true);
  KeyChord shifted(LogicalKeyboardKey k) => mac
      ? KeyChord(k, meta: true, shift: true)
      : KeyChord(k, control: true, shift: true);
  KeyChord font(LogicalKeyboardKey k, {bool shift = false}) => mac
      ? KeyChord(k, meta: true, shift: shift)
      : KeyChord(k, control: true, shift: shift);
  KeyBinding b(KeyChord c, String name, [String? param]) =>
      KeyBinding([c], KeyAction(name, param));
  return [
    b(primary(LogicalKeyboardKey.keyT), 'new_tab'),
    b(primary(LogicalKeyboardKey.keyW), 'close_surface'),
    // A11 D14: Cmd+Shift+T; Ctrl+Shift+T is new_tab on Windows, so Alt too.
    b(
      mac
          ? shifted(LogicalKeyboardKey.keyT)
          : const KeyChord(
              LogicalKeyboardKey.keyT,
              control: true,
              shift: true,
              alt: true,
            ),
      'reopen_closed',
    ),
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
    b(shifted(LogicalKeyboardKey.keyK), 'ssh_connect'),
    b(shifted(LogicalKeyboardKey.keyI), 'toggle_notifications'),
    b(shifted(LogicalKeyboardKey.keyU), 'jump_to_unread'),
    b(primary(LogicalKeyboardKey.keyC), 'copy_to_clipboard'),
    b(primary(LogicalKeyboardKey.keyV), 'paste_from_clipboard'),
    b(primary(LogicalKeyboardKey.keyA), 'select_all'),
    // A10 D4: Cmd+F/G on macOS; Ctrl+Shift+F/G (Alt for previous) on
    // Windows — never a bare F3, which htop and mc use.
    b(primary(LogicalKeyboardKey.keyF), 'start_search'),
    // A11 D21: Cmd+Shift+F; Ctrl+Shift+F is start_search on Windows, so
    // Alt too.
    b(
      mac
          ? shifted(LogicalKeyboardKey.keyF)
          : const KeyChord(
              LogicalKeyboardKey.keyF,
              control: true,
              shift: true,
              alt: true,
            ),
      'search_all',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyG, meta: true)
          : const KeyChord(LogicalKeyboardKey.keyG, control: true, shift: true),
      'navigate_search',
      'next',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyG, meta: true, shift: true)
          : const KeyChord(
              LogicalKeyboardKey.keyG,
              control: true,
              shift: true,
              alt: true,
            ),
      'navigate_search',
      'previous',
    ),
    for (var i = 0; i < _digitKeys.length; i++)
      b(
        mac
            ? KeyChord(_digitKeys[i], meta: true)
            : KeyChord(_digitKeys[i], control: true, alt: true),
        'goto_tab',
        '${i + 1}',
      ),
    b(const KeyChord(LogicalKeyboardKey.tab, control: true), 'next_tab'),
    b(
      const KeyChord(LogicalKeyboardKey.tab, control: true, shift: true),
      'previous_tab',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyD, meta: true)
          : const KeyChord(LogicalKeyboardKey.keyD, control: true, shift: true),
      'new_split',
      'right',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.keyD, meta: true, shift: true)
          : const KeyChord(
              LogicalKeyboardKey.keyD,
              control: true,
              shift: true,
              alt: true,
            ),
      'new_split',
      'down',
    ),
    for (final (key, dir) in _arrows) ...[
      b(
        mac
            ? KeyChord(key, meta: true, alt: true)
            : KeyChord(key, control: true, alt: true),
        'goto_split',
        dir,
      ),
      b(
        mac
            ? KeyChord(key, meta: true, control: true)
            : KeyChord(key, control: true, shift: true, alt: true),
        'resize_split',
        dir,
      ),
    ],
    // A11 D15: Cmd+Ctrl+[ / ] on macOS; Ctrl+Alt+[ / ] on Windows (left
    // Alt only).
    for (final (key, which) in [
      (LogicalKeyboardKey.bracketLeft, 'back'),
      (LogicalKeyboardKey.bracketRight, 'forward'),
    ])
      b(
        mac
            ? KeyChord(key, meta: true, control: true)
            : KeyChord(key, control: true, alt: true),
        'focus_history',
        which,
      ),
    for (final enter in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      b(
        mac
            ? KeyChord(enter, meta: true, shift: true)
            : KeyChord(enter, control: true, shift: true),
        'toggle_split_zoom',
      ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.equal, meta: true, control: true)
          : const KeyChord(
              LogicalKeyboardKey.equal,
              control: true,
              shift: true,
              alt: true,
            ),
      'equalize_splits',
    ),
    // A11 D11: Terminal.app / iTerm line editing; macOS only.
    if (mac) ...[
      b(
        const KeyChord(LogicalKeyboardKey.arrowLeft, meta: true),
        'edit_line',
        'line_start',
      ),
      b(
        const KeyChord(LogicalKeyboardKey.arrowRight, meta: true),
        'edit_line',
        'line_end',
      ),
      b(
        const KeyChord(LogicalKeyboardKey.backspace, meta: true),
        'edit_line',
        'delete_line',
      ),
      b(
        const KeyChord(LogicalKeyboardKey.backspace, alt: true),
        'edit_line',
        'delete_word',
      ),
      b(
        const KeyChord(LogicalKeyboardKey.delete, alt: true),
        'edit_line',
        'delete_word_forward',
      ),
    ],
    // A11 D13: Cmd+Shift+M / Ctrl+Shift+M.
    b(shifted(LogicalKeyboardKey.keyM), 'toggle_copy_mode'),
    b(font(LogicalKeyboardKey.equal), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.equal, shift: true), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.add), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.numpadAdd), 'increase_font_size', '1'),
    b(font(LogicalKeyboardKey.minus), 'decrease_font_size', '1'),
    b(font(LogicalKeyboardKey.numpadSubtract), 'decrease_font_size', '1'),
    b(font(LogicalKeyboardKey.digit0), 'reset_font_size'),
    b(font(LogicalKeyboardKey.numpad0), 'reset_font_size'),
    b(const KeyChord(LogicalKeyboardKey.f6, control: true), 'next_region'),
    b(
      const KeyChord(LogicalKeyboardKey.f6, control: true, shift: true),
      'previous_region',
    ),
    // A9 D24.
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.comma, meta: true, shift: true)
          : const KeyChord(
              LogicalKeyboardKey.comma,
              control: true,
              shift: true,
            ),
      'reload_config',
    ),
    // A11 D10 (a deliberate change of A9 D37): ⌘, / Ctrl+, opens Settings;
    // the file moves to ⌘⌥, / Ctrl+Shift+Alt+, (Windows: left Alt only).
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.comma, meta: true)
          : const KeyChord(LogicalKeyboardKey.comma, control: true),
      'open_settings',
    ),
    b(
      mac
          ? const KeyChord(LogicalKeyboardKey.comma, meta: true, alt: true)
          : const KeyChord(
              LogicalKeyboardKey.comma,
              control: true,
              shift: true,
              alt: true,
            ),
      'open_config',
    ),
    b(shifted(LogicalKeyboardKey.keyP), 'toggle_command_palette'),
  ];
}

/// D22: split at the first `=` that is not right after `+` or `>` (so
/// `super+==…` binds the `=` key).
({String trigger, String action})? splitKeybind(String value) {
  for (var i = 1; i < value.length; i++) {
    if (value[i] == '=' && value[i - 1] != '+' && value[i - 1] != '>') {
      final trigger = value.substring(0, i).trim();
      final action = value.substring(i + 1).trim();
      if (trigger.isEmpty || action.isEmpty) return null;
      return (trigger: trigger, action: action);
    }
  }
  return null;
}

final Set<KeyChord> _reservedMac = {
  for (final t in [
    'super+q',
    'super+h',
    'super+alt+h',
    'super+m',
    'super+tab',
    'super+shift+tab',
    'super+space',
    'ctrl+space',
    'ctrl+super+space',
    'super+grave',
    'super+shift+grave',
    'super+alt+escape',
    'ctrl+super+q',
    'ctrl+super+f',
    'super+shift+3',
    'super+shift+4',
    'super+shift+5',
  ])
    parseKeyChord(t)!,
};

final Set<KeyChord> _reservedWindows = {
  for (final t in [
    'alt+f4',
    'alt+tab',
    'alt+shift+tab',
    'alt+escape',
    'ctrl+escape',
    'ctrl+shift+escape',
    'alt+space',
    'ctrl+alt+delete',
  ])
    parseKeyChord(t)!,
};

bool _reserved(KeyChord c, {required bool mac}) =>
    mac ? _reservedMac.contains(c) : (c.meta || _reservedWindows.contains(c));

bool _isLetter(LogicalKeyboardKey k) => k.keyId >= 0x61 && k.keyId <= 0x7a;

bool _isArrow(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.arrowLeft ||
    k == LogicalKeyboardKey.arrowRight ||
    k == LogicalKeyboardKey.arrowUp ||
    k == LogicalKeyboardKey.arrowDown;

/// D25: an error drops the binding; notes keep it.
({ConfigProblemCode? error, List<ConfigProblemCode> notes}) checkTrigger(
  List<KeyChord> seq,
  KeyAction action, {
  required bool mac,
  required OptionAsAlt optionAsAlt,
}) {
  for (final c in seq) {
    if (_reserved(c, mac: mac)) {
      return (error: ConfigProblemCode.reservedTrigger, notes: const []);
    }
  }
  final c = seq.first;
  if (c.key == LogicalKeyboardKey.f6 && !c.control && !c.alt && !c.meta) {
    return (error: ConfigProblemCode.regionTrigger, notes: const []);
  }
  if (!c.hasCommandModifier) {
    // D25's Esc exception for `browser_stop` comes with A6.
    if (!isFunctionKey(c.key)) {
      return (error: ConfigProblemCode.plainKeyTrigger, notes: const []);
    }
  }
  final notes = <ConfigProblemCode>[];
  if (c.control && !c.alt && !c.meta && !c.shift && _isLetter(c.key)) {
    notes.add(ConfigProblemCode.shellKeyTrigger);
  }
  if (mac &&
      c.alt &&
      !c.control &&
      !c.meta &&
      isPrintableKey(c.key) &&
      optionAsAlt == OptionAsAlt.off) {
    notes.add(ConfigProblemCode.optionKeyTrigger);
  }
  if (!mac && c.control && c.alt && isPrintableKey(c.key)) {
    notes.add(ConfigProblemCode.altGrTrigger);
  }
  if (mac && c.control && !c.meta && !c.alt && _isArrow(c.key)) {
    notes.add(ConfigProblemCode.missionControlTrigger);
  }
  return (error: null, notes: notes);
}

final RegExp _prefix = RegExp(r'^(global|all|unconsumed|performable):');

/// D22–D27: the defaults, then each `keybind` line in order.
KeyBindings resolveKeyBindings({
  required TargetPlatform platform,
  required List<KeybindEntry> entries,
  required Set<String> commandNames,
  required OptionAsAlt optionAsAlt,
  required List<ConfigProblem> problems,
}) {
  final mac = platform == TargetPlatform.macOS;
  final slots = <KeyBinding>[...defaultKeyBindings(platform)];

  void report(
    ConfigEntry at,
    ConfigSeverity severity,
    ConfigProblemCode code, {
    String? value,
    String? hint,
    String? detail,
  }) => problems.add(
    ConfigProblem(
      file: at.file,
      line: at.line,
      severity: severity,
      code: code,
      key: 'keybind',
      value: value,
      hint: hint,
      detail: detail,
    ),
  );

  for (final entry in entries) {
    final at = entry.origin;
    final text = entry.value.trim();
    if (text == 'clear') {
      slots.clear();
      continue;
    }
    final split = splitKeybind(text);
    if (split == null) {
      report(
        at,
        ConfigSeverity.error,
        ConfigProblemCode.badTrigger,
        value: text,
      );
      continue;
    }
    var trigger = split.trigger;
    var refused = false;
    for (
      var m = _prefix.firstMatch(trigger);
      m != null;
      m = _prefix.firstMatch(trigger)
    ) {
      final prefix = m.group(1)!;
      if (prefix == 'global') {
        report(
          at,
          ConfigSeverity.error,
          ConfigProblemCode.unsupportedPrefix,
          value: 'global:',
        );
        refused = true;
        break;
      }
      report(
        at,
        ConfigSeverity.info,
        ConfigProblemCode.unsupportedPrefix,
        value: '$prefix:',
      );
      trigger = trigger.substring(m.end);
    }
    if (refused) continue;
    final steps = trigger.split('>');
    if (steps.length > 2) {
      report(at, ConfigSeverity.error, ConfigProblemCode.sequenceTooLong);
      continue;
    }
    final seq = [for (final s in steps) parseKeyChord(s)];
    if (seq.any((c) => c == null)) {
      report(
        at,
        ConfigSeverity.error,
        ConfigProblemCode.badTrigger,
        value: trigger,
      );
      continue;
    }
    final sequence = seq.cast<KeyChord>();
    if (split.action == 'unbind') {
      slots.removeWhere((b) => listEquals(b.sequence, sequence));
      continue;
    }
    final parsed = parseKeyAction(split.action);
    final action = parsed.action;
    if (action == null) {
      report(
        at,
        ConfigSeverity.error,
        parsed.problem!,
        value: split.action,
        hint: parsed.hint,
      );
      continue;
    }
    if (action.name == 'run_command' && !commandNames.contains(action.param)) {
      report(
        at,
        ConfigSeverity.warning,
        ConfigProblemCode.unknownCommand,
        value: action.param,
      );
      continue;
    }
    final label = sequenceLabel(sequence, mac: mac);
    final rule = checkTrigger(
      sequence,
      action,
      mac: mac,
      optionAsAlt: optionAsAlt,
    );
    if (rule.error != null) {
      report(at, ConfigSeverity.error, rule.error!, value: label);
      continue;
    }
    for (final note in rule.notes) {
      report(at, ConfigSeverity.info, note, value: label);
    }
    if (sequence.length == 2 && sequence[0] == sequence[1]) {
      report(
        at,
        ConfigSeverity.info,
        ConfigProblemCode.sequenceRepeatsPrefix,
        value: chordLabel(sequence[0], mac: mac),
      );
    }
    if (action.name == 'resize_split' && split.action.contains(',')) {
      report(
        at,
        ConfigSeverity.info,
        ConfigProblemCode.unsupportedValue,
        value: split.action,
        hint: '5 %',
      );
    }
    final scope = kActionSpecs[action.name]!.scope;
    bool same(KeyBinding b) =>
        b.scope == scope && listEquals(b.sequence, sequence);
    final previous = slots.where(same).firstOrNull;
    if (previous?.origin != null && previous!.action != action) {
      report(
        at,
        ConfigSeverity.info,
        ConfigProblemCode.duplicate,
        detail: '${previous.origin!.line}',
      );
    }
    slots
      ..removeWhere(same)
      ..add(KeyBinding(sequence, action, origin: at));
  }

  // D27: a sequence's first step no longer works on its own.
  for (final s in [...slots.where((b) => b.sequence.length == 2)]) {
    final prefix = [s.sequence.first];
    final shadowed = slots
        .where((b) => b.sequence.length == 1 && listEquals(b.sequence, prefix))
        .toList();
    if (shadowed.isEmpty) continue;
    slots.removeWhere(shadowed.contains);
    if (s.origin != null) {
      report(
        s.origin!,
        ConfigSeverity.warning,
        ConfigProblemCode.sequencePrefixShadows,
        value: chordLabel(prefix.single, mac: mac),
      );
    }
  }
  return KeyBindings(platform, slots);
}
