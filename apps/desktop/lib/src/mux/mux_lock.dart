import 'dart:io';

import 'mux_paths.dart';

/// `mux/mux.lock`, exclusive, for the host's lifetime (A5b D16): whoever
/// holds it is the one process that serves the mux address. The OS releases
/// it when the process dies. The directory is made first (0700 on macOS: the
/// socket and the endpoint live there).
final class MuxLock {
  MuxLock._(this._handle);
  final RandomAccessFile _handle;

  /// Throws [StateError] when another process holds the lock.
  static Future<MuxLock> acquire(MuxPaths paths) async {
    await Directory(paths.muxDirectory).create(recursive: true);
    if (!paths.windows) {
      final r = await Process.run('/bin/chmod', ['700', paths.muxDirectory]);
      if (r.exitCode != 0) {
        throw FileSystemException('chmod 700 failed', paths.muxDirectory);
      }
    }
    final handle = await File(paths.lock).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      throw StateError('another ShellX host holds the mux lock');
    }
    return MuxLock._(handle);
  }

  /// Whether no host holds the lock right now (D16: no daemon). The lock is
  /// taken and released at once; a daemon that starts in between simply
  /// finds it held. False when the directory cannot be used.
  static Future<bool> isFree(MuxPaths paths) async {
    try {
      final lock = await acquire(paths);
      await lock.release();
      return true;
    } on StateError {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> release() async {
    try {
      await _handle.unlock();
    } finally {
      await _handle.close();
    }
  }
}
