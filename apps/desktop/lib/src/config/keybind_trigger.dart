import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One key combination (A9 D22). [meta] is super: ⌘ on macOS, Win on
/// Windows.
@immutable
final class KeyChord {
  const KeyChord(
    this.key, {
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  bool get hasCommandModifier => control || alt || meta;

  @override
  bool operator ==(Object other) =>
      other is KeyChord &&
      other.key == key &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, control, alt, shift, meta);

  @override
  String toString() => chordConfigText(this) ?? 'KeyChord(${key.debugName})';
}

const _digits = [
  LogicalKeyboardKey.digit0,
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

const _numpadDigits = [
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

const _functionKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
];

/// Canonical config names first: [chordConfigText] writes the first name
/// of each key.
final List<(String, LogicalKeyboardKey)> _names = [
  ('enter', LogicalKeyboardKey.enter),
  ('return', LogicalKeyboardKey.enter),
  ('tab', LogicalKeyboardKey.tab),
  ('escape', LogicalKeyboardKey.escape),
  ('space', LogicalKeyboardKey.space),
  ('backspace', LogicalKeyboardKey.backspace),
  ('delete', LogicalKeyboardKey.delete),
  ('insert', LogicalKeyboardKey.insert),
  ('home', LogicalKeyboardKey.home),
  ('end', LogicalKeyboardKey.end),
  ('page_up', LogicalKeyboardKey.pageUp),
  ('page_down', LogicalKeyboardKey.pageDown),
  ('arrow_left', LogicalKeyboardKey.arrowLeft),
  ('left', LogicalKeyboardKey.arrowLeft),
  ('arrow_right', LogicalKeyboardKey.arrowRight),
  ('right', LogicalKeyboardKey.arrowRight),
  ('arrow_up', LogicalKeyboardKey.arrowUp),
  ('up', LogicalKeyboardKey.arrowUp),
  ('arrow_down', LogicalKeyboardKey.arrowDown),
  ('down', LogicalKeyboardKey.arrowDown),
  ('equal', LogicalKeyboardKey.equal),
  ('minus', LogicalKeyboardKey.minus),
  ('plus', LogicalKeyboardKey.add),
  ('comma', LogicalKeyboardKey.comma),
  ('period', LogicalKeyboardKey.period),
  ('slash', LogicalKeyboardKey.slash),
  ('backslash', LogicalKeyboardKey.backslash),
  ('semicolon', LogicalKeyboardKey.semicolon),
  ('quote', LogicalKeyboardKey.quote),
  ('backquote', LogicalKeyboardKey.backquote),
  ('grave', LogicalKeyboardKey.backquote),
  ('bracket_left', LogicalKeyboardKey.bracketLeft),
  ('bracket_right', LogicalKeyboardKey.bracketRight),
  ('kp_enter', LogicalKeyboardKey.numpadEnter),
  ('kp_add', LogicalKeyboardKey.numpadAdd),
  ('kp_subtract', LogicalKeyboardKey.numpadSubtract),
  for (var i = 0; i <= 9; i++) ('kp_$i', _numpadDigits[i]),
  for (var i = 0; i <= 9; i++) ('digit_$i', _digits[i]),
  for (var i = 1; i <= 24; i++) ('f$i', _functionKeys[i - 1]),
];

final Map<String, LogicalKeyboardKey> _byName = {
  for (final (name, key) in _names) name: key,
};

final Map<LogicalKeyboardKey, String> _nameOf = () {
  final map = <LogicalKeyboardKey, String>{};
  for (final (name, key) in _names) {
    map.putIfAbsent(key, () => name);
  }
  // Letters and digits are written as themselves.
  for (var i = 0; i <= 9; i++) {
    map[_digits[i]] = '$i';
  }
  return map;
}();

const Map<String, LogicalKeyboardKey> _punctuation = {
  '=': LogicalKeyboardKey.equal,
  '-': LogicalKeyboardKey.minus,
  '[': LogicalKeyboardKey.bracketLeft,
  ']': LogicalKeyboardKey.bracketRight,
  ';': LogicalKeyboardKey.semicolon,
  "'": LogicalKeyboardKey.quote,
  ',': LogicalKeyboardKey.comma,
  '.': LogicalKeyboardKey.period,
  '/': LogicalKeyboardKey.slash,
  r'\': LogicalKeyboardKey.backslash,
  '`': LogicalKeyboardKey.backquote,
  '+': LogicalKeyboardKey.add,
};

LogicalKeyboardKey? _keyForToken(String token) {
  final lower = token.toLowerCase();
  final named = _byName[lower];
  if (named != null) return named;
  if (token.runes.length != 1) return null;
  final punct = _punctuation[token];
  if (punct != null) return punct;
  final cp = lower.runes.single;
  if (cp >= 0x61 && cp <= 0x7a) return LogicalKeyboardKey.findKeyByKeyId(cp);
  if (cp >= 0x30 && cp <= 0x39) return _digits[cp - 0x30];
  if (cp < 0x80) return null; // other ASCII: not a key token
  return LogicalKeyboardKey(cp); // layout characters (ö, é…), like Ghostty
}

/// D22: `mod+mod+key`; `+` itself as `ctrl++` or `plus`.
KeyChord? parseKeyChord(String text) {
  final step = text.trim();
  if (step.isEmpty) return null;
  final String keyToken;
  final List<String> mods;
  if (step == '+') {
    keyToken = '+';
    mods = const [];
  } else if (step.endsWith('++')) {
    keyToken = '+';
    mods = step.substring(0, step.length - 2).split('+');
  } else {
    final parts = step.split('+');
    keyToken = parts.last;
    mods = parts.sublist(0, parts.length - 1);
  }
  if (keyToken.isEmpty) return null;
  var control = false, alt = false, shift = false, meta = false;
  for (final m in mods) {
    switch (m.toLowerCase()) {
      case 'ctrl' || 'control':
        control = true;
      case 'alt' || 'opt' || 'option':
        alt = true;
      case 'shift':
        shift = true;
      case 'super' || 'cmd' || 'command':
        meta = true;
      default:
        return null;
    }
  }
  final key = _keyForToken(keyToken);
  if (key == null) return null;
  return KeyChord(key, control: control, alt: alt, shift: shift, meta: meta);
}

bool isFunctionKey(LogicalKeyboardKey k) => _functionKeys.contains(k);

bool isPrintableKey(LogicalKeyboardKey k) {
  if (k == LogicalKeyboardKey.space) return true;
  if (_punctuation.containsValue(k)) return true;
  final id = k.keyId;
  return id >= 0x21 && id < 0x110000 && k.keyLabel.runes.length == 1;
}

String _keyLabel(LogicalKeyboardKey k, {required bool mac}) {
  final special = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.enter: mac ? '↩' : 'Enter',
    LogicalKeyboardKey.numpadEnter: mac ? '⌤' : 'Num Enter',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.backspace: mac ? '⌫' : 'Backspace',
    LogicalKeyboardKey.delete: mac ? '⌦' : 'Delete',
    LogicalKeyboardKey.insert: 'Insert',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PgUp',
    LogicalKeyboardKey.pageDown: 'PgDn',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.add: '+',
    LogicalKeyboardKey.numpadAdd: 'Num+',
    LogicalKeyboardKey.numpadSubtract: 'Num−',
  };
  final s = special[k];
  if (s != null) return s;
  final fn = _functionKeys.indexOf(k);
  if (fn >= 0) return 'F${fn + 1}';
  final pad = _numpadDigits.indexOf(k);
  if (pad >= 0) return 'Num$pad';
  final label = k.keyLabel;
  return label.isEmpty ? (k.debugName ?? '?') : label.toUpperCase();
}

/// D29: macOS ⌘⌃⌥⇧ then the key (the order A1–A4 labels already use:
/// "⌘⇧D", "⌘⌃="); Windows Ctrl+Shift+Alt+Win+key ("Ctrl+Shift+Alt+D").
String chordLabel(KeyChord c, {required bool mac}) {
  final key = _keyLabel(c.key, mac: mac);
  if (mac) {
    return '${c.meta ? '⌘' : ''}${c.control ? '⌃' : ''}'
        '${c.alt ? '⌥' : ''}${c.shift ? '⇧' : ''}$key';
  }
  return [
    if (c.control) 'Ctrl',
    if (c.shift) 'Shift',
    if (c.alt) 'Alt',
    if (c.meta) 'Win',
    key,
  ].join('+');
}

String sequenceLabel(List<KeyChord> s, {required bool mac}) =>
    s.map((c) => chordLabel(c, mac: mac)).join(' ');

/// The config spelling (`ctrl+alt+shift+super+key`); null for a key with
/// no spelling (the recorder refuses it).
String? chordConfigText(KeyChord c) {
  var name = _nameOf[c.key];
  if (name == null) {
    final id = c.key.keyId;
    if (id >= 0x61 && id <= 0x7a) {
      name = String.fromCharCode(id);
    } else if (id >= 0x80 && id < 0x110000 && c.key.keyLabel.isNotEmpty) {
      name = String.fromCharCode(id);
    } else {
      return null;
    }
  }
  return [
    if (c.control) 'ctrl',
    if (c.alt) 'alt',
    if (c.shift) 'shift',
    if (c.meta) 'super',
    name,
  ].join('+');
}

SingleActivator chordActivator(KeyChord c, {required bool repeats}) =>
    SingleActivator(
      c.key,
      control: c.control,
      alt: c.alt,
      shift: c.shift,
      meta: c.meta,
      includeRepeats: repeats,
    );

/// The golden fixtures' spelling of an activator (Task 4 Step 1).
String describeActivator(ShortcutActivator a) {
  final s = a as SingleActivator;
  return [
        if (s.control) 'ctrl',
        if (s.alt) 'alt',
        if (s.shift) 'shift',
        if (s.meta) 'meta',
        s.trigger.keyId.toRadixString(16),
      ].join('+') +
      (s.includeRepeats ? '' : ' norepeat');
}

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// The chord a key-down makes; null for a modifier on its own.
KeyChord? chordOfEvent(KeyEvent event, HardwareKeyboard keyboard) {
  if (_modifierKeys.contains(event.logicalKey)) return null;
  return KeyChord(
    event.logicalKey,
    control: keyboard.isControlPressed,
    alt: keyboard.isAltPressed,
    shift: keyboard.isShiftPressed,
    meta: keyboard.isMetaPressed,
  );
}

/// A9 D26: real AltGr on Windows is Ctrl + right Alt together; the key is
/// then the keyboard layout's. A right Alt alone (stuck, or a plain Alt
/// key) is not AltGr, and macOS has none.
bool altGrHeld(Set<LogicalKeyboardKey> pressed, TargetPlatform platform) =>
    platform == TargetPlatform.windows &&
    pressed.contains(LogicalKeyboardKey.altRight) &&
    pressed.contains(LogicalKeyboardKey.controlLeft);
