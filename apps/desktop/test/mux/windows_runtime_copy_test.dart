import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/mux/windows_runtime_copy.dart';

/// A tiny Windows file system: files by full path (`\` separators), with
/// directories implied; `copies` counts the copy calls.
final class MemoryFileOps implements FileOps {
  final files_ = <String, int>{};
  final dirs = <String>{};
  final inUse = <String>{};
  int copies = 0;
  bool failRename = false;
  void Function()? beforeRename;

  @override
  Future<bool> directoryExists(String path) async =>
      dirs.contains(path) || files_.keys.any((f) => f.startsWith('$path\\'));

  @override
  Future<List<FileEntry>> files(String directory) async => [
    for (final e in files_.entries)
      if (e.key.startsWith('$directory\\')) (path: e.key, length: e.value),
  ];

  @override
  Future<List<String>> subdirectories(String directory) async {
    final found = <String>{};
    for (final p in [...dirs, ...files_.keys]) {
      if (!p.startsWith('$directory\\')) continue;
      final rest = p.substring(directory.length + 1);
      final at = rest.indexOf(r'\');
      if (at != -1 || dirs.contains(p)) {
        found.add('$directory\\${at == -1 ? rest : rest.substring(0, at)}');
      }
    }
    return found.toList();
  }

  @override
  Future<void> createDirectory(String path) async => dirs.add(path);

  @override
  Future<void> copyFile(String from, String to) async {
    copies++;
    files_[to] = files_[from]!;
  }

  @override
  Future<void> renameDirectory(String from, String to) async {
    beforeRename?.call();
    if (failRename || await directoryExists(to)) {
      throw StateError('exists');
    }
    for (final k in files_.keys.toList()) {
      if (k.startsWith('$from\\')) {
        files_['$to${k.substring(from.length)}'] = files_.remove(k)!;
      }
    }
    final moved = dirs
        .where((d) => d == from || d.startsWith('$from\\'))
        .toList();
    dirs
      ..removeAll(moved)
      ..addAll([for (final d in moved) '$to${d.substring(from.length)}']);
    dirs.add(to);
  }

  @override
  Future<void> deleteDirectory(String path) async {
    if (inUse.any((u) => u == path || u.startsWith('$path\\'))) {
      throw StateError('in use');
    }
    files_.removeWhere((k, _) => k.startsWith('$path\\'));
    dirs.removeWhere((d) => d == path || d.startsWith('$path\\'));
  }

  final ages = <String, DateTime>{};
  final now = DateTime(2026, 10, 7, 12);

  @override
  Future<void> deleteFile(String path) async {
    if (inUse.contains(path)) throw StateError('in use');
    files_.remove(path);
  }

  @override
  Future<DateTime?> modified(String path) async =>
      ages[path] ?? (await directoryExists(path) ? now : null);
}

const _install = r'C:\Program Files\ShellX';
const _local = r'C:\Users\me\AppData\Local';
const _target = r'C:\Users\me\AppData\Local\ShellX\mux\1.6.0';

MemoryFileOps installed() => MemoryFileOps()
  ..files_.addAll({
    '$_install\\ShellX.exe': 1000,
    '$_install\\flutter_windows.dll': 2000,
    '$_install\\flutter_pty.dll': 300,
    '$_install\\readme.txt': 5,
    '$_install\\unins000.exe': 9,
    '$_install\\data\\app.so': 400,
    '$_install\\data\\flutter_assets\\fonts\\a.ttf': 50,
  });

void main() {
  test(
    'copies the exe renamed, the dlls and data into <local>\\ShellX\\mux\\<version>',
    () async {
      final ops = installed();
      final exe = await prepareWindowsRuntime(
        installDir: _install,
        localAppData: _local,
        version: '1.6.0',
        ops: ops,
        random: Random(1),
      );
      expect(exe, '$_target\\shellx-mux.exe');
      expect(ops.files_['$_target\\shellx-mux.exe'], 1000);
      expect(ops.files_['$_target\\flutter_windows.dll'], 2000);
      expect(ops.files_['$_target\\flutter_pty.dll'], 300);
      expect(ops.files_['$_target\\data\\app.so'], 400);
      expect(ops.files_['$_target\\data\\flutter_assets\\fonts\\a.ttf'], 50);
      // Only what the daemon runs from.
      expect(ops.files_.containsKey('$_target\\ShellX.exe'), isFalse);
      expect(ops.files_.containsKey('$_target\\readme.txt'), isFalse);
      expect(ops.files_.containsKey('$_target\\unins000.exe'), isFalse);
      // Through a temp dir that is gone.
      expect(ops.files_.keys.where((k) => k.contains('.tmp-')), isEmpty);
      expect(ops.dirs.where((d) => d.contains('.tmp-')), isEmpty);
    },
  );

  test('a second call with the same sizes copies nothing', () async {
    final ops = installed();
    Future<String> run() => prepareWindowsRuntime(
      installDir: _install,
      localAppData: _local,
      version: '1.6.0',
      ops: ops,
    );
    final first = await run();
    final copied = ops.copies;
    expect(copied, 5);
    expect(await run(), first);
    expect(ops.copies, copied);
  });

  test('a file of another size, or a missing one, is copied again', () async {
    final ops = installed();
    Future<void> run() => prepareWindowsRuntime(
      installDir: _install,
      localAppData: _local,
      version: '1.6.0',
      ops: ops,
    );
    await run();
    ops.files_['$_target\\flutter_windows.dll'] = 1; // a half-copied one
    final before = ops.copies;
    await run();
    expect(ops.files_['$_target\\flutter_windows.dll'], 2000);
    expect(ops.copies, before + 5);
  });

  test(
    'a copy that died before the rename leaves no version directory',
    () async {
      final ops = installed()..failRename = true;
      await expectLater(
        prepareWindowsRuntime(
          installDir: _install,
          localAppData: _local,
          version: '1.6.0',
          ops: ops,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await ops.directoryExists(_target), isFalse);
      expect(ops.files_.keys.where((k) => k.contains('.tmp-')), isEmpty);
    },
  );

  test(
    'another start winning the rename is fine when its copy is complete',
    () async {
      final ops = installed();
      ops.beforeRename = () {
        ops.beforeRename = null;
        for (final e in {
          'shellx-mux.exe': 1000,
          'flutter_windows.dll': 2000,
          'flutter_pty.dll': 300,
          'data\\app.so': 400,
          'data\\flutter_assets\\fonts\\a.ttf': 50,
        }.entries) {
          ops.files_['$_target\\${e.key}'] = e.value;
        }
      };
      // The target did not exist at the first check, exists at rename time.
      final exe = await prepareWindowsRuntime(
        installDir: _install,
        localAppData: _local,
        version: '1.6.0',
        ops: ops,
      );
      expect(exe, '$_target\\shellx-mux.exe');
    },
  );

  test(
    'no ShellX.exe in the install directory: fails, copies nothing',
    () async {
      final ops = MemoryFileOps()..files_['$_install\\a.dll'] = 1;
      await expectLater(
        prepareWindowsRuntime(
          installDir: _install,
          localAppData: _local,
          version: '1.6.0',
          ops: ops,
        ),
        throwsA(anything),
      );
      expect(ops.copies, 0);
    },
  );

  group('cleanupOldRuntimes', () {
    const root = r'C:\Users\me\AppData\Local\ShellX\mux';
    test(
      'removes the other versions and half-copied ones, keeps its own',
      () async {
        final ops = MemoryFileOps()
          ..files_.addAll({
            '$root\\1.5.0\\shellx-mux.exe': 1,
            '$root\\1.6.0\\shellx-mux.exe': 1,
            '$root\\1.7.0.tmp-ab12\\shellx-mux.exe': 1,
            '$root\\endpoint': 3,
            '$root\\mux.lock': 0,
          })
          ..dirs.add('$root\\1.4.0');
        await cleanupOldRuntimes(localAppData: _local, keep: '1.6.0', ops: ops);
        expect(await ops.directoryExists('$root\\1.5.0'), isFalse);
        expect(await ops.directoryExists('$root\\1.4.0'), isFalse);
        expect(await ops.directoryExists('$root\\1.7.0.tmp-ab12'), isFalse);
        expect(await ops.directoryExists('$root\\1.6.0'), isTrue);
        // Not runtime directories: untouched.
        expect(ops.files_.containsKey('$root\\endpoint'), isTrue);
        expect(ops.files_.containsKey('$root\\mux.lock'), isTrue);
      },
    );

    test('a directory in use is skipped, the rest is still cleaned', () async {
      final ops = MemoryFileOps()
        ..files_.addAll({
          '$root\\1.4.0\\shellx-mux.exe': 1,
          '$root\\1.5.0\\shellx-mux.exe': 1,
        })
        ..inUse.add('$root\\1.4.0\\shellx-mux.exe');
      await cleanupOldRuntimes(localAppData: _local, keep: '1.6.0', ops: ops);
      expect(await ops.directoryExists('$root\\1.4.0'), isTrue);
      expect(await ops.directoryExists('$root\\1.5.0'), isFalse);
    });

    test('a running daemon\'s directory keeps all its files', () async {
      final ops = MemoryFileOps()
        ..files_.addAll({
          '$root\\1.4.0\\shellx-mux.exe': 1,
          '$root\\1.4.0\\flutter_windows.dll': 1,
        })
        ..inUse.add('$root\\1.4.0\\shellx-mux.exe');
      await cleanupOldRuntimes(localAppData: _local, keep: '1.6.0', ops: ops);
      expect(ops.files_.keys, hasLength(2));
    });

    test('a fresh .tmp- directory (a start is copying) stays', () async {
      final ops = MemoryFileOps()
        ..files_['$root\\1.7.0.tmp-ab12\\shellx-mux.exe'] = 1;
      ops.ages['$root\\1.7.0.tmp-ab12'] = ops.now.subtract(
        const Duration(minutes: 4),
      );
      await cleanupOldRuntimes(
        localAppData: _local,
        keep: '1.6.0',
        ops: ops,
        now: () => ops.now,
      );
      expect(await ops.directoryExists('$root\\1.7.0.tmp-ab12'), isTrue);
    });

    test('a version that could leave the directory is refused', () async {
      for (final bad in ['..\\x', '1.6.0\\..', 'a/b', '', '.hidden', 'a b']) {
        await expectLater(
          prepareWindowsRuntime(
            installDir: _install,
            localAppData: _local,
            version: bad,
            ops: installed(),
          ),
          throwsArgumentError,
          reason: bad,
        );
        await expectLater(
          cleanupOldRuntimes(
            localAppData: _local,
            keep: bad,
            ops: MemoryFileOps(),
          ),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('nothing there is not an error', () async {
      await cleanupOldRuntimes(
        localAppData: _local,
        keep: '1.6.0',
        ops: MemoryFileOps(),
      );
    });
  });
}
