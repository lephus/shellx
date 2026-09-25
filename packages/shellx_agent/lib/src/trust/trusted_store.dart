import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A phone this agent trusts (spec §5.3 step 5).
final class TrustedDevice {
  const TrustedDevice({
    required this.mobileId,
    required this.publicKey,
    required this.name,
    required this.pairedAt,
  });

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

  static TrustedDevice fromJson(Map<String, Object?> json) => TrustedDevice(
    mobileId: json['mobile_id'] as String,
    publicKey: fromBase64UrlNoPad(json['public_key'] as String),
    name: json['name'] as String,
    pairedAt: DateTime.fromMillisecondsSinceEpoch(
      json['paired_at'] as int,
      isUtc: true,
    ),
  );
}

/// Local trust list — the only source of truth for trust (spec §5.4).
/// Stored as a JSON array under [storageKey]. Unreadable data counts as
/// "no trusted devices" (fail closed).
final class TrustedStore {
  TrustedStore(KeyValueStore store) : _store = store;

  static const String storageKey = 'trusted_devices';

  final KeyValueStore _store;
  final _changes = StreamController<void>.broadcast();
  Future<void> _lock = Future.value();

  Stream<void> get changes => _changes.stream;

  Future<List<TrustedDevice>> list() => _read();

  Future<TrustedDevice?> find(String mobileId) async {
    for (final device in await _read()) {
      if (device.mobileId == mobileId) return device;
    }
    return null;
  }

  /// Adds [device], replacing an entry with the same mobileId.
  Future<void> add(TrustedDevice device) => _mutate(
    (devices) => [
      ...devices.where((d) => d.mobileId != device.mobileId),
      device,
    ],
  );

  Future<void> remove(String mobileId) => _mutate(
    (devices) => devices.where((d) => d.mobileId != mobileId).toList(),
  );

  Future<void> clear() => _mutate((_) => const []);

  Future<List<TrustedDevice>> _read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return [
        for (final entry in decoded)
          TrustedDevice.fromJson((entry as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _mutate(
    List<TrustedDevice> Function(List<TrustedDevice> devices) change,
  ) {
    final next = _lock.then((_) async {
      final updated = change(await _read());
      await _store.write(
        storageKey,
        jsonEncode([for (final d in updated) d.toJson()]),
      );
      _changes.add(null);
    });
    _lock = next.catchError((Object _) {});
    return next;
  }
}
