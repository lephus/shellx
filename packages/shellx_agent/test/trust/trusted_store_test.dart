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

  test('TrustedDevice rejects public keys that are not 32 bytes', () {
    expect(
      () => TrustedDevice.fromJson({
        'mobile_id': 'm1',
        'public_key': base64UrlNoPad(Uint8List(16)), // Wrong length
        'name': 'Phone',
        'paired_at': 0,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'TrustedStore skips entries with invalid key lengths but keeps valid ones',
    () async {
      final kv = InMemoryKeyValueStore();
      // Manually write storage with one valid and one invalid entry.
      await kv.write(
        TrustedStore.storageKey,
        jsonEncode([
          {
            'mobile_id': 'm1',
            'public_key': base64UrlNoPad(
              Uint8List.fromList(List.filled(32, 7)),
            ),
            'name': 'Valid',
            'paired_at': DateTime.utc(2026, 9, 25, 10).millisecondsSinceEpoch,
          },
          {
            'mobile_id': 'm2',
            'public_key': base64UrlNoPad(Uint8List(16)), // Wrong length
            'name': 'Invalid',
            'paired_at': DateTime.utc(2026, 9, 25, 10).millisecondsSinceEpoch,
          },
        ]),
      );
      final store = TrustedStore(kv);
      final devices = await store.list();
      expect(devices, hasLength(1));
      expect(devices.first.mobileId, 'm1');
    },
  );

  test('TrustedDevice copies the public key on construction', () {
    final original = Uint8List.fromList(List.filled(32, 42));
    final device = TrustedDevice(
      mobileId: 'm1',
      publicKey: original,
      name: 'Phone',
      pairedAt: DateTime.utc(2026, 9, 25, 10),
    );
    original[0] = 99; // Mutate the original.
    expect(device.publicKey[0], 42); // Device's copy should be unchanged.
  });

  group('unregistered pairings', () {
    test('add(unregistered: true) marks the phone; markRegistered clears it '
        'and reports whether it was pending', () async {
      final store = TrustedStore(InMemoryKeyValueStore());
      await store.add(device('m1', 1), unregistered: true);
      await store.add(device('m2', 2));
      expect(await store.unregistered(), {'m1'});
      expect(await store.find('m1'), isNotNull);

      expect(await store.markRegistered('m1'), isTrue);
      expect(await store.markRegistered('m1'), isFalse);
      expect(await store.unregistered(), isEmpty);
      expect(await store.find('m1'), isNotNull); // Trust is untouched.
    });

    test('persist as a JSON array under pending_pairing_posts', () async {
      final kv = InMemoryKeyValueStore();
      await TrustedStore(kv).add(device('m1', 1), unregistered: true);
      expect(TrustedStore.unregisteredKey, 'pending_pairing_posts');
      expect(jsonDecode(kv.values[TrustedStore.unregisteredKey]!), ['m1']);
      expect(await TrustedStore(kv).unregistered(), {'m1'});
    });

    test('remove and clear drop pending entries too', () async {
      final store = TrustedStore(InMemoryKeyValueStore());
      await store.add(device('m1', 1), unregistered: true);
      await store.add(device('m2', 2), unregistered: true);
      await store.remove('m1');
      expect(await store.unregistered(), {'m2'});
      await store.clear();
      expect(await store.unregistered(), isEmpty);
      expect(await store.list(), isEmpty);
    });

    test('corrupt pending data counts as nothing pending', () async {
      final kv = InMemoryKeyValueStore();
      await kv.write(TrustedStore.unregisteredKey, '{not json');
      expect(await TrustedStore(kv).unregistered(), isEmpty);
    });
  });

  test('removing a phone that is not trusted writes nothing and fires no '
      'change', () async {
    final kv = CountingStore();
    final store = TrustedStore(kv);
    await store.add(device('m1', 1));
    var changes = 0;
    store.changes.listen((_) => changes++);
    final writes = kv.writes;

    await store.remove('m9');
    await pumpEventQueue();
    expect(kv.writes, writes);
    expect(changes, 0);

    await store.remove('m1');
    await pumpEventQueue();
    expect(kv.writes, greaterThan(writes));
    expect(changes, 1);
  });
}

/// Counts writes to an in-memory store.
final class CountingStore implements KeyValueStore {
  final _inner = InMemoryKeyValueStore();
  int writes = 0;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) {
    writes++;
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    writes++;
    return _inner.delete(key);
  }
}
