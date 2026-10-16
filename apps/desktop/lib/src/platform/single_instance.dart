import 'dart:async';
import 'dart:io';

/// "Only one agent at a time" (spec §8.2): an exclusive lock on
/// `<app support>/shellx.lock`, held for the life of the process and released
/// by the OS even if the process crashes.
final class SingleInstanceLock {
  SingleInstanceLock(this.directory);

  static const String lockFileName = 'shellx.lock';
  static const String activationFileName = 'activate.signal';

  /// A5a I1: written by the Windows installer before it replaces the
  /// files, so the running instance quits with a clean, final save.
  static const String quitFileName = 'quit.signal';

  final Directory directory;
  RandomAccessFile? _handle;

  /// One directory watcher for both signal files.
  Stream<FileSystemEvent>? _events;

  String get lockPath =>
      '${directory.path}${Platform.pathSeparator}$lockFileName';
  String get _activationPath =>
      '${directory.path}${Platform.pathSeparator}$activationFileName';
  String get _quitPath =>
      '${directory.path}${Platform.pathSeparator}$quitFileName';

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
    // A5a I1: a quit signal from an earlier run (the installer wrote it
    // and the app was gone, or quit before deleting it) must not quit
    // this one. Done before anything watches the directory.
    try {
      await File(_quitPath).delete();
    } on FileSystemException {
      // None there (the usual case), or not deletable: nothing to do.
    }
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
  }) => _requests(activationFileName, coalesce);

  /// A5a I1: fires when the installer writes [quitFileName] (an update
  /// while ShellX runs); main quits as for the Restart Manager. Only
  /// while the file is there: the macOS watcher may still report the
  /// leftover that [acquire] deleted.
  Stream<void> quitRequests({Duration coalesce = const Duration(seconds: 1)}) =>
      _requests(
        quitFileName,
        coalesce,
        present: () => File(_quitPath).existsSync(),
      );

  Stream<void> _requests(
    String fileName,
    Duration coalesce, {
    bool Function()? present,
  }) => coalesceEvents(
    (_events ??= directory
            .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
            .asBroadcastStream())
        .where(
          (event) =>
              _basename(event.path) == fileName && (present?.call() ?? true),
        )
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
