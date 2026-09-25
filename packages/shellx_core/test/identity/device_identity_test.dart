import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

/// Counts writes so tests can prove a key is generated only once.
final class _CountingStore implements KeyValueStore {
  final inner = InMemoryKeyValueStore();
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(Duration.zero);
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writes++;
    return inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => inner.delete(key);
}

void main() {
  group('InMemoryKeyValueStore', () {
    test('read, write, overwrite, delete', () async {
      final store = InMemoryKeyValueStore({'a': '1'});
      expect(await store.read('a'), '1');
      expect(await store.read('missing'), isNull);
      await store.write('a', '2');
      expect(await store.read('a'), '2');
      await store.delete('a');
      expect(await store.read('a'), isNull);
      await store.delete('never-existed');
      expect(store.values, isEmpty);
    });

    test('does not share the initial map', () async {
      final seed = {'k': 'v'};
      final store = InMemoryKeyValueStore(seed);
      await store.write('k', 'changed');
      expect(seed['k'], 'v');
    });
  });

  group('DeviceIdentity.loadOrCreate', () {
    test(
      'creates a key and stores the private key as base64url without padding',
      () async {
        final store = InMemoryKeyValueStore();
        final keys = await DeviceIdentity.loadOrCreate(store);
        expect(DeviceIdentity.storageKey, 'device_private_key');
        final stored = store.values['device_private_key']!;
        expect(stored, hasLength(43));
        expect(stored, isNot(contains('=')));
        expect(fromBase64UrlNoPad(stored), keys.privateKey);
      },
    );

    test('is idempotent', () async {
      final store = InMemoryKeyValueStore();
      final first = await DeviceIdentity.loadOrCreate(store);
      final second = await DeviceIdentity.loadOrCreate(store);
      expect(second.publicKey, first.publicKey);
      expect(second.privateKey, first.privateKey);
    });

    test('loads an existing key without rewriting it', () async {
      final existing = await NoiseKeyPair.generate();
      final store = _CountingStore();
      await store.inner.write(
        'device_private_key',
        base64UrlNoPad(existing.privateKey),
      );
      final loaded = await DeviceIdentity.loadOrCreate(store);
      expect(loaded.publicKey, existing.publicKey);
      expect(store.writes, 0);
    });

    test('concurrent first calls generate a single key', () async {
      final store = _CountingStore();
      final results = await Future.wait([
        DeviceIdentity.loadOrCreate(store),
        DeviceIdentity.loadOrCreate(store),
        DeviceIdentity.loadOrCreate(store),
      ]);
      expect(store.writes, 1);
      expect(results[1].publicKey, results[0].publicKey);
      expect(results[2].publicKey, results[0].publicKey);
    });

    test('replaces a corrupted stored key instead of crashing', () async {
      for (final corrupted in ['not base64!', base64UrlNoPad(Uint8List(16))]) {
        final store = InMemoryKeyValueStore({'device_private_key': corrupted});
        final keys = await DeviceIdentity.loadOrCreate(store);
        expect(keys.privateKey, hasLength(32));
        expect(
          fromBase64UrlNoPad(store.values['device_private_key']!),
          keys.privateKey,
        );
      }
    });
  });
}
