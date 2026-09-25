import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

TrustedDevice device(String id, int keyByte, {String name = 'Phone'}) =>
    TrustedDevice(
      mobileId: id,
      publicKey: Uint8List.fromList(List.filled(32, keyByte)),
      name: name,
      pairedAt: DateTime.utc(2026, 9, 25, 10),
    );

void main() {
  test('TrustedDevice round-trips through JSON with a base64url key', () {
    final original = device('m1', 7, name: 'iPhone của Phú');
    final json = original.toJson();
    expect(json['public_key'], base64UrlNoPad(original.publicKey));
    expect(
      json['paired_at'],
      DateTime.utc(2026, 9, 25, 10).millisecondsSinceEpoch,
    );
    final copy = TrustedDevice.fromJson(json);
    expect(copy.mobileId, 'm1');
    expect(copy.publicKey, original.publicKey);
    expect(copy.name, 'iPhone của Phú');
    expect(copy.pairedAt, original.pairedAt);
  });

  test('add, find, list, replace and remove', () async {
    final kv = InMemoryKeyValueStore();
    final store = TrustedStore(kv);
    expect(await store.list(), isEmpty);

    await store.add(device('m1', 1));
    await store.add(device('m2', 2));
    await store.add(device('m1', 3, name: 'New phone'));

    final all = await store.list();
    expect([for (final d in all) d.mobileId], ['m2', 'm1']);
    expect((await store.find('m1'))!.publicKey.first, 3);
    expect(await store.find('m9'), isNull);

    await store.remove('m2');
    expect([for (final d in await store.list()) d.mobileId], ['m1']);
    await store.clear();
    expect(await store.list(), isEmpty);
  });

  test('persists as a JSON array under trusted_devices', () async {
    final kv = InMemoryKeyValueStore();
    await TrustedStore(kv).add(device('m1', 1));
    final raw = await kv.read(TrustedStore.storageKey);
    expect(TrustedStore.storageKey, 'trusted_devices');
    expect(jsonDecode(raw!), isA<List<Object?>>());
    expect((await TrustedStore(kv).find('m1')), isNotNull);
  });

  test('corrupt storage fails closed (nobody is trusted)', () async {
    final kv = InMemoryKeyValueStore();
    await kv.write(TrustedStore.storageKey, '{not json');
    expect(await TrustedStore(kv).list(), isEmpty);
  });

  test('concurrent adds are not lost and changes fire per mutation', () async {
    final store = TrustedStore(InMemoryKeyValueStore());
    var changes = 0;
    store.changes.listen((_) => changes++);
    await Future.wait([
      store.add(device('m1', 1)),
      store.add(device('m2', 2)),
      store.add(device('m3', 3)),
    ]);
    await pumpEventQueue();
    expect(await store.list(), hasLength(3));
    expect(changes, 3);
  });
}
