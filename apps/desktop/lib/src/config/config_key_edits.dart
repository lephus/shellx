import 'config_writer.dart';

/// A11 D5: the second block ShellX manages, for keys the Settings screen
/// writes. A9's keybinding block (`kManagedStart`) is separate and never
/// touched here.
const kSettingsStart = '# >>> shellx-managed settings >>>';
const kSettingsEnd = '# <<< shellx-managed settings <<<';
const _blockNote =
    '# Written by ShellX Settings. Edit freely; delete the block to forget it.';

/// One change to one scalar key. `toString()` is `…`: a value is the
/// user's.
sealed class KeyEdit {
  const KeyEdit(this.key);
  final String key;

  @override
  String toString() => '…';
}

/// Make [key] [value]. An empty value writes `key =` (the key reset to
/// ShellX's own default, A9 D5).
final class SetKey extends KeyEdit {
  const SetKey(super.key, this.value);
  final String value;
}

/// Undo what the user (or Settings) set. A line is never deleted from the
/// user's own text: it is commented out. [explicitDefault] also writes
/// `key =` in the block, for a value that comes from a Ghostty file.
final class ResetKey extends KeyEdit {
  const ResetKey(super.key, {this.explicitDefault = false});
  final bool explicitDefault;
}

/// Keys that are not scalar settings: their own blocks and the include list.
const _notEdited = {'keybind', 'config-file'};

final RegExp _validKey = RegExp(r'^[a-z0-9][a-z0-9-]*$');
final RegExp _loneCr = RegExp(r'\r(?!\n)');

/// Applies [edits] in order. Every byte outside the lines of the edited
/// keys stays (BOM, CRLF, comments, blank lines, other blocks). Throws
/// [ConfigWriteRefused] (damagedBlock) when either managed block has a lone
/// or doubled marker, when the two blocks overlap, and
/// ([ConfigWriteRefusal.loneCarriageReturn]) for a file the loader reads
/// as one line; [ArgumentError] for a key that is not a config key or a
/// value with a line break (it would write a second line).
String applyKeyEdits(String text, List<KeyEdit> edits) {
  if (edits.isEmpty) return text;
  for (final e in edits) {
    if (!_validKey.hasMatch(e.key) || _notEdited.contains(e.key)) {
      throw ArgumentError.value('…', 'key');
    }
    if (e is SetKey && e.value.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError.value('…', 'value');
    }
  }
  if (_loneCr.hasMatch(text)) {
    throw const ConfigWriteRefused(ConfigWriteRefusal.loneCarriageReturn);
  }
  var out = text;
  for (final e in edits) {
    out = switch (e) {
      SetKey() => _set(out, e.key, e.value),
      ResetKey() => _reset(out, e),
    };
  }
  return out;
}

typedef _Range = ({int start, int end});

/// The two blocks of [lines], validated: each may be absent, never lone,
/// doubled, reversed, nor overlapping the other.
({_Range? mine, _Range? keys}) _blocks(List<ConfigLineSpan> lines) {
  _Range? find(String start, String end) {
    final s = <int>[], e = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final b = lines[i].body.trim();
      if (b == start) s.add(i);
      if (b == end) e.add(i);
    }
    if (s.isEmpty && e.isEmpty) return null;
    if (s.length == 1 && e.length == 1 && s.single < e.single) {
      return (start: s.single, end: e.single);
    }
    throw const ConfigWriteRefused(ConfigWriteRefusal.damagedBlock);
  }

  final mine = find(kSettingsStart, kSettingsEnd);
  final keys = find(kManagedStart, kManagedEnd);
  if (mine != null &&
      keys != null &&
      mine.start <= keys.end &&
      keys.start <= mine.end) {
    throw const ConfigWriteRefused(ConfigWriteRefusal.damagedBlock);
  }
  return (mine: mine, keys: keys);
}

/// The key of a line the way the loader reads it: trimmed, whole-line `#`
/// comments skipped, the first `=` splits.
String? _keyOf(String body) {
  final t = body.trim();
  if (t.isEmpty || t.startsWith('#')) return null;
  final eq = t.indexOf('=');
  return eq < 0 ? null : t.substring(0, eq).trim();
}

String _endingOf(String raw) =>
    raw.endsWith('\r\n') ? '\r\n' : (raw.endsWith('\n') ? '\n' : '');

