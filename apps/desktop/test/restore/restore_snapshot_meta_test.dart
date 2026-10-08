import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';

final k1 = 'a' * 32;

RestoreSnapshot oneTabSnapshot({
  bool pinned = false,
  String description = '',
  TabStatus status = TabStatus.none,
}) => RestoreSnapshot(
  savedAt: DateTime.utc(2026, 10, 7, 14, 32),
  cleanExit: true,
  selectedTab: k1,
  workspaces: [
    SavedWorkspace(id: 'default', tabs: [k1]),
  ],
  tabs: [
    SavedTab(
      key: k1,
      focused: k1,
      layout: SavedPane(key: k1, cwd: '/tmp', session: 3),
      pinned: pinned,
      description: description,
      status: status,
    ),
  ],
);

/// The shape A5a/A11-before wrote: no pinned, desc or status.
const legacyLayoutJson =
    '{"v":1,"savedAt":"2026-10-07T14:32:00.000Z","cleanExit":true,'
    '"daemon":null,"selectedTab":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
    '"workspaces":[{"id":"default","tabs":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}],'
    '"tabs":[{"key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":null,'
    '"focused":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","zoomed":null,'
    '"layout":{"pane":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cwd":"/tmp","session":3}}]}';

Map<String, Object?> firstTab(String text) =>
    ((jsonDecode(text) as Map)['tabs'] as List).first as Map<String, Object?>;

void main() {
  test(
    'pinned, description and status survive a round trip, version stays 1',
    () {
      final snap = oneTabSnapshot(
        pinned: true,
        description: 'waiting for review',
        status: TabStatus.review,
      );
      final back = RestoreSnapshot.tryParse(snap.encode())!;
      final t = back.tabs.single;
      expect(
        (t.pinned, t.description, t.status),
        (true, 'waiting for review', TabStatus.review),
      );
      expect(jsonDecode(snap.encode())['v'], 1);
      expect(back.encode(), snap.encode());
    },
  );

  test('an undecorated tab writes none of the new keys (byte-identical)', () {
    final tab = firstTab(oneTabSnapshot().encode());
    expect(tab.keys, isNot(contains('pinned')));
    expect(tab.keys, isNot(contains('desc')));
    expect(tab.keys, isNot(contains('status')));
    // The same text an A5a build wrote.
    expect(oneTabSnapshot().encode(), legacyLayoutJson);
  });

  test(
    'a file from before A11 has none of the keys and loads with defaults',
    () {
      final old = RestoreSnapshot.tryParse(legacyLayoutJson)!;
      expect(
        (
          old.tabs.single.pinned,
          old.tabs.single.description,
          old.tabs.single.status,
        ),
        (false, '', TabStatus.none),
      );
    },
  );

  test('unknown extra keys on a tab are ignored (an older build reading)', () {
    final map = jsonDecode(oneTabSnapshot(pinned: true).encode()) as Map;
    ((map['tabs'] as List).first as Map)['future'] = 1;
    map['future'] = 1;
    expect(RestoreSnapshot.tryParse(jsonEncode(map)), isNotNull);
  });

  test('a bad status or a 10 000-character description is repaired', () {
    final map =
        jsonDecode(oneTabSnapshot(pinned: true).encode())
            as Map<String, Object?>;
    final tab = (map['tabs']! as List).first as Map<String, Object?>;
    tab['status'] = 'weird';
    tab['desc'] = 'x\ny' * 4000;
    tab['pinned'] = 'yes';
    final t = RestoreSnapshot.tryParse(jsonEncode(map))!.tabs.single;
    expect(t.status, TabStatus.none);
    expect(t.pinned, isFalse);
    expect(t.description.length, 120);
    expect(t.description, isNot(contains('\n')));
    tab['desc'] = 42;
    expect(
      RestoreSnapshot.tryParse(jsonEncode(map))!.tabs.single.description,
      '',
    );
  });
}
