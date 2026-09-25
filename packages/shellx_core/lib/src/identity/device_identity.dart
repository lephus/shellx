import 'dart:typed_data';

import '../noise/noise_key_pair.dart';
import '../storage/key_value_store.dart';
import '../util/bytes.dart';

abstract final class DeviceIdentity {
  /// Storage key of the base64url (no padding) X25519 private key.
  static const String storageKey = 'device_private_key';

  static final Expando<Future<NoiseKeyPair>> _inFlight = Expando();

  /// Returns the device's static key pair, creating and storing it on first
  /// use. Idempotent: later calls (and concurrent calls on the same [store])
  /// return the same key. A stored value that is not a 32-byte base64url key
  /// is replaced by a new key (the device must then pair again).
  static Future<NoiseKeyPair> loadOrCreate(KeyValueStore store) {
    final pending = _inFlight[store];
    if (pending != null) {
      return pending;
    }
    final future = _loadOrCreate(store);
    _inFlight[store] = future;
    return future.whenComplete(() => _inFlight[store] = null);
  }

  static Future<NoiseKeyPair> _loadOrCreate(KeyValueStore store) async {
    final stored = await store.read(storageKey);
    final existing = stored == null ? null : _decode(stored);
    if (existing != null) {
      return NoiseKeyPair.fromPrivateKey(existing);
    }
    final created = await NoiseKeyPair.generate();
    await store.write(storageKey, base64UrlNoPad(created.privateKey));
    return created;
  }

  static Uint8List? _decode(String stored) {
    try {
      final bytes = fromBase64UrlNoPad(stored);
      return bytes.length == 32 ? bytes : null;
    } on FormatException {
      return null;
    }
  }
}