String _line(String key, String value) =>
    value.isEmpty ? '$key =' : '$key = $value';

String _set(String text, String key, String value) {
  final lines = splitConfigLines(text);
  final b = _blocks(lines);
  final mine = b.mine, keys = b.keys;
  bool inKeys(int i) => keys != null && i >= keys.start && i <= keys.end;

  // 1. The line in effect: the last one for the key anywhere in the file
  //    except the keybind block. A user's line is edited in place (key
  //    spelling, spacing and line ending kept); one of ours the same way.
  for (var i = lines.length - 1; i >= 0; i--) {
    if (inKeys(i) || _keyOf(lines[i].body) != key) continue;
    final span = lines[i];
    final raw = text.substring(span.start, span.end);
    final body = raw.substring(0, raw.length - _endingOf(raw).length);
    final eq = body.indexOf('=');
    final afterEq = body.substring(eq + 1);
    final ws = afterEq.substring(0, afterEq.length - afterEq.trimLeft().length);
    final hadValue = afterEq.trim().isNotEmpty;
    final gap = value.isEmpty ? '' : (hadValue || ws.isNotEmpty ? ws : ' ');
    return text.replaceRange(
      span.start,
      span.end,
      '${body.substring(0, eq + 1)}$gap$value${_endingOf(raw)}',
    );
  }

  final eol = eolBefore(text, lines, mine?.start ?? lines.length);
  final newLine = _line(key, value);
  // 2. Our block exists: the key joins it.
  if (mine != null) {
    final at = lines[mine.end].start;
    return text.replaceRange(at, at, '$newLine$eol');
  }
  // 3. A new block at the very end (after the keybind block, if any).
  final head = text.isEmpty || text.endsWith('\n') ? text : '$text$eol';
  final sep = head.isEmpty || head.endsWith('$eol$eol') ? '' : eol;
  return '$head$sep$kSettingsStart$eol$_blockNote$eol$newLine$eol$kSettingsEnd$eol';
}

String _reset(String text, ResetKey r) {
  final lines = splitConfigLines(text);
  final b = _blocks(lines);
  final mine = b.mine, keys = b.keys;
  bool inKeys(int i) => keys != null && i >= keys.start && i <= keys.end;
  final buf = StringBuffer();
  var touched = false;
  for (var i = 0; i < lines.length; i++) {
    final raw = text.substring(lines[i].start, lines[i].end);
    final isKey = !inKeys(i) && _keyOf(lines[i].body) == r.key;
    final inMine = mine != null && i > mine.start && i < mine.end;
    if (isKey && inMine) {
      touched = true; // our own line: gone
      continue;
    }
    if (isKey) {
      final indent = raw.substring(0, raw.length - raw.trimLeft().length);
      buf.write('$indent# ${raw.trimLeft()}');
      touched = true;
      continue;
    }
    buf.write(raw);
  }
  var out = touched ? _dropEmptyBlock(buf.toString()) : text;
  if (r.explicitDefault) out = _set(out, r.key, '');
  return out;
}

/// Our block with nothing left in it but the note goes away.
String _dropEmptyBlock(String text) {
  final lines = splitConfigLines(text);
  final mine = _blocks(lines).mine;
  if (mine == null) return text;
  for (var i = mine.start + 1; i < mine.end; i++) {
    final t = lines[i].body.trim();
    if (t.isNotEmpty && t != _blockNote) return text;
  }
  return text.replaceRange(lines[mine.start].start, lines[mine.end].end, '');
}

/// 1-based lines of the two settings markers, or null when there is no
/// block or it is damaged (the caller shows file lines inside it as
/// ShellX's own).
({int first, int last})? settingsBlockLines(String text) {
  try {
    final mine = _blocks(splitConfigLines(text)).mine;
    return mine == null ? null : (first: mine.start + 1, last: mine.end + 1);
  } on ConfigWriteRefused {
    return null;
  }
}

/// "Undo everything changed here" (A11 D9): the settings block goes, markers
/// and lines; every other byte stays, the keybind block included. Throws
/// [ConfigWriteRefused] (damagedBlock) when a marker is lone or doubled.
String removeSettingsBlock(String text) {
  final lines = splitConfigLines(text);
  final mine = _blocks(lines).mine;
  if (mine == null) return text;
  return text.replaceRange(lines[mine.start].start, lines[mine.end].end, '');
}
