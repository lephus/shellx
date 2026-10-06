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

  test('a failed layout write returns false, keeps the old file and '
      'succeeds on retry (§5 disk full)', () async {
    // A non-empty directory where the temp file wants to go makes the
    // write fail the way a full disk does: before the rename.
    final blocker = Directory('${root.path}/blocked');
    final locked = RestoreStore(blocker, log: logs.add);
    await blocker.create();
    await File('${blocker.path}/layout.json').create();
    await Process.run('/bin/chmod', ['500', blocker.path]);
    expect(await locked.writeLayout(snap()), isFalse);
    expect(await File('${blocker.path}/layout.json').readAsString(), '');
    expect(
      blocker.listSync().map((e) => e.path).where((p) => p.contains('.tmp-')),
      isEmpty,
    );
    await Process.run('/bin/chmod', ['700', blocker.path]);
    expect(await locked.writeLayout(snap('/new')), isTrue);
    final back = await locked.loadLayout();
    expect(back.snapshot!.encode(), snap('/new').encode());
    expect(logs.join(), isNot(contains(root.path)));
  }, testOn: '!windows');

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

  test('without POSIX permissions scrollback is never written (§5)', () async {
    // chmod cannot fail for the owner in a temp dir, so it is injected.
    final plain = RestoreStore(
      Directory('${root.path}/no-chmod'),
      posix: true,
      chmod: (mode, paths) async => false,
      log: logs.add,
    );
    expect(await plain.prepare(), isFalse);
    await plain.writeScrollbacks({k1: 'x'});
    expect(await plain.hasScrollback(), isFalse);
  });

  test('NullRestoreFiles stores nothing', () async {
    const files = NullRestoreFiles();
    expect(await files.prepare(), isFalse);
    expect(await files.writeLayout(snap()), isTrue);
    final load = await files.loadLayout();
    expect(load.snapshot, isNull);
    expect(load.corrupt, isFalse);
    await files.writeScrollbacks({k1: 'x'});
    expect(await files.readScrollback(k1), isNull);
    expect(await files.scrollbackSavedAt(k1), isNull);
    expect(await files.hasScrollback(), isFalse);
    await files.deleteScrollback(k1);
    await files.deleteAllScrollback();
    await files.removeOrphans({k1});
  });
}
