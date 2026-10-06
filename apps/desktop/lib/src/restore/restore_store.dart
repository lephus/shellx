import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'restore_snapshot.dart';
import 'scrollback_codec.dart';

/// A larger `layout.json` is not one we wrote (D11). The largest layout
/// capture can produce (32 panes × a 4096-character cwd of 4-byte UTF-8,
/// plus names and ids) stays well under it.
const int kRestoreMaxLayoutBytes = 1048576;

final class RestoreLoad {
  const RestoreLoad({this.snapshot, this.corrupt = false});
  final RestoreSnapshot? snapshot;

  /// The file existed but was not ours (D11); it is now `layout.json.bak`.
  final bool corrupt;
}

/// What restore persistence needs from the disk (D2, D3).
abstract interface class RestoreFiles {
  /// False when scrollback must never be written (§5: permissions not set).
  Future<bool> prepare();
  Future<RestoreLoad> loadLayout();

  /// True only when the layout reached the disk; a failed write (disk full)
  /// keeps the previous file, and the caller retries next time (§5).
  Future<bool> writeLayout(RestoreSnapshot snapshot);

  /// False when the files could not be written (disk full): the caller
  /// keeps them pending. True too when scrollback is never written here
  /// (permissions, §5): retrying would not help.
  Future<bool> writeScrollbacks(Map<String, String> textByKey);
  Future<String?> readScrollback(String key);
  Future<DateTime?> scrollbackSavedAt(String key);
  Future<void> deleteScrollback(String key);
  Future<void> deleteAllScrollback();
  Future<bool> hasScrollback();
  Future<void> removeOrphans(Set<String> keep);
}

/// Stores nothing: the default until the app wires a [RestoreStore].
/// Writes are accepted and dropped (so callers never retry them).
final class NullRestoreFiles implements RestoreFiles {
  const NullRestoreFiles();

  @override
  Future<bool> prepare() async => false;
  @override
  Future<RestoreLoad> loadLayout() async => const RestoreLoad();
  @override
  Future<bool> writeLayout(RestoreSnapshot snapshot) async => true;
  @override
  Future<bool> writeScrollbacks(Map<String, String> textByKey) async => true;
  @override
  Future<String?> readScrollback(String key) async => null;
  @override
  Future<DateTime?> scrollbackSavedAt(String key) async => null;
  @override
  Future<void> deleteScrollback(String key) async {}
  @override
  Future<void> deleteAllScrollback() async {}
  @override
  Future<bool> hasScrollback() async => false;
  @override
  Future<void> removeOrphans(Set<String> keep) async {}
}

/// A layout write waiting in the queue; a newer write replaces its
/// snapshot instead of queueing another (D25). The newer snapshot is thus
/// written at the older write's place in the queue, overtaking any
/// scrollback operations queued in between. That is harmless: those
/// touch other files. Only [RestoreStore.loadLayout], which reads this
/// file, is fenced: it closes the slot, so a later write queues anew.
final class _LayoutSlot {
  _LayoutSlot(this.snapshot);
  RestoreSnapshot snapshot;
  late final Future<bool> done;
}

/// The files of A5a (D2, D3): `layout.json` and `scrollback/<key>.txt`.
/// Every operation runs through one serial queue (D25), so a delete issued
/// after a write always wins. Logs carry error types only — never paths
/// or contents.
final class RestoreStore implements RestoreFiles {
  RestoreStore(
    this.directory, {
    bool? posix,
    Future<void> Function(String path)? excludeFromBackup,
    Future<bool> Function(String mode, List<String> paths)? chmod,
    Future<String> Function(File file)? readLayout,
    Duration excludeTimeout = const Duration(seconds: 5),
    void Function(String message)? log,
  }) : _readLayout = readLayout ?? ((file) => file.readAsString()),
       _excludeTimeout = excludeTimeout,
       _posix = posix ?? !Platform.isWindows,
       _exclude = excludeFromBackup,
       _chmod = chmod ?? _systemChmod,
       _log = log ?? ((_) {});

