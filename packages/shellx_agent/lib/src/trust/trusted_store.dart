import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A phone this agent trusts (spec §5.3 step 5).
final class TrustedDevice {
  TrustedDevice({
    required this.mobileId,
    required Uint8List publicKey,
    required this.name,
    required this.pairedAt,
  }) : publicKey = Uint8List.fromList(publicKey);

  final String mobileId;
  final Uint8List publicKey;
  final String name;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
    'mobile_id': mobileId,
    'public_key': base64UrlNoPad(publicKey),
    'name': name,
    'paired_at': pairedAt.millisecondsSinceEpoch,
  };

  static TrustedDevice fromJson(Map<String, Object?> json) {
    final publicKey = fromBase64UrlNoPad(json['public_key'] as String);
    if (publicKey.length != 32) {
      throw FormatException('Public key must be exactly 32 bytes');
    }
    return TrustedDevice(
      mobileId: json['mobile_id'] as String,
      publicKey: publicKey,
      name: json['name'] as String,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(
        json['paired_at'] as int,
        isUtc: true,
      ),
    );
  }
}

/// Local trust list — the only source of truth for trust (spec §5.4).
/// Stored as a JSON array under [storageKey]. Unreadable data counts as
/// "no trusted devices" (fail closed).
///
/// Also keeps, under [unregisteredKey], the ids of phones paired here whose
/// `POST /v1/pairings` the relay has not acknowledged yet ("unregistered").
/// Until it has, the relay may still replay a `pairing_removed` tombstone
/// from an earlier unpair of that phone, which must not undo the new trust.
/// Unreadable data counts as "nothing unregistered".
///
/// **Important:** Create one shared instance per underlying [KeyValueStore]
/// instance. The mutation lock is per [TrustedStore] instance.
final class TrustedStore {
  TrustedStore(KeyValueStore store) : _store = store;

  static const String storageKey = 'trusted_devices';
  static const String unregisteredKey = 'pending_pairing_posts';

  final KeyValueStore _store;
  final _changes = StreamController<void>.broadcast();
  Future<void> _lock = Future.value();

  /// Fires whenever the trust list itself changes.
  Stream<void> get changes => _changes.stream;

  Future<List<TrustedDevice>> list() => _read();

  Future<TrustedDevice?> find(String mobileId) async {
    for (final device in await _read()) {
      if (device.mobileId == mobileId) return device;
    }
    return null;
  }

  /// Adds [device], replacing an entry with the same mobileId. With
  /// [unregistered], the phone is first marked unregistered (before the
  /// trust entry is written, so the new trust is never unprotected).
  Future<void> add(TrustedDevice device, {bool unregistered = false}) =>
      _locked(() async {
        if (unregistered) {
          final pending = await _readUnregistered();
          if (pending.add(device.mobileId)) {
            await _writeUnregistered(pending);
          }
        }
        final devices = await _read();
        await _writeDevices([
          ...devices.where((d) => d.mobileId != device.mobileId),
          device,
        ]);
        _changes.add(null);
      });

  /// Removes [mobileId] and its unregistered mark. Removing a phone that is
  /// not trusted writes nothing (the relay replays `pairing_removed`).
  Future<void> remove(String mobileId) => _locked(() async {
    final devices = await _read();
    if (devices.any((d) => d.mobileId == mobileId)) {
      await _writeDevices(
        devices.where((d) => d.mobileId != mobileId).toList(),
      );
      _changes.add(null);
    }
    final pending = await _readUnregistered();
    if (pending.remove(mobileId)) await _writeUnregistered(pending);
  });

  Future<void> clear() => _locked(() async {
    await _writeDevices(const []);
    await _store.delete(unregisteredKey);
    _changes.add(null);
  });

  /// Phones paired here whose `POST /v1/pairings` is not acknowledged yet.
  Future<Set<String>> unregistered() => _readUnregistered();

  /// The relay acknowledged (or refused) [mobileId]'s pairing record.
  /// Returns false when it was not marked unregistered.
  Future<bool> markRegistered(String mobileId) => _locked(() async {
    final pending = await _readUnregistered();
    if (!pending.remove(mobileId)) return false;
    await _writeUnregistered(pending);
    return true;
  });

  Future<List<TrustedDevice>> _read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      final devices = <TrustedDevice>[];
      for (final entry in decoded) {
        try {
          devices.add(
            TrustedDevice.fromJson((entry as Map).cast<String, Object?>()),
          );
        } catch (_) {
          // Skip corrupt entries (e.g., wrong key length).
        }
      }
      return devices;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeDevices(List<TrustedDevice> devices) => _store.write(
    storageKey,
    jsonEncode([for (final d in devices) d.toJson()]),
  );

  Future<Set<String>> _readUnregistered() async {
    final raw = await _store.read(unregisteredKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return {...(jsonDecode(raw) as List<Object?>).cast<String>()};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _writeUnregistered(Set<String> ids) =>
      _store.write(unregisteredKey, jsonEncode(ids.toList()));

  /// Runs [body] after every earlier mutation; a failure does not block the
  /// next one.
  Future<T> _locked<T>(Future<T> Function() body) {
    final next = _lock.then((_) => body());
    _lock = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
