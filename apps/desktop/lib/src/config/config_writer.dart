import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'config_files.dart';
import 'config_syntax.dart';
import 'keybind_actions.dart';
import 'keybind_trigger.dart';
import 'keybindings.dart';

const kManagedStart = '# >>> shellx-managed keybinds >>>';
const kManagedEnd = '# <<< shellx-managed keybinds <<<';

sealed class BindingEdit {
  const BindingEdit();
}

final class AddBinding extends BindingEdit {
  const AddBinding(this.chord, this.action);
  final KeyChord chord;
  final KeyAction action;
}

/// [isDefault]: the chord is one of the platform defaults (then an
/// `unbind` line is needed to take it away).
final class RemoveBinding extends BindingEdit {
  const RemoveBinding(this.chord, {required this.isDefault});
  final KeyChord chord;
  final bool isDefault;
}

final class ResetAction extends BindingEdit {
  const ResetAction(this.action, this.defaultChords);
  final KeyAction action;
  final List<KeyChord> defaultChords;
}

typedef _Line = ({String trigger, String action});

_Line? _parse(String line) {
  final t = line.trim();
  if (!t.startsWith('keybind')) return null;
  final eq = t.indexOf('=');
  if (eq < 0 || t.substring(0, eq).trim() != 'keybind') return null;
  final split = splitKeybind(t.substring(eq + 1).trim());
  return split == null ? null : (trigger: split.trigger, action: split.action);
}

/// One line of the text: where it starts, where it ends (past its `\n`),
/// and what it says without the line ending.
typedef _Span = ({int start, int end, String body});

List<_Span> _lines(String text) {
  final spans = <_Span>[];
  var pos = 0;
  while (pos < text.length) {
    final nl = text.indexOf('\n', pos);
    final end = nl < 0 ? text.length : nl + 1;
    spans.add((
      start: pos,
      end: end,
      body: text.substring(pos, nl < 0 ? text.length : nl).trimRight(),
    ));
    pos = end;
  }
  return spans;
}

/// What the marker lines make of the file: no block, one block, or a
/// damaged one (a marker alone, a second block, an end before its start).
/// A marker quoted in a comment is not a marker (the whole line is).
typedef _Scan = ({({int start, int end})? block, bool damaged});

_Scan _scan(List<_Span> lines) {
  final starts = <int>[];
  final ends = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final body = lines[i].body.trim();
    if (body == kManagedStart) starts.add(i);
    if (body == kManagedEnd) ends.add(i);
  }
  if (starts.isEmpty && ends.isEmpty) return (block: null, damaged: false);
  if (starts.length == 1 && ends.length == 1 && starts.single < ends.single) {
    return (block: (start: starts.single, end: ends.single), damaged: false);
  }
  return (block: null, damaged: true);
}

/// 1-based lines of the two markers, or null.
({int first, int last})? managedLineRange(String text) {
  final block = _scan(_lines(text)).block;
  return block == null ? null : (first: block.start + 1, last: block.end + 1);
}

bool _sameChord(String trigger, KeyChord chord) =>
    parseKeyChord(trigger) == chord;

/// The line ending of the line before [index] (the end of the text when
/// the block is yet to be added); when that line has none, the first one
/// the text has; else `\n`.
String _eolBefore(String text, List<_Span> lines, int index) {
  String? ending(_Span line) {
    final raw = text.substring(line.start, line.end);
    if (raw.endsWith('\r\n')) return '\r\n';
    return raw.endsWith('\n') ? '\n' : null;
  }

  if (index > 0) {
    final own = ending(lines[index - 1]);
    if (own != null) return own;
  }
  for (final line in lines) {
    final e = ending(line);
    if (e != null) return e;
  }
  return '\n';
}

/// A line of the block: what it says (a `keybind`) or free text the user
/// put there, kept as it was.
typedef _Item = ({String text, _Line? bind});

