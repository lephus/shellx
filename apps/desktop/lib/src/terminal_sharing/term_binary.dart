import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;

import 'sharing_paths.dart';

/// Sets a file's mode (macOS); injected in tests.
typedef Chmod = Future<void> Function(String mode, String path);

Future<void> _systemChmod(String mode, String path) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod $mode failed', path);
  }
}

/// Copies `shellx-term` from the app into the `bin` folder the blocks call,
/// keeps it current, and removes it (spec §10.4, §10.5).
///
/// File operations use the host's path rules; [SharingPaths.windows] only
/// selects the Windows behaviour (rename a locked binary).
final class TermBinaryInstaller {
  TermBinaryInstaller(this.paths, {Chmod chmod = _systemChmod})
    : _chmod = chmod;

  final SharingPaths paths;
  final Chmod _chmod;

  static final RegExp _old = RegExp(r'^shellx-term\.old-(\d+)\.exe$');

  Future<bool> bundledExists() => File(paths.bundledBinary).exists();

  Future<bool> installedExists() => File(paths.binary).exists();

  /// True when the copy in `bin` has the same bytes as the app's (same
  /// version and same hash).
  Future<bool> isCurrent() async {
    final installed = File(paths.binary);
    final bundled = File(paths.bundledBinary);
    if (!await installed.exists() || !await bundled.exists()) return false;
    if (await installed.length() != await bundled.length()) return false;
    return listEquals(
      await installed.readAsBytes(),
      await bundled.readAsBytes(),
    );
  }

  /// Copies the app's binary into `bin`. macOS: through a temporary file
  /// renamed over the old one (open terminals keep the old inode).
  /// Windows: a running `shellx-term.exe` cannot be replaced, so the old
  /// one is renamed to `shellx-term.old-<n>.exe` first ([cleanupOld]
  /// deletes it once nothing runs it). Throws when the app has no binary.
  Future<void> install() async {
    final bundled = File(paths.bundledBinary);
    if (!await bundled.exists()) {
      throw FileSystemException(
        'shellx-term is missing from the app',
        bundled.path,
      );
    }
    final bin = Directory(paths.binDir);
    await bin.create(recursive: true);
    final temp = File('${paths.binary}.tmp-$pid');
    await bundled.copy(temp.path);
    try {
      if (!paths.windows) await _chmod('755', temp.path);
      if (paths.windows && await File(paths.binary).exists()) {
        await File(paths.binary).rename(await _freeOldName());
      }
      await temp.rename(paths.binary);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// Deletes the `bin` folder. A file Windows keeps locked (a terminal
  /// still runs it) is renamed to `.old-<n>` and left for the next start.
  /// True when the folder is gone.
  Future<bool> remove() async {
    final bin = Directory(paths.binDir);
    if (!await bin.exists()) return true;
    try {
      await bin.delete(recursive: true);
      return true;
    } on FileSystemException {
      // Windows: a running exe. Delete what can go, keep the rest.
    }
    final binary = File(paths.binary);
    if (await binary.exists()) {
      try {
        await binary.rename(await _freeOldName());
      } on FileSystemException {
        // Left in place; the next start tries again.
      }
    }
    await cleanupOld();
    try {
      await bin.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Deletes `shellx-term.old-*.exe` files nothing holds open any more.
  Future<void> cleanupOld() async {
    final bin = Directory(paths.binDir);
    if (!await bin.exists()) return;
    await for (final entity in bin.list()) {
      final name = p.basename(entity.path);
      if (entity is! File || !_old.hasMatch(name)) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // Still running in some terminal.
      }
    }
  }

  Future<String> _freeOldName() async {
    for (var n = 1; ; n++) {
      final candidate = p.join(paths.binDir, 'shellx-term.old-$n.exe');
      if (!await File(candidate).exists()) return candidate;
    }
  }
}
