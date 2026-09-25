import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A machine whose static key this phone pinned when pairing (spec §5.3
/// step 6).
final class PinnedMachine {
  const PinnedMachine({
    required this.agentId,
    required this.publicKey,
    required this.pairedAt,
  });

  final String agentId;
  final Uint8List publicKey;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
    'agent_id': agentId,
    'public_key': base64UrlNoPad(publicKey),
    'paired_at': pairedAt.millisecondsSinceEpoch,
  };

  static PinnedMachine fromJson(Map<String, Object?> json) => PinnedMachine(
    agentId: json['agent_id'] as String,
    publicKey: fromBase64UrlNoPad(json['public_key'] as String),
    pairedAt: DateTime.fromMillisecondsSinceEpoch(
      json['paired_at'] as int,
      isUtc: true,
    ),
  );
}

/// Pinned machines of one account, stored as a JSON array under
/// `pinned_machines_<userId>` so another account on the same phone never
/// sees them (spec §5.2).
final class PinnedStore {
  PinnedStore(KeyValueStore store, {required String userId})
    : _store = store,
      _key = 'pinned_machines_$userId';

  final KeyValueStore _store;
  final String _key;
  Future<void> _lock = Future.value();

  Future<List<PinnedMachine>> list() => _read();

  Future<PinnedMachine?> find(String agentId) async {
    for (final machine in await _read()) {
      if (machine.agentId == agentId) return machine;
    }
    return null;
  }

  /// Adds [machine], replacing an entry with the same agentId.
  Future<void> add(PinnedMachine machine) => _mutate(
    (machines) => [
      ...machines.where((m) => m.agentId != machine.agentId),
      machine,
    ],
  );

  Future<void> remove(String agentId) => _mutate(
    (machines) => machines.where((m) => m.agentId != agentId).toList(),
  );

  Future<List<PinnedMachine>> _read() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return [
        for (final entry in decoded)
          PinnedMachine.fromJson((entry as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _mutate(
    List<PinnedMachine> Function(List<PinnedMachine> machines) change,
  ) {
    final next = _lock.then((_) async {
      final updated = change(await _read());
      await _store.write(
        _key,
        jsonEncode([for (final m in updated) m.toJson()]),
      );
    });
    _lock = next.catchError((Object _) {});
    return next;
  }
}
