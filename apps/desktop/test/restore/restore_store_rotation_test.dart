import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';

final k1 = 'a' * 32, k2 = 'b' * 32, k3 = 'c' * 32;

RestoreSnapshot snap(String key, {bool clean = false, bool empty = false}) =>
    RestoreSnapshot(
      savedAt: DateTime.utc(2026, 10, 7),
      cleanExit: clean,
      selectedTab: empty ? null : key,
      workspaces: [
        SavedWorkspace(id: 'default', tabs: empty ? [] : [key]),
      ],
      tabs: empty
          ? []
          : [
              SavedTab(
                key: key,
                focused: key,
                layout: SavedPane(key: key, cwd: '/tmp'),
              ),
            ],
    );

void main() {
  group('pickSnapshot (A10 D25)', () {
    test('a layout with tabs always wins', () {
      final r = pickSnapshot(current: snap(k1), generations: [snap(k2)]);
      expect(r.snapshot!.tabs.single.key, k1);
      expect(r.recovered, isFalse);
    });

    test('empty after a crash gives way to the last run that had tabs', () {
      final r = pickSnapshot(
        current: snap(k1, empty: true),
        generations: [snap(k2, clean: true), null],
      );
      expect(r.snapshot!.tabs.single.key, k2);
      expect(r.recovered, isTrue);
      expect(r.snapshot!.cleanExit, isFalse, reason: 'the strip shows');
    });

    test('empty after a clean quit is respected', () {
      final r = pickSnapshot(
        current: snap(k1, empty: true, clean: true),
        generations: [snap(k2)],
      );
      expect(r.snapshot!.tabs, isEmpty);
      expect(r.recovered, isFalse);
    });

    test('unreadable: the first generation that has tabs', () {
      final r = pickSnapshot(
        current: null,
        generations: [snap(k2, empty: true), snap(k3)],
      );
      expect(r.snapshot!.tabs.single.key, k3);
      expect(r.recovered, isTrue);
    });

    test('nothing at all', () {
      final r = pickSnapshot(current: null, generations: [null, null]);
      expect(r.snapshot, isNull);
      expect(r.recovered, isFalse);
    });
  });

  group('RestoreStore generations', () {
    late Directory root;
    late RestoreStore store;
    final logs = <String>[];

    setUp(() async {
      root = await Directory.systemTemp.createTemp('restore_rotation_test');
      logs.clear();
      store = RestoreStore(
        Directory('${root.path}/restore'),
        excludeFromBackup: (_) async {},
        log: logs.add,
      );
      await store.prepare();
    });
    tearDown(() => root.delete(recursive: true));

    String path(String name) => '${store.directory.path}/$name';

    test('each run that starts with tabs shifts the generations', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout(); // run 2 starts from k1
      expect(File(path('layout.json.1')).existsSync(), isTrue);
      expect(File(path('layout.json.2')).existsSync(), isFalse);

      await store.writeLayout(snap(k2));
      await store.loadLayout(); // run 3 starts from k2
      expect(
        RestoreSnapshot.tryParse(
          File(path('layout.json.1')).readAsStringSync(),
        )!.tabs.single.key,
        k2,
      );
      expect(
        RestoreSnapshot.tryParse(
          File(path('layout.json.2')).readAsStringSync(),
        )!.tabs.single.key,
        k1,
      );
    });

    test('the same layout twice does not push a good one out', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout();
      await store.writeLayout(snap(k2));
      await store.loadLayout();
      await store.loadLayout(); // a quick second crash: same k2 again
      await store.loadLayout();
      expect(
        RestoreSnapshot.tryParse(
          File(path('layout.json.2')).readAsStringSync(),
        )!.tabs.single.key,
        k1,
      );
    });

    test('closing every tab and crashing does not bring them back', () async {
      // The user emptied the window: the write of the empty layout (unclean:
      // the window hid, or the service died) ends the old generations.
      await store.writeLayout(snap(k1));
      await store.loadLayout(); // generation 1 = k1
      await store.writeLayout(snap(k1, empty: true)); // then kill -9
      final load = await store.loadLayout();
      expect(load.recovered, isFalse);
      expect(load.snapshot!.tabs, isEmpty);
      expect(File(path('layout.json.1')).existsSync(), isFalse);
    });

    test(
      'an empty unclean layout that nobody wrote is still recovered',
      () async {
        // Parseable but empty, not written by this store (a bug elsewhere):
        // the generations are intact.
        await store.writeLayout(snap(k1));
        await store.loadLayout();
        File(
          path('layout.json'),
        ).writeAsStringSync(snap(k1, empty: true).encode());
        final load = await store.loadLayout();
        expect(load.recovered, isTrue);
        expect(load.snapshot!.tabs.single.key, k1);
      },
    );

    test('a damaged generation 1 is not rotated over a good 2', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout();
      await store.writeLayout(snap(k2));
      await store.loadLayout(); // 1 = k2, 2 = k1
      File(path('layout.json.1')).writeAsStringSync('garbage');
      await store.writeLayout(snap(k3));
      await store.loadLayout();
      String keyOf(int n) => RestoreSnapshot.tryParse(
        File(path('layout.json.$n')).readAsStringSync(),
      )!.tabs.single.key;
      expect(keyOf(1), k3);
      expect(keyOf(2), k1);
    });

    test(
      'a corrupt layout falls back to a generation and keeps .bak',
      () async {
        await store.writeLayout(snap(k1));
        await store.loadLayout();
        File(path('layout.json')).writeAsStringSync('{"not": "ours"');
        final load = await store.loadLayout();
        expect(load.corrupt, isTrue);
        expect(load.recovered, isTrue);
        expect(load.snapshot!.tabs.single.key, k1);
        expect(File(path('layout.json.bak')).existsSync(), isTrue);
      },
    );

    test('a damaged generation 1 is skipped for 2', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout();
      await store.writeLayout(snap(k2));
      await store.loadLayout(); // 1 = k2, 2 = k1
      File(path('layout.json.1')).writeAsStringSync('garbage');
      File(path('layout.json')).writeAsStringSync('garbage');
      final load = await store.loadLayout();
      expect(load.snapshot!.tabs.single.key, k1);
    });

    test(
      'generations are 0600 and nothing is logged about their content',
      () async {
        await store.writeLayout(snap(k1));
        await store.loadLayout();
        final mode =
            (Process.runSync('stat', [
                      ...(Platform.isMacOS ? ['-f', '%Lp'] : ['-c', '%a']),
                      path('layout.json.1'),
                    ]).stdout
                    as String)
                .trim();
        expect(mode, '600');
        expect(logs.join(), isNot(contains(k1)));
      },
      testOn: '!windows',
    );

    test('a clean empty layout is not replaced by a generation', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout();
      await store.writeLayout(snap(k1, empty: true, clean: true));
      final load = await store.loadLayout();
      expect(load.recovered, isFalse);
      expect(load.snapshot!.tabs, isEmpty);
    });

    test('removeOrphans keeps the scrollback of the generations', () async {
      await store.writeLayout(snap(k1));
      await store.loadLayout(); // generation 1 = k1
      await store.writeScrollbacks({k1: 'one', k3: 'three'});
      await store.removeOrphans({k2});
      expect(await store.readScrollback(k1), 'one');
      expect(await store.readScrollback(k3), isNull);
    });
  });
}
