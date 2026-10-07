import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'config_problem.dart';
import 'config_syntax.dart';

/// D5: a bigger file is not read.
const int kConfigMaxBytes = 256 * 1024;

/// D6: `config-file` nesting below the root.
const int kConfigMaxIncludeDepth = 4;

/// What the watcher compares (D9).
@immutable
final class FileStamp {
  const FileStamp({
    required this.exists,
    required this.size,
    required this.modifiedMs,
  });
  const FileStamp.missing() : exists = false, size = 0, modifiedMs = 0;

  final bool exists;
  final int size;
  final int modifiedMs;

  @override
  bool operator ==(Object other) =>
      other is FileStamp &&
      other.exists == exists &&
      other.size == size &&
      other.modifiedMs == modifiedMs;

  @override
  int get hashCode => Object.hash(exists, size, modifiedMs);
}

final class ConfigTooLarge implements Exception {
  const ConfigTooLarge();
}

/// The file system as the config code sees it (tests use a memory one).
abstract interface class ConfigFs {
  /// Null when [path] does not exist. Throws [ConfigTooLarge] above
  /// [kConfigMaxBytes] and [FileSystemException] when it can't be read.
  Future<Uint8List?> read(String path);

  /// Never throws: a path that can't be stat'ed is missing.
  Future<FileStamp> stamp(String path);
}

final class IoConfigFs implements ConfigFs {
  const IoConfigFs();

  @override
  Future<Uint8List?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > kConfigMaxBytes) throw const ConfigTooLarge();
    return file.readAsBytes();
  }

  @override
  Future<FileStamp> stamp(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) {
        return const FileStamp.missing();
      }
      return FileStamp(
        exists: true,
        size: stat.size,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      );
    } on FileSystemException {
      return const FileStamp.missing();
    }
  }
}

/// A root file and its includes.
final class ConfigChain {
  ConfigChain(this.entries, this.files, {required this.readable});

  /// Every entry except `config-file`, in effective order (D6).
  final List<ConfigEntry> entries;

  /// Every path looked at, existing or not (the watcher's list, D9).
  final List<String> files;

  /// False when the root exists but could not be read (D8).
  final bool readable;
}

p.Context _context(bool windows) => windows ? p.windows : p.posix;

/// D6: `~` / `~/…` from [home]; relative to [baseDir]; normalised.
String expandConfigPath(
  String value, {
  required String baseDir,
  required String home,
  bool windows = false,
}) {
  final ctx = _context(windows);
  var path = value.trim();
  if (path == '~') {
    path = home;
  } else if (path.startsWith('~/') || (windows && path.startsWith(r'~\'))) {
    path = ctx.join(home, path.substring(2));
  }
  return ctx.normalize(ctx.isAbsolute(path) ? path : ctx.join(baseDir, path));
}

/// Reads [path] and its `config-file` includes (D5, D6). [quiet] is the
/// Ghostty layer (D4): its syntax and include problems are not ShellX's to
/// report, and a read problem is only a warning. [keep] filters keys.
Future<ConfigChain> loadConfigChain(
  String path, {
  required ConfigFs fs,
  required String home,
  required List<ConfigProblem> problems,
  bool windows = false,
  bool quiet = false,
  bool Function(String key)? keep,
}) async {
  final entries = <ConfigEntry>[];
  final files = <String>[];
  var readable = true;
  final ctx = _context(windows);
  final readSeverity = quiet ? ConfigSeverity.warning : ConfigSeverity.error;

  void fileProblem(String file, ConfigProblemCode code, int depth) {
    problems.add(
      ConfigProblem(file: file, line: 0, severity: readSeverity, code: code),
    );
    if (depth == 0) readable = false;
  }

  Future<void> visit(
    String file,
    int depth,
    List<String> stack, {
    ConfigEntry? from,
    bool optional = false,
  }) async {
    files.add(file);
    final Uint8List? bytes;
    try {
      bytes = await fs.read(file);
    } on ConfigTooLarge {
      return fileProblem(file, ConfigProblemCode.tooLarge, depth);
    } on FileSystemException {
      return fileProblem(file, ConfigProblemCode.unreadable, depth);
    }
    if (bytes == null) {
      if (from != null && !optional && !quiet) {
        problems.add(
          ConfigProblem(
            file: from.file,
            line: from.line,
            severity: ConfigSeverity.warning,
            code: ConfigProblemCode.includeMissing,
            key: 'config-file',
            value: from.value,
          ),
        );
      }
      return;
    }
    final String text;
    try {
      text = decodeConfigBytes(bytes);
    } on FormatException {
      return fileProblem(file, ConfigProblemCode.notUtf8, depth);
    }
    final syntax = quiet ? <ConfigProblem>[] : problems;
    final own = parseConfigText(text, file: file, problems: syntax);
    final includes = <ConfigEntry>[];
    for (final entry in own) {
      if (entry.key == 'config-file') {
        if (entry.value.isNotEmpty) includes.add(entry);
      } else if (keep == null || keep(entry.key)) {
        entries.add(entry);
      }
    }
    for (final include in includes) {
      final optionalInclude = include.value.startsWith('?');
      final target = expandConfigPath(
        optionalInclude ? include.value.substring(1) : include.value,
        baseDir: ctx.dirname(file),
        home: home,
        windows: windows,
      );
      ConfigProblemCode? refused;
      if (stack.contains(target)) {
        refused = ConfigProblemCode.includeCycle;
      } else if (depth + 1 > kConfigMaxIncludeDepth) {
        refused = ConfigProblemCode.includeDepth;
      }
      if (refused != null) {
        if (!quiet) {
          problems.add(
            ConfigProblem(
              file: include.file,
              line: include.line,
              severity: ConfigSeverity.warning,
              code: refused,
              key: 'config-file',
              value: include.value,
            ),
          );
        }
        continue;
      }
      await visit(
        target,
        depth + 1,
        [...stack, target],
        from: include,
        optional: optionalInclude,
      );
    }
  }

  await visit(path, 0, [path]);
  return ConfigChain(entries, files, readable: readable);
}
