import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One line of a `.gitignore`, compiled (ruling B12).
final class _Rule {
  const _Rule(this.re, {required this.negate, required this.dirOnly});
  final RegExp re;
  final bool negate;
  final bool dirOnly;
}

/// B12: ShellX's own reading of a project's `.gitignore` files, for `@` and
/// the Files panel. It never runs git, and never touches the project's own
/// `.git`. It covers `#` comments, `!` re-inclusion, a trailing `/` (folders
/// only), anchoring by a `/`, `*`, `?`, `[...]` and `**`; a deeper
/// `.gitignore` wins over a shallower one, and the last matching line of a
/// file wins. Global excludes and `.git/info/exclude` are not read.
final class AiGitIgnore {
  final _sets = <(String, List<_Rule>)>[];

  /// The `.gitignore` of folder [base] ('' is the project root), relative to
  /// the root with `/` separators.
  void add(String base, String text) {
    final rules = <_Rule>[];
    // Git skips a byte order mark at the start of the file.
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    for (var line in text.split('\n')) {
      line = line.replaceAll('\r', '');
      if (line.isEmpty || line.startsWith('#')) continue;
      // Trailing spaces go unless escaped.
      while (line.endsWith(' ') && !line.endsWith(r'\ ')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      var negate = false;
      if (line.startsWith('!')) {
        negate = true;
        line = line.substring(1);
      } else if (line.startsWith(r'\!') || line.startsWith(r'\#')) {
        line = line.substring(1);
      }
      var dirOnly = false;
      if (line.endsWith('/')) {
        dirOnly = true;
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      // A line that cannot be compiled drops that line only: reading a
      // `.gitignore` never fails the panel or `@`.
      RegExp? re;
      try {
        re = _compile(line);
      } on Object {
        re = null;
      }
      if (re != null) rules.add(_Rule(re, negate: negate, dirOnly: dirOnly));
    }
    if (rules.isNotEmpty) _sets.add((base, rules));
  }

  /// Whether [path] (relative to the root, `/` separators) is ignored by the
  /// rules added so far. A folder above an ignored folder is the caller's
  /// to check: git never looks inside an ignored folder.
  bool ignores(String path, {required bool dir}) {
    bool? result;
    for (final (base, rules) in _sets) {
      final String rel;
      if (base.isEmpty) {
        rel = path;
      } else if (path.startsWith('$base/')) {
        rel = path.substring(base.length + 1);
      } else {
        continue;
      }
      for (final r in rules) {
        if (r.dirOnly && !dir) continue;
        if (r.re.hasMatch(rel)) result = !r.negate;
      }
    }
    return result ?? false;
  }

  static RegExp? _compile(String pattern) {
    var pat = pattern;
    final anchored = pat.contains('/');
    if (pat.startsWith('/')) pat = pat.substring(1);
    final b = StringBuffer('^');
    if (!anchored) b.write('(?:.*/)?');
    for (var i = 0; i < pat.length; i++) {
      final c = pat[i];
      if (c == '*') {
        final twin = i + 1 < pat.length && pat[i + 1] == '*';
        final atStart = i == 0 || pat[i - 1] == '/';
        final atEnd = i + 2 >= pat.length || pat[i + 2] == '/';
        if (twin && atStart && atEnd) {
          if (i + 2 >= pat.length) {
            b.write('.*');
            i += 1;
          } else {
            b.write('(?:.*/)?');
            i += 2;
          }
        } else {
          b.write('[^/]*');
          if (twin) i += 1;
        }
      } else if (c == '?') {
        b.write('[^/]');
      } else if (c == '[') {
        // The search starts after the first member (`[]a]` takes its first
        // `]` as one); a `[` that ends the pattern is no class (and an
        // `indexOf` past the end is a RangeError).
        final close = i + 2 > pat.length ? -1 : pat.indexOf(']', i + 2);
        if (close < 0) {
          b.write(r'\[');
          continue;
        }
        var body = pat.substring(i + 1, close);
        if (body.startsWith('!')) body = '^${body.substring(1)}';
        b.write('[${body.replaceAll(r'\', r'\\')}]');
        i = close;
      } else if (c == r'\' && i + 1 < pat.length) {
        b.write(RegExp.escape(pat[i + 1]));
        i += 1;
      } else {
        b.write(RegExp.escape(c));
      }
    }
    b.write(r'$');
    try {
      return RegExp(b.toString());
    } on FormatException {
      return null;
    }
  }
}

/// One entry of a project folder (§4.4 Files).
final class AiDirEntry {
  const AiDirEntry(this.path, {required this.dir, required this.ignored});

  /// Relative to the project root, `/` separators.
  final String path;
  final bool dir;

  /// `.gitignore` drops it (or a folder above it).
  final bool ignored;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  @override
  String toString() => '…';
}

/// The most files `@` indexes in one project (D16).
const int kAiIndexMax = 20000;

String _rel(String root, String path) =>
    p.relative(path, from: root).replaceAll(r'\', '/');

void _addIgnore(AiGitIgnore rules, String root, String dirAbs) {
  final file = File(p.join(dirAbs, '.gitignore'));
  try {
    if (file.existsSync()) {
      final base = dirAbs == root ? '' : _rel(root, dirAbs);
      // Not valid UTF-8 (a Latin-1 comment): the bad bytes become U+FFFD,
      // the rules around them still count.
      rules.add(
        base,
        utf8.decode(file.readAsBytesSync(), allowMalformed: true),
      );
    }
  } on Object {
    // Unreadable: nothing ignored by it.
  }
}

/// D18, B12: folder [args.$2] of project [args.$1] ('' is the root) — folders
/// first, then files, each by name; never `.git`; each marked ignored when a
/// `.gitignore` says so or a folder above it is ignored. Blocking: run it
/// off the UI isolate (`aiOffThreadProvider`).
List<AiDirEntry> aiListDir((String, String) args) {
  final (root, dir) = args;
  final rules = AiGitIgnore();
  _addIgnore(rules, root, root);
  var above = false;
  if (dir.isNotEmpty) {
    final parts = dir.split('/');
    for (var i = 0; i < parts.length; i++) {
      final rel = parts.take(i + 1).join('/');
      if (rules.ignores(rel, dir: true)) above = true;
      _addIgnore(rules, root, p.join(root, rel));
    }
  }
  final folder = Directory(dir.isEmpty ? root : p.join(root, dir));
  final dirs = <AiDirEntry>[];
  final files = <AiDirEntry>[];
  try {
    for (final e in folder.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (name == '.git') continue;
      final rel = dir.isEmpty ? name : '$dir/$name';
      final isDir = e is Directory;
      final entry = AiDirEntry(
        rel,
        dir: isDir,
        ignored: above || rules.ignores(rel, dir: isDir),
      );
      (isDir ? dirs : files).add(entry);
    }
  } on FileSystemException {
    return const [];
  }
  int byName(AiDirEntry a, AiDirEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return [...dirs..sort(byName), ...files..sort(byName)];
}

/// D16, B12: every file of project [root] that the `.gitignore` files keep
/// (relative, `/` separators, sorted), at most [kAiIndexMax]; ignored
/// folders and `.git` are never entered, links never followed. Blocking: run
/// it off the UI isolate.
List<String> aiIndexProject(String root) {
  final rules = AiGitIgnore();
  final out = <String>[];
  final queue = <String>[''];
  while (queue.isNotEmpty && out.length < kAiIndexMax) {
    final dir = queue.removeAt(0);
    final abs = dir.isEmpty ? root : p.join(root, dir);
    _addIgnore(rules, root, abs);
    final List<FileSystemEntity> list;
    try {
      list = Directory(abs).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final e in list) {
      final name = p.basename(e.path);
      if (name == '.git') continue;
      final rel = dir.isEmpty ? name : '$dir/$name';
      if (e is Directory) {
        if (!rules.ignores(rel, dir: true)) queue.add(rel);
      } else if (e is File && !rules.ignores(rel, dir: false)) {
        out.add(rel);
        if (out.length >= kAiIndexMax) break;
      }
    }
  }
  return out..sort();
}
