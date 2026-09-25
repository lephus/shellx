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

  /// Fires once per second launch that called [signalRunningInstance]. The
  /// watcher may report the signal file's creation and its write as two
  /// events, so events within [coalesce] of the last one delivered are
  /// dropped.
  Stream<void> activationRequests({
    Duration coalesce = const Duration(seconds: 1),
  }) => coalesceEvents(
    directory
        .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
        .where((event) => _basename(event.path) == activationFileName)
        .map((_) {}),
    window: coalesce,
  );

  /// The final path component, independent of which separator style the
  /// platform's directory watcher reports (avoids matching e.g.
  /// `notactivate.signal`, which `endsWith` would wrongly accept, and avoids
  /// adding a dependency on `package:path` for this one call).
  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}

/// Passes an event through, then drops every event that arrives within
/// [window] of it (leading-edge throttle).
Stream<void> coalesceEvents(
  Stream<void> events, {
  required Duration window,
  DateTime Function() now = DateTime.now,
}) {
  DateTime? last;
  return events.where((_) {
    final time = now();
    final previous = last;
    if (previous != null && time.difference(previous) < window) return false;
    last = time;
    return true;
  });
}