  final Directory directory;
  final bool _posix;
  final Future<void> Function(String path)? _exclude;
  final Future<bool> Function(String mode, List<String> paths) _chmod;
  final void Function(String message) _log;
  final Future<String> Function(File file) _readLayout;
  final Duration _excludeTimeout;
  final _random = Random.secure();
  Future<void> _tail = Future.value();
  bool _scrollbackAllowed = true;
  _LayoutSlot? _pendingLayout;
  bool _layoutChmodLogged = false;

  String get _sep => Platform.pathSeparator;
  String get _layout => '${directory.path}${_sep}layout.json';
  Directory get _scrollDir => Directory('${directory.path}${_sep}scrollback');
  String _scrollPath(String key) => '${_scrollDir.path}$_sep$key.txt';

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// Creates the directories (0700) and asks the OS to keep them out of
  /// backups. False when the permissions could not be set: scrollback is
  /// then never written (the layout still is).
  @override
  Future<bool> prepare() => _serial(() async {
    try {
      await _scrollDir.create(recursive: true);
    } on Object catch (error) {
      _log('restore: directory not created (${error.runtimeType})');
      _scrollbackAllowed = false;
      return false;
    }
    if (_posix) {
      final ok = await _chmod('700', [directory.path, _scrollDir.path]);
      _scrollbackAllowed = ok;
      if (!ok) _log('restore: permissions not set; scrollback disabled');
    }
    try {
      await _exclude?.call(directory.path).timeout(_excludeTimeout);
    } on Object catch (error) {
      _log('restore: backup exclusion failed (${error.runtimeType})');
    }
    return _scrollbackAllowed;
  });

  @override
  Future<RestoreLoad> loadLayout() {
    // A write queued after this load must not merge into one before it.
    _pendingLayout = null;
    return _serial(() async {
      final file = File(_layout);
      String? reason;
      try {
        if (!await file.exists()) return const RestoreLoad();
        String text;
        try {
          text = await _readCapped(file);
        } on FileSystemException {
          // A transient lock (another process, antivirus): one retry.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          text = await _readCapped(file);
        }
        final snapshot = RestoreSnapshot.tryParse(text);
        if (snapshot != null) return RestoreLoad(snapshot: snapshot);
        reason = 'FormatException';
      } on _Oversized {
        reason = 'oversized';
      } on Object catch (error) {
        reason = '${error.runtimeType}';
      }
      _log('restore: layout unreadable ($reason)');
      try {
        await file.rename('$_layout.bak');
      } on Object catch (error) {
        _log('restore: keeping .bak failed (${error.runtimeType})');
      }
      return const RestoreLoad(corrupt: true);
    });
  }

  /// The layout's text; [_Oversized] past [kRestoreMaxLayoutBytes].
  Future<String> _readCapped(File file) async {
    if (await file.length() > kRestoreMaxLayoutBytes) throw const _Oversized();
    return _readLayout(file);
  }

  @override
  Future<bool> writeLayout(RestoreSnapshot snapshot) {
    final pending = _pendingLayout;
    if (pending != null) {
      pending.snapshot = snapshot;
      return pending.done;
    }
    final slot = _pendingLayout = _LayoutSlot(snapshot);
    slot.done = _serial(() {
      if (identical(_pendingLayout, slot)) _pendingLayout = null;
      return _atomic({_layout: slot.snapshot.encode()}, private: false);
    });
    return slot.done;
  }

  @override
  Future<bool> writeScrollbacks(Map<String, String> textByKey) =>
      _serial(() async {
        if (!_scrollbackAllowed) return true;
        return _atomic({
          for (final MapEntry(:key, :value) in textByKey.entries)
            if (isPaneKey(key)) _scrollPath(key): value,
        }, private: true);
      });