/// D32: edits only the managed block (appended at the end when missing,
/// removed when it ends up empty); every other byte stays.
String applyBindingEdits(String text, List<BindingEdit> edits) {
  final lines = _lines(text);
  final scan = _scan(lines);
  if (scan.damaged) {
    throw const ConfigWriteRefused(ConfigWriteRefusal.damagedBlock);
  }
  final found = scan.block;
  final eol = _eolBefore(text, lines, found?.start ?? lines.length);
  final String head;
  final String tail;
  final items = <_Item>[];
  if (found != null) {
    head = text.substring(0, lines[found.start].start);
    tail = text.substring(lines[found.end].end);
    for (var i = found.start + 1; i < found.end; i++) {
      final body = lines[i].body;
      items.add((text: body, bind: _parse(body)));
    }
  } else {
    head = text;
    tail = '';
  }
  // Lines outside the block that bind a chord (for RemoveBinding).
  final outside = [for (final raw in '$head$tail'.split('\n')) ?_parse(raw)];

  _Item bind(String trigger, String action) => (
    text: 'keybind = $trigger=$action',
    bind: (trigger: trigger, action: action),
  );

  for (final edit in edits) {
    switch (edit) {
      case AddBinding(:final chord, :final action):
        final trigger = chordConfigText(chord)!;
        items
          ..removeWhere(
            (i) => i.bind != null && _sameChord(i.bind!.trigger, chord),
          )
          ..add(bind(trigger, action.text));
      case RemoveBinding(:final chord, :final isDefault):
        items.removeWhere(
          (i) => i.bind != null && _sameChord(i.bind!.trigger, chord),
        );
        final boundOutside = outside.any(
          (l) => _sameChord(l.trigger, chord) && l.action != 'unbind',
        );
        if (isDefault || boundOutside) {
          items.add(bind(chordConfigText(chord)!, 'unbind'));
        }
      case ResetAction(:final action, :final defaultChords):
        items.removeWhere((i) {
          final b = i.bind;
          return b != null &&
              (b.action == action.text ||
                  (b.action == 'unbind' &&
                      defaultChords.any((c) => _sameChord(b.trigger, c))));
        });
    }
  }

  if (items.every((i) => i.text.trim().isEmpty)) return head + tail;
  final body = [
    kManagedStart,
    for (final i in items) i.text,
    kManagedEnd,
  ].join(eol);
  if (found != null) return '$head$body$eol$tail';
  final sep = head.isEmpty || head.endsWith('\n') ? '' : eol;
  return '$head$sep$body$eol';
}

/// Why a write was not made (the file is left as it was).
enum ConfigWriteRefusal {
  /// UTF-16: the app does not rewrite it; edit by hand.
  utf16,

  /// Not valid UTF-8.
  notUtf8,

  /// The file, or what it would become, is over [kConfigMaxBytes].
  tooLarge,

  /// The file exists but can't be read (or is not a regular file).
  unreadable,

  /// The file changed on disk since it was read.
  changed,

  /// NUL bytes: UTF-16 without a byte-order mark, or not text at all.
  notText,

  /// The managed block's markers are damaged (a lone marker, two blocks):
  /// the app edits nothing rather than guess.
  damagedBlock,
}

final class ConfigWriteRefused implements Exception {
  const ConfigWriteRefused(this.reason);
  final ConfigWriteRefusal reason;

  @override
  String toString() => 'ConfigWriteRefused(${reason.name})';
}

abstract interface class ConfigFileStore {
  /// Null when [path] does not exist. Throws [ConfigTooLarge] above
  /// [kConfigMaxBytes] and [FileSystemException] when it can't be read.
  Future<Uint8List?> read(String path);

  /// Replaces [path] atomically (a temporary file renamed over it).
  /// [expected] is what the caller read: when the file holds something
  /// else by now (or [mustNotExist] and it exists) the write is refused
  /// with [ConfigWriteRefusal.changed] and nothing is touched.
  Future<void> replace(
    String path,
    Uint8List bytes, {
    Uint8List? expected,
    bool mustNotExist = false,
  });
}

var _tempCounter = 0;

final class IoConfigFileStore implements ConfigFileStore {
  const IoConfigFileStore();

  @override
  Future<Uint8List?> read(String path) => const IoConfigFs().read(path);

  /// The file a write to [path] ends up in: through every symlink, a
  /// dangling one included (dotfiles managers).
  static Future<String> _realTarget(String path) async {
    var target = path;
    for (var hops = 0; hops < 16; hops++) {
      if (!await FileSystemEntity.isLink(target)) return target;
      try {
        return await File(target).resolveSymbolicLinks();
      } on FileSystemException {
        // Dangling: follow it one step by hand.
        final next = await Link(target).target();
        target = p.isAbsolute(next)
            ? next
            : p.normalize(p.join(p.dirname(target), next));
      }
    }
    throw FileSystemException('too many symbolic links', path);
  }

