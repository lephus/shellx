import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

PinnedMachine machine(String id, int keyByte) => PinnedMachine(
  agentId: id,
  publicKey: Uint8List.fromList(List.filled(32, keyByte)),
  pairedAt: DateTime.utc(2026, 9, 25),
);

void main() {
  test('PinnedMachine round-trips through JSON', () {
    final original = machine('a1', 5);
    final json = original.toJson();
    expect(json['agent_id'], 'a1');
    expect(json['public_key'], base64UrlNoPad(original.publicKey));
    final copy = PinnedMachine.fromJson(json);
    expect(copy.publicKey, original.publicKey);
    expect(copy.pairedAt, original.pairedAt);
  });

  test('add, find, replace and remove', () async {
    final store = PinnedStore(InMemoryKeyValueStore(), userId: 'u1');
    await store.add(machine('a1', 1));
    await store.add(machine('a2', 2));
    await store.add(machine('a1', 3));
    expect([for (final m in await store.list()) m.agentId], ['a2', 'a1']);
    expect((await store.find('a1'))!.publicKey.first, 3);
    await store.remove('a1');
    expect(await store.find('a1'), isNull);
  });

  test('pins are stored per account under pinned_machines_<userId>', () async {
    final kv = InMemoryKeyValueStore();
    await PinnedStore(kv, userId: 'u1').add(machine('a1', 1));
    expect(await kv.read('pinned_machines_u1'), isNotNull);
    expect(await PinnedStore(kv, userId: 'u2').list(), isEmpty);
    expect(await PinnedStore(kv, userId: 'u1').list(), hasLength(1));
  });

  test('corrupt storage reads as no pins', () async {
    final kv = InMemoryKeyValueStore();
    await kv.write('pinned_machines_u1', '[{"agent_id": 1}]');
    expect(await PinnedStore(kv, userId: 'u1').list(), isEmpty);
  });
}