  /// Sanitized (D6); null when missing, oversized or not UTF-8.
  @override
  Future<String?> readScrollback(String key) => _serial(() async {
    if (!isPaneKey(key)) return null;
    final file = File(_scrollPath(key));
    try {
      if (!await file.exists()) return null;
      if (await file.length() > kRestoreMaxFileBytes) return null;
      final text = utf8.decode(await file.readAsBytes());
      return sanitizeRestored(text);
    } on Object {
      return null;
    }
  });

  @override
  Future<DateTime?> scrollbackSavedAt(String key) => _serial(() async {
    if (!isPaneKey(key)) return null;
    final file = File(_scrollPath(key));
    try {
      return await file.exists() ? await file.lastModified() : null;
    } on FileSystemException {
      return null;
    }
  });

  @override
  Future<void> deleteScrollback(String key) => _serial(() async {
    if (!isPaneKey(key)) return;
    await _deleteQuietly(File(_scrollPath(key)));
  });

  @override
  Future<void> deleteAllScrollback() => _serial(() async {
    for (final file in await _files(_scrollDir)) {
      await _deleteQuietly(file);
    }
  });

  @override
  Future<bool> hasScrollback() => _serial(() async {
    return (await _files(_scrollDir)).any((f) => f.path.endsWith('.txt'));
  });

  /// D15: files of panes no longer in the layout, and stray temp files.
  @override
  Future<void> removeOrphans(Set<String> keep) => _serial(() async {
    for (final file in await _files(directory)) {
      if (file.uri.pathSegments.last.contains('.tmp-')) {
        await _deleteQuietly(file);
      }
    }
    for (final file in await _files(_scrollDir)) {
      final name = file.uri.pathSegments.last;
      final key = name.endsWith('.txt')
          ? name.substring(0, name.length - 4)
          : '';
      if (!keep.contains(key)) await _deleteQuietly(file);
    }
  });

  /// The plain files of [dir]; empty when it cannot be listed.
  Future<List<File>> _files(Directory dir) async {
    try {
      if (!await dir.exists()) return const [];
      return await dir.list().where((e) => e is File).cast<File>().toList();
    } on FileSystemException catch (error) {
      _log('restore: listing failed (${error.runtimeType})');
      return const [];
    }
  }

  /// Temp files first, one chmod for all of them before any content goes
  /// in (D2), then content, then rename each over its target. True only
  /// when every file was written; on failure the targets keep their
  /// previous content (§5). A [private] file (scrollback) is never written
  /// without 0600; the layout is written anyway (§5), logged once.
  Future<bool> _atomic(
    Map<String, String> contents, {
    required bool private,
  }) async {
    if (contents.isEmpty) return true;
    final temps = <String, File>{
      for (final path in contents.keys)
        path: File(
          '$path.tmp-$pid-${_random.nextInt(1 << 32).toRadixString(16)}',
        ),
    };
    try {
      for (final temp in temps.values) {
        await temp.writeAsBytes(const [], flush: true);
      }
      if (_posix &&
          !await _chmod('600', [for (final t in temps.values) t.path])) {
        if (private) throw const FileSystemException('chmod 600 failed');
        if (!_layoutChmodLogged) {
          _layoutChmodLogged = true;
          _log('restore: layout permissions not set; writing anyway');
        }
      }
      for (final MapEntry(:key, :value) in temps.entries) {
        await value.writeAsString(contents[key]!, flush: true);
        await value.rename(key);
      }
      return true;
    } on Object catch (error) {
      _log('restore: write failed (${error.runtimeType})');
      for (final temp in temps.values) {
        await _deleteQuietly(temp);
      }
      return false;
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  static Future<bool> _systemChmod(String mode, List<String> paths) async {
    try {
      final result = await Process.run('/bin/chmod', [mode, ...paths]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}

final class _Oversized implements Exception {
  const _Oversized();
}
