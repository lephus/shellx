import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_paths.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';

final k1 = 'a' * 32, k2 = 'b' * 32;

RestoreSnapshot snap([String cwd = '/tmp']) => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7),
  cleanExit: false,
  selectedTab: k1,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k1]),
  ],
  tabs: [
    SavedTab(
      key: k1,
      focused: k1,
      layout: SavedPane(key: k1, cwd: cwd),
    ),
  ],
);

/// Permission bits: BSD `stat -f` on macOS, GNU `stat -c` on Linux.
String mode(String path) =>
    (Process.runSync(
              'stat',
              Platform.isMacOS ? ['-f', '%Lp', path] : ['-c', '%a', path],
            ).stdout
            as String)
        .trim();

void main() {
  late Directory root;
  late RestoreStore store;
  final excluded = <String>[];
  final logs = <String>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('restore_store_test');
    excluded.clear();
    logs.clear();
    store = RestoreStore(
      Directory('${root.path}/restore'),
      excludeFromBackup: (p) async => excluded.add(p),
      log: logs.add,
    );
    expect(await store.prepare(), isTrue);
  });
  tearDown(() => root.delete(recursive: true));

  String layoutPath() => '${store.directory.path}/layout.json';

  test('paths: macOS app support, Windows LOCALAPPDATA (D2)', () {
    expect(
      restoreDirectoryPath(
        windows: false,
        environment: const {},
        appSupportPath:
            '/Users/a/Library/Application Support/pro.shellx.desktop',
      ),
      '/Users/a/Library/Application Support/pro.shellx.desktop/restore',
    );
    expect(
      restoreDirectoryPath(
        windows: true,
        environment: const {'LOCALAPPDATA': r'C:\Users\a\AppData\Local'},
        appSupportPath: r'C:\Users\a\AppData\Roaming\pro.shellx\ShellX',
      ),
      r'C:\Users\a\AppData\Local\ShellX\restore',
    );
    expect(
      () => restoreDirectoryPath(
        windows: true,
        environment: const {},
        appSupportPath: r'C:\Users\a\AppData\Roaming\pro.shellx\ShellX',
      ),
      throwsStateError,
    );
  });

  test('prepare: 0700 directories, excluded from backup once', () {
    expect(mode(store.directory.path), '700');
    expect(mode('${store.directory.path}/scrollback'), '700');
    expect(excluded, [store.directory.path]);
  }, testOn: '!windows');

  test('layout round trip, 0600, no temp files left', () async {
    expect(await store.writeLayout(snap()), isTrue);
    final load = await store.loadLayout();
    expect(load.corrupt, isFalse);
    expect(load.snapshot!.encode(), snap().encode());
    expect(mode(layoutPath()), '600');
    expect(
      store.directory
          .listSync()
          .map((e) => e.path)
          .where((p) => p.contains('.tmp-')),
      isEmpty,
    );
  }, testOn: '!windows');

  test('scrollback files are 0600', () async {
    await store.writeScrollbacks({k1: 'one\r\n'});
    expect(mode('${store.directory.path}/scrollback/$k1.txt'), '600');
  }, testOn: '!windows');

  test('no file → no snapshot, not corrupt', () async {
    final load = await store.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isFalse);
  });

  test(
    'corrupt layout → .bak, fresh start, content never logged (D11)',
    () async {
      File(layoutPath()).writeAsStringSync('{"v":1, garbage /secret/path');
      final load = await store.loadLayout();
      expect(load.snapshot, isNull);
      expect(load.corrupt, isTrue);
      expect(File(layoutPath()).existsSync(), isFalse);
      expect(
        File('${layoutPath()}.bak').readAsStringSync(),
        contains('garbage'),
      );
      expect(logs.join(), isNot(contains('secret')));
      expect(logs.join(), isNot(contains(root.path)));
    },
  );

  test('an oversized layout is corrupt, kept as .bak, never parsed', () async {
    // Valid JSON padded past the cap: the size check alone rejects it.
    final padded = snap().encode().replaceFirst(
      '{',
      '{"pad":"${'x' * kRestoreMaxLayoutBytes}",',
    );
    expect(RestoreSnapshot.tryParse(padded), isNotNull);
    File(layoutPath()).writeAsStringSync(padded);
    final load = await store.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isTrue);
    expect(File(layoutPath()).existsSync(), isFalse);
    expect(File('${layoutPath()}.bak').lengthSync(), padded.length);
  });

  test('a failed layout write returns false, leaves no temp file and '
      'succeeds on retry (§5 disk full)', () async {
    // A non-empty directory at the target makes the final rename fail on
    // every platform, as a full disk fails a write: nothing is replaced.
    final blocker = Directory(layoutPath());
    await blocker.create();
    await File('${blocker.path}/keep').create();
    expect(await store.writeLayout(snap()), isFalse);
    expect(blocker.existsSync(), isTrue);
    expect(
      store.directory
          .listSync()
          .map((e) => e.path)
          .where((p) => p.contains('.tmp-')),
      isEmpty,
    );
    await blocker.delete(recursive: true);
    expect(await store.writeLayout(snap('/new')), isTrue);
    final back = await store.loadLayout();
    expect(back.snapshot!.encode(), snap('/new').encode());
    expect(logs.join(), isNot(contains(root.path)));
  });

  test('a failed private write keeps the previous scrollback', () async {
    var chmodOk = true;
    final flaky = RestoreStore(
      Directory('${root.path}/flaky'),
      posix: true,
      chmod: (mode, paths) async => chmodOk,
      log: logs.add,
    );
    expect(await flaky.prepare(), isTrue);
    expect(await flaky.writeScrollbacks({k1: 'old'}), isTrue);
    chmodOk = false;
    expect(await flaky.writeScrollbacks({k1: 'new'}), isFalse);
    expect(await flaky.readScrollback(k1), 'old');
    expect(
      Directory(
        '${root.path}/flaky/scrollback',
      ).listSync().map((e) => e.path).where((p) => p.contains('.tmp-')),
      isEmpty,
    );
  });

  test('loadLayout retries once on a file system error (M4)', () async {
    File(layoutPath()).writeAsStringSync(snap().encode());
    var reads = 0;
    final retrying = RestoreStore(
      store.directory,
      readLayout: (file) async {
        if (++reads == 1) throw const FileSystemException('busy');
        return file.readAsString();
      },
      log: logs.add,
    );
    final load = await retrying.loadLayout();
    expect(reads, 2);
    expect(load.corrupt, isFalse);
    expect(load.snapshot!.encode(), snap().encode());
  });

  test('loadLayout gives up after the retry: .bak, corrupt', () async {
    File(layoutPath()).writeAsStringSync(snap().encode());
    var reads = 0;
    final failing = RestoreStore(
      store.directory,
      readLayout: (file) async {
        reads++;
        throw const FileSystemException('busy');
      },
      log: logs.add,
    );
    final load = await failing.loadLayout();
    expect(reads, 2);
    expect(load.corrupt, isTrue);
    expect(File('${layoutPath()}.bak').existsSync(), isTrue);
  });

  test('a parse failure is not retried', () async {
    File(layoutPath()).writeAsStringSync('garbage');
    var reads = 0;
    final counting = RestoreStore(
      store.directory,
      readLayout: (file) async {
        reads++;
        return file.readAsString();
      },
      log: logs.add,
    );
    expect((await counting.loadLayout()).corrupt, isTrue);
    expect(reads, 1);
  });

  test('scrollback: batch write, sanitized read, delete', () async {
    await store.writeScrollbacks({
      k1: 'one\x1b]52;c;eA==\x07\r\n',
      k2: 'two\r\n',
    });
    expect(await store.readScrollback(k1), 'one\r\n');
    expect(await store.hasScrollback(), isTrue);
    expect(await store.scrollbackSavedAt(k1), isNotNull);
    await store.deleteScrollback(k1);
    expect(await store.readScrollback(k1), isNull);
    expect(await store.scrollbackSavedAt(k1), isNull);
    await store.deleteAllScrollback();
    expect(await store.hasScrollback(), isFalse);
  });

  test('oversized or invalid UTF-8 scrollback is ignored (D6)', () async {
    File(
      '${store.directory.path}/scrollback/$k1.txt',
    ).writeAsBytesSync(List.filled(524289, 0x41));
    File(
      '${store.directory.path}/scrollback/$k2.txt',
    ).writeAsBytesSync([0xff, 0xfe]);
    expect(await store.readScrollback(k1), isNull);
    expect(await store.readScrollback(k2), isNull);
  });

  test('a non-key name is never read or written', () async {
    await store.writeScrollbacks({'../x': 'nope'});
    expect(File('${store.directory.path}/x.txt').existsSync(), isFalse);
    expect(await store.readScrollback('../x'), isNull);
  });

  test('orphans and stray temp files are removed (D15)', () async {
    await store.writeScrollbacks({k1: 'a', k2: 'b'});
    File(
      '${store.directory.path}/scrollback/$k1.txt.tmp-1-ff',
    ).writeAsStringSync('x');
    File('${layoutPath()}.tmp-1-ff').writeAsStringSync('x');
    await store.removeOrphans({k1});
    final names = Directory(
      '${store.directory.path}/scrollback',
    ).listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['$k1.txt']);
    expect(File('${layoutPath()}.tmp-1-ff').existsSync(), isFalse);
  });

  test(
    'serial queue: delete-all after an in-flight write wins (D25)',
    () async {
      final write = store.writeScrollbacks({k1: 'a' * 200000});
      final clear = store.deleteAllScrollback();
      await Future.wait([write, clear]);
      expect(await store.hasScrollback(), isFalse);
    },
  );

  test('queued layout writes coalesce: the newest replaces the pending one '
      '(D25)', () async {
    // Keeps the queue busy so the layout writes below wait.
    final busy = store.writeScrollbacks({k1: 'a' * 200000});
    final first = store.writeLayout(snap('/one'));
    final second = store.writeLayout(snap('/two'));
    final third = store.writeLayout(snap('/three'));
    // When the second caller's write is reported done, the file already
    // holds the newest layout: the second was never written on its own.
    expect(await second, isTrue);
    expect(
      RestoreSnapshot.tryParse(File(layoutPath()).readAsStringSync())!.encode(),
      snap('/three').encode(),
    );
    expect(await first, isTrue);
    expect(await third, isTrue);
    await busy;
  });

  test('a layout write queued after a load is not merged into an earlier '
      'one', () async {
    final busy = store.writeScrollbacks({k1: 'a' * 200000});
    final before = store.writeLayout(snap('/before'));
    final load = store.loadLayout();
    final after = store.writeLayout(snap('/after'));
    await busy;
    expect(await before, isTrue);
    expect((await load).snapshot!.encode(), snap('/before').encode());
    expect(await after, isTrue);
    expect(
      (await store.loadLayout()).snapshot!.encode(),
      snap('/after').encode(),
    );
  });

  test('without POSIX permissions scrollback is never written, the layout '
      'still is (§5)', () async {
    // chmod cannot fail for the owner in a temp dir, so it is injected.
    final plain = RestoreStore(
      Directory('${root.path}/no-chmod'),
      posix: true,
      chmod: (mode, paths) async => false,
      log: logs.add,
    );
    expect(await plain.prepare(), isFalse);
    // Dropped, not failed: retrying would not help.
    expect(await plain.writeScrollbacks({k1: 'x'}), isTrue);
    expect(await plain.hasScrollback(), isFalse);
    expect(await plain.writeLayout(snap()), isTrue);
    expect(await plain.writeLayout(snap('/again')), isTrue);
    expect(
      (await plain.loadLayout()).snapshot!.encode(),
      snap('/again').encode(),
    );
    expect(logs.where((l) => l.contains('layout permissions')).length, 1);
    expect(logs.join(), isNot(contains(root.path)));
  });

  test('orphan cleanup matches temp names, not a directory path containing '
      '.tmp- (M1)', () async {
    final odd = RestoreStore(Directory('${root.path}/x.tmp-1/restore'));
    expect(await odd.prepare(), isTrue);
    expect(await odd.writeLayout(snap()), isTrue);
    await odd.writeScrollbacks({k1: 'a'});
    await odd.removeOrphans({k1});
    expect(File('${odd.directory.path}/layout.json').existsSync(), isTrue);
    expect(await odd.readScrollback(k1), 'a');
  });

  test('a backup exclusion that never completes does not wedge the queue '
      '(M2)', () async {
    final hung = RestoreStore(
      Directory('${root.path}/hung'),
      excludeFromBackup: (_) => Completer<void>().future,
      excludeTimeout: const Duration(milliseconds: 50),
      log: logs.add,
    );
    expect(await hung.prepare(), isTrue);
    expect(await hung.writeLayout(snap()), isTrue);
    // The exclusion runs in the background; its timeout is still logged.
    // Poll with a wide deadline: the 50 ms timer can fire late under load.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!logs.any((l) => l.contains('backup exclusion failed')) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      logs.where((l) => l.contains('backup exclusion failed')),
      hasLength(1),
    );
  });

  test('prepare does not wait for the backup exclusion: the queue moves on '
      'at once (startup never waits for tmutil)', () async {
    final slow = RestoreStore(
      Directory('${root.path}/slow'),
      excludeFromBackup: (_) => Completer<void>().future,
      excludeTimeout: const Duration(seconds: 30),
      log: logs.add,
    );
    const quick = Duration(seconds: 10); // far below the 30 s exclusion timeout
    expect(await slow.prepare().timeout(quick), isTrue);
    expect(await slow.writeLayout(snap()).timeout(quick), isTrue);
    expect((await slow.loadLayout().timeout(quick)).snapshot, isNotNull);
  });

  test('NullRestoreFiles stores nothing', () async {
    const files = NullRestoreFiles();
    expect(await files.prepare(), isFalse);
    expect(await files.writeLayout(snap()), isTrue);
    final load = await files.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isFalse);
    expect(await files.writeScrollbacks({k1: 'x'}), isTrue);
    expect(await files.readScrollback(k1), isNull);
    expect(await files.scrollbackSavedAt(k1), isNull);
    expect(await files.hasScrollback(), isFalse);
    await files.deleteScrollback(k1);
    await files.deleteAllScrollback();
    await files.removeOrphans({k1});
  });
}
