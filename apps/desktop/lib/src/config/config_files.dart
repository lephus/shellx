import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'config_problem.dart';
import 'config_syntax.dart';

/// D5: a bigger file is not read.
const int kConfigMaxBytes = 256 * 1024;

/// D6: `config-file` nesting below the root.
const int kConfigMaxIncludeDepth = 4;

/// Files in one chain (the root included); includes beyond are refused.
const int kConfigMaxFiles = 64;

/// Problems kept per chain; a summary problem follows the cut.
const int kConfigMaxProblems = 100;

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
    // Device namespaces and NUL never name a config file; refuse before
    // touching the file system (a device path can block).
    if (path.contains('\x00') ||
        path.startsWith(r'\\.\') ||
        path.startsWith(r'\\?\') ||
        path.startsWith('//./') ||
        path.startsWith('//?/')) {
      throw FileSystemException('not a regular file', path);
    }
    final stat = await FileStat.stat(path); // follows symlinks
    if (stat.type == FileSystemEntityType.notFound) {
      return _missingOrOddNode(path);
    }
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('not a regular file', path);
    }
    // A character device (/dev/zero) also reports "file" and a length of
    // 0: never trust the size, bound the read itself.
    final raf = await File(path).open();
    try {
      final builder = BytesBuilder(copy: false);
      var total = 0;
      while (total <= kConfigMaxBytes) {
        final chunk = await raf.read(kConfigMaxBytes + 1 - total);
        if (chunk.isEmpty) break;
        builder.add(chunk);
        total += chunk.length;
      }
      if (total > kConfigMaxBytes) throw const ConfigTooLarge();
      return builder.takeBytes();
    } finally {
      await raf.close();
    }
  }

  /// `stat` reports a missing path and some device nodes (macOS
  /// `/dev/zero`) alike; opening tells them apart. ENOENT / ENOTDIR (or the
  /// Windows 2 / 3) is missing; an open that works is not a regular file.
  Future<Uint8List?> _missingOrOddNode(String path) async {
    try {
      await (await File(path).open()).close();
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      if (code == 2 || code == 3 || code == 20) return null;
      rethrow;
    }
    throw FileSystemException('not a regular file', path);
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
  final tilde =
      path == '~' ||
      path.startsWith('~/') ||
      (windows && path.startsWith(r'~\'));
  if (tilde && home.isEmpty) {
    throw ArgumentError.value(home, 'home', 'is empty');
  }
  if (path == '~') {
    path = home;
  } else if (tilde) {
    path = ctx.join(home, path.substring(2));
  }
  return ctx.normalize(ctx.isAbsolute(path) ? path : ctx.join(baseDir, path));
}

/// Reads [path] and its `config-file` includes (D5, D6). [quiet] is the
/// Ghostty layer (D4): its syntax and include problems are not ShellX's to
/// report, and a read problem is only a warning. [keep] filters keys.
///
/// Only a bad root keeps the previous configuration (`readable` false); a
/// bad include is a warning at the including line and is skipped. A file
/// already loaded is skipped, at most [kConfigMaxFiles] files are looked
/// at, and at most [kConfigMaxProblems] problems are kept (D8). Paths are
/// compared normalised, ignoring case when [caseInsensitive] (default: on
/// Windows; callers pass true on macOS).
Future<ConfigChain> loadConfigChain(
  String path, {
  required ConfigFs fs,
  required String home,
  required List<ConfigProblem> problems,
  bool windows = false,
  bool quiet = false,
  bool Function(String key)? keep,
  bool? caseInsensitive,
}) async {
  final entries = <ConfigEntry>[];
  final files = <String>[];
  final loaded = <String>{};
  var readable = true;
  var limitReported = false;
  final ctx = _context(windows);
  final foldCase = caseInsensitive ?? windows;
  final firstProblem = problems.length;

  String identity(String file) {
    final n = ctx.normalize(windows ? file.replaceAll('/', r'\') : file);
    return foldCase ? n.toLowerCase() : n;
  }

  void fileProblem(String file, ConfigProblemCode code, ConfigEntry? from) {
    if (from == null) {
      problems.add(
        ConfigProblem(
          file: file,
          line: 0,
          severity: quiet ? ConfigSeverity.warning : ConfigSeverity.error,
          code: code,
        ),
      );
      readable = false;
    } else {
      problems.add(
        ConfigProblem(
          file: from.file,
          line: from.line,
          severity: ConfigSeverity.warning,
          code: code,
          key: 'config-file',
          value: from.value,
        ),
      );
    }
  }

  Future<void> visit(
    String file,
    int depth,
    List<String> stack, {
    ConfigEntry? from,
    bool optional = false,
  }) async {
    files.add(file);
    loaded.add(identity(file));
    final Uint8List? bytes;
    try {
      bytes = await fs.read(file);
    } on ConfigTooLarge {
      return fileProblem(file, ConfigProblemCode.tooLarge, from);
    } on FileSystemException {
      return fileProblem(file, ConfigProblemCode.unreadable, from);
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
      return fileProblem(file, ConfigProblemCode.notUtf8, from);
    }
    final syntax = quiet ? <ConfigProblem>[] : problems;
    final own = parseConfigText(text, file: file, problems: syntax);
    final includes = <ConfigEntry>[];
    for (final entry in own) {
      if (entry.key == 'config-file') {
        // D5: an empty value resets the list collected so far.
        if (entry.value.isEmpty) {
          includes.clear();
        } else {
          includes.add(entry);
        }
      } else if (keep == null || keep(entry.key)) {
        entries.add(entry);
      }
    }
    for (final include in includes) {
      final optionalInclude = include.value.startsWith('?');
      final String target;
      try {
        final raw = optionalInclude
            ? include.value.substring(1)
            : include.value;
        if (raw.contains('\x00')) throw const FormatException('NUL in path');
        target = expandConfigPath(
          raw,
          baseDir: ctx.dirname(file),
          home: home,
          windows: windows,
        );
      } on FormatException {
        if (!quiet) fileProblem(file, ConfigProblemCode.unreadable, include);
        continue;
      } on ArgumentError {
        if (!quiet) fileProblem(file, ConfigProblemCode.unreadable, include);
        continue;
      }
      final id = identity(target);
      ConfigProblemCode? refused;
      if (stack.any((s) => identity(s) == id)) {
        refused = ConfigProblemCode.includeCycle;
      } else if (loaded.contains(id)) {
        continue; // already loaded through another include: skip silently
      } else if (depth + 1 > kConfigMaxIncludeDepth) {
        refused = ConfigProblemCode.includeDepth;
      } else if (files.length >= kConfigMaxFiles) {
        if (limitReported) continue;
        limitReported = true;
        refused = ConfigProblemCode.includeLimit;
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
  final added = problems.length - firstProblem;
  if (added > kConfigMaxProblems) {
    problems.removeRange(firstProblem + kConfigMaxProblems, problems.length);
    problems.add(
      ConfigProblem(
        file: path,
        line: 0,
        severity: ConfigSeverity.warning,
        code: ConfigProblemCode.problemLimit,
        detail: '$added',
      ),
    );
  }
  return ConfigChain(entries, files, readable: readable);
}
