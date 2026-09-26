import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

import '../../support/fakes.dart';

void main() {
  late InMemoryKeyValueStore store;
  late PendingUnpairs pending;

  setUp(() {
    store = InMemoryKeyValueStore();
    pending = PendingUnpairs(store);
  });

  test('entries are kept per account as a JSON list of {agentId, name}', () async {
    await pending.add('user-1', agentA, 'MacBook-Pro');
    await pending.add('user-1', agentB, null);
    await pending.add('user-2', agentA, 'Other');

    expect(await pending.load('user-1'), [(agentId: agentA, name: 'MacBook-Pro'), (agentId: agentB, name: null)]);
    expect(await pending.load('user-2'), [(agentId: agentA, name: 'Other')]);
    expect(jsonDecode((await store.read('pending_unpairs_user-1'))!), [
      {'agentId': agentA, 'name': 'MacBook-Pro'},
      {'agentId': agentB, 'name': null},
    ]);
  });

  test('adding a machine again keeps one entry and the name it had', () async {
    await pending.add('user-1', agentA, 'MacBook-Pro');
    await pending.add('user-1', agentA, null);
    expect(await pending.load('user-1'), [(agentId: agentA, name: 'MacBook-Pro')]);
  });

  test('removing the last entry deletes the record; other accounts keep theirs', () async {
    await pending.add('user-1', agentA, 'MacBook-Pro');
    await pending.add('user-2', agentA, 'Other');
    await pending.remove('user-1', agentA);
    expect(await store.read('pending_unpairs_user-1'), isNull);
    expect(await pending.load('user-2'), hasLength(1));
  });

  test('concurrent updates do not lose each other', () async {
    await Future.wait([
      pending.add('user-1', agentA, 'a'),
      pending.add('user-1', agentB, 'b'),
      pending.remove('user-1', agentA),
      pending.add('user-1', agentA, 'a'),
    ]);
    expect((await pending.load('user-1')).map((e) => e.agentId), unorderedEquals([agentA, agentB]));
  });

  test('a damaged record reads as nothing pending', () async {
    await store.write('pending_unpairs_user-1', 'not json');
    expect(await pending.load('user-1'), isEmpty);
    await store.write('pending_unpairs_user-1', '[{"agentId": 3}]');
    expect(await pending.load('user-1'), isEmpty);
  });

  group('retry', () {
    late FakeBackend backend;

    setUp(() => backend = FakeBackend());

    test('a successful unpair drops the entry; a failed one keeps it', () async {
      await pending.add('user-1', agentA, 'MacBook-Pro');
      await pending.retry('user-1', backend);
      expect(backend.unpaired, [agentA]);
      expect(await pending.load('user-1'), isEmpty);

      await pending.add('user-1', agentB, 'DESKTOP-42');
      backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
      await pending.retry('user-1', backend);
      expect(backend.unpaired, [agentA, agentB]);
      expect(await pending.load('user-1'), [(agentId: agentB, name: 'DESKTOP-42')]);
    });

    test('a machine paired again since is only dropped from the record, never unpaired', () async {
      backend.pinnedList = [pinned(agentA)];
      await pending.add('user-1', agentA, 'MacBook-Pro');
      await pending.retry('user-1', backend);
      expect(backend.unpaired, isEmpty);
      expect(await pending.load('user-1'), isEmpty);
    });

    test('nothing pending sends nothing; a failure to read the pins never throws', () async {
      await pending.retry('user-1', backend);
      expect(backend.unpaired, isEmpty);

      await pending.add('user-1', agentA, null);
      backend.pinnedError = StateError('keychain');
      await pending.retry('user-1', backend);
      expect(backend.unpaired, isEmpty);
      expect(await pending.load('user-1'), hasLength(1));
    });
  });
}
