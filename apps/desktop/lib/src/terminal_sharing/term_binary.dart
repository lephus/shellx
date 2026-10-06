import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;

import 'sharing_paths.dart';

/// Sets a file's mode (macOS); injected in tests.
typedef Chmod = Future<void> Function(String mode, String path);

/// `/bin/chmod`; throws when it fails.
Future<void> systemChmod(String mode, String path) async {
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
  TermBinaryInstaller(this.paths, {Chmod chmod = systemChmod}) : _chmod = chmod;

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
    await copyBinary(
      from: bundled.path,
      to: paths.binary,
      windows: paths.windows,
      chmod: _chmod,
    );
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

  Future<String> _freeOldName() => freeOldName(paths.binary);
}

/// Copies [from] to [to] (A7 D7 shares it with the command-line copy):
/// through a temporary file beside [to], renamed over it, so a running
/// copy keeps its old inode (macOS, mode 755). Windows: a running `.exe`
/// cannot be replaced, so the old one is renamed to `<name>.old-<n>.exe`
/// first ([freeOldName]).
Future<void> copyBinary({
  required String from,
  required String to,
  required bool windows,
  required Chmod chmod,
}) async {
  await File(to).parent.create(recursive: true);
  final temp = File('$to.tmp-$pid');
  await File(from).copy(temp.path);
  try {
    if (!windows) await chmod('755', temp.path);
    if (windows && await File(to).exists()) {
      await File(to).rename(await freeOldName(to));
    }
    await temp.rename(to);
  } catch (_) {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}

/// `<dir>/<name>.old-<n>.exe` for [binary] `<dir>/<name>.exe`, with the
/// first `n` not taken.
Future<String> freeOldName(String binary) async {
  final stem = p.basenameWithoutExtension(binary);
  for (var n = 1; ; n++) {
    final candidate = p.join(p.dirname(binary), '$stem.old-$n.exe');
    if (!await File(candidate).exists()) return candidate;
  }
}