  static Future<void> _chmod(String path, String mode) async {
    if (Platform.isWindows) return;
    final result = await Process.run('/bin/chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod failed', path);
    }
  }

  @override
  Future<void> replace(
    String path,
    Uint8List bytes, {
    Uint8List? expected,
    bool mustNotExist = false,
  }) async {
    // A symlinked config is written through the link: the link stays a
    // link, and the temporary file sits beside the real target so the
    // rename never crosses a volume.
    final target = await _realTarget(path);
    await Directory(p.dirname(target)).create(recursive: true);
    final existing = File(target);
    final stat = await existing.stat();
    final exists = stat.type != FileSystemEntityType.notFound;
    if (mustNotExist && exists) {
      throw const ConfigWriteRefused(ConfigWriteRefusal.changed);
    }
    final temp = File('$target.shellx-tmp-$pid-${_tempCounter++}');
    try {
      await temp.create(exclusive: true);
      // Private from the first byte: the file may hold commands and paths,
      // so no moment where it is world-readable (the umask may allow that).
      await _chmod(temp.path, '600');
      await temp.writeAsBytes(bytes, flush: true);
      if (exists) {
        // The owner's choice (0600, 0444 …) survives; set after the content,
        // so a read-only source can still be replaced.
        await _chmod(temp.path, (stat.mode & 0xFFF).toRadixString(8));
      }
      // Last look before the swap: someone saved meanwhile → keep theirs.
      if (expected != null &&
          !listEquals(
            await existing.readAsBytes().catchError((_) => Uint8List(0)),
            expected,
          )) {
        throw const ConfigWriteRefused(ConfigWriteRefusal.changed);
      }
      await temp.rename(target);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Nothing more to do; the temporary name carries our pid.
      }
      rethrow;
    }
  }
}

final class ConfigFileWriter {
  ConfigFileWriter(this.store);
  final ConfigFileStore store;

  /// Reads the file now (not the copy from the last load), applies
  /// [edits], writes it back with the same BOM and line endings. Throws
  /// [ConfigWriteRefused] (the file untouched) for UTF-16 and non-UTF-8
  /// files, one over [kConfigMaxBytes] (or that the edit would make so),
  /// an unreadable one, and one that changed on disk meanwhile.
  Future<void> edit(
    String path,
    List<BindingEdit> edits, {
    required String template,
  }) async {
    final Uint8List? bytes;
    try {
      bytes = await store.read(path);
    } on ConfigTooLarge {
      throw const ConfigWriteRefused(ConfigWriteRefusal.tooLarge);
    } on FileSystemException {
      throw const ConfigWriteRefused(ConfigWriteRefusal.unreadable);
    }
    var bom = false;
    String text;
    if (bytes == null) {
      text = template;
    } else {
      if (bytes.length >= 2 &&
          ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
              (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
        throw const ConfigWriteRefused(ConfigWriteRefusal.utf16);
      }
      bom =
          bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      if (bytes.contains(0)) {
        throw const ConfigWriteRefused(ConfigWriteRefusal.notText);
      }
      try {
        text = decodeConfigBytes(bytes);
      } on FormatException {
        throw const ConfigWriteRefused(ConfigWriteRefusal.notUtf8);
      }
    }
    final edited = applyBindingEdits(text, edits);
    // Nothing to change: no write (and no file made from the template).
    if (edited == text) return;
    final next = Uint8List.fromList([
      if (bom) ...[0xEF, 0xBB, 0xBF],
      ...utf8.encode(edited),
    ]);
    if (next.length > kConfigMaxBytes) {
      throw const ConfigWriteRefused(ConfigWriteRefusal.tooLarge);
    }
    await store.replace(
      path,
      next,
      expected: bytes,
      mustNotExist: bytes == null,
    );
  }
}

final configFileStoreProvider = Provider<ConfigFileStore>(
  (ref) => const IoConfigFileStore(),
);

final configFileWriterProvider = Provider<ConfigFileWriter>(
  (ref) => ConfigFileWriter(ref.watch(configFileStoreProvider)),
);

/// The defaults of [action] on [platform] (single chords), for reset.
List<KeyChord> defaultChordsOf(KeyAction action, TargetPlatform platform) => [
  for (final b in defaultKeyBindings(platform))
    if (b.action == action && b.sequence.length == 1) b.sequence.single,
];
