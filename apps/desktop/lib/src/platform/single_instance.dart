import 'dart:async';
import 'dart:io';

/// "Only one agent at a time" (spec §8.2): an exclusive lock on
/// `<app support>/shellx.lock`, held for the life of the process and released
/// by the OS even if the process crashes.
final class SingleInstanceLock {
  SingleInstanceLock(this.directory);

  static const String lockFileName = 'shellx.lock';
  static const String activationFileName = 'activate.signal';

  final Directory directory;
  RandomAccessFile? _handle;

  String get lockPath =>
      '${directory.path}${Platform.pathSeparator}$lockFileName';
  String get _activationPath =>
      '${directory.path}${Platform.pathSeparator}$activationFileName';

  /// True if this process now owns the lock.
  Future<bool> acquire() async {
    await directory.create(recursive: true);
    final handle = await File(lockPath).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      return false;
    }
    _handle = handle;
    return true;
  }

  Future<void> release() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    await handle.unlock();
    await handle.close();
  }

  /// Called by a second launch just before it exits.
  Future<void> signalRunningInstance() => File(
    _activationPath,
  ).writeAsString('${DateTime.now().microsecondsSinceEpoch}', flush: true);

  /// Fires when a second launch called [signalRunningInstance].
  Stream<void> activationRequests() => directory
      .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
      .where((event) => event.path.endsWith(activationFileName))
      .map((_) {});
}
