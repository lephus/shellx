import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/backend/backend.dart';

/// A machine whose unpair failed after `shellx_client` had already forgotten its pin; [name] is
/// the name last known for it (null when it was never known).
typedef PendingUnpair = ({String agentId, String? name});

/// Spec §5.5: unpairing also deletes the pairing on the relay, but `ClientService.unpair` forgets
/// the pin before that DELETE, which can still fail (offline, 5xx). Without a record the machine
/// would vanish from the app while the computer keeps trusting the phone.
///
/// The record is kept per account in secure storage (`pending_unpairs_<userId>`, a JSON list of
/// `{agentId, name}`) until an unpair of that machine succeeds: Settings lists the entries as
/// failed rows with a retry, and every start of a backend retries them once ([retry]).
///
/// Updates are serialised, so a retry running at sign-in and an unpair in Settings never lose
/// each other's changes. Nothing here logs an id.
@lazySingleton
class PendingUnpairs {
  PendingUnpairs(this._store);

  final KeyValueStore _store;

  /// The end of the last update still running; null when none runs (a chain is only started on
  /// demand, in the zone of the call that needs it).
  Future<void>? _last;

  static String storageKey(String userId) => 'pending_unpairs_$userId';

  /// The machines of [userId] whose unpair is still pending; an unreadable record reads as none.
  Future<List<PendingUnpair>> load(String userId) => _serialized(() => _read(userId));

  /// Remembers that unpairing [agentId] failed (again).
  Future<void> add(String userId, String agentId, String? name) => _serialized(() async {
    final entries = await _read(userId);
    final previous = entries.where((entry) => entry.agentId == agentId).firstOrNull;
    await _write(userId, [
      for (final entry in entries)
        if (entry.agentId != agentId) entry,
      (agentId: agentId, name: name ?? previous?.name),
    ]);
  });

  /// [agentId] is unpaired, or paired again: nothing is pending for it any more.
  Future<void> remove(String userId, String agentId) => _serialized(() async {
    final entries = await _read(userId);
    if (!entries.any((entry) => entry.agentId == agentId)) return;
    await _write(userId, [
      for (final entry in entries)
        if (entry.agentId != agentId) entry,
    ]);
  });

  /// Tries every pending unpair of [userId] once, best effort: a success drops the entry, a
  /// failure keeps it for the next start or for Settings. A machine that is pinned again was
  /// paired again since, and is only dropped from the record — the pairing on the relay is the new
  /// one, which a DELETE would remove. Never throws.
  Future<void> retry(String userId, ShellxBackend backend) async {
    try {
      final pending = await load(userId);
      if (pending.isEmpty) return;
      final pinned = {for (final pin in await backend.pinnedMachines()) pin.agentId};
      for (final entry in pending) {
        if (!pinned.contains(entry.agentId)) {
          try {
            await backend.unpair(entry.agentId);
          } catch (error) {
            _log('unpair', error);
            continue;
          }
        }
        await remove(userId, entry.agentId);
      }
    } catch (error) {
      _log('retry', error);
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _last;
    final result = previous == null ? Future.sync(action) : previous.then((_) => action());
    late final Future<void> done;
    done = result.then<void>(
      (_) {
        if (identical(_last, done)) _last = null;
      },
      onError: (Object _) {
        if (identical(_last, done)) _last = null;
      },
    );
    _last = done;
    return result;
  }

  Future<List<PendingUnpair>> _read(String userId) async {
    final raw = await _store.read(storageKey(userId));
    if (raw == null) return [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<Object?>)
          if (item case {'agentId': final String agentId, 'name': final String? name}) (agentId: agentId, name: name),
      ];
    } on Object catch (error) {
      // A damaged record: nothing can be retried from it.
      _log('read', error);
      return [];
    }
  }

  Future<void> _write(String userId, List<PendingUnpair> entries) {
    final key = storageKey(userId);
    if (entries.isEmpty) return _store.delete(key);
    return _store.write(
      key,
      jsonEncode([
        for (final entry in entries) {'agentId': entry.agentId, 'name': entry.name},
      ]),
    );
  }

  /// Only the step and the error type: never an id.
  static void _log(String step, Object error) {
    if (kDebugMode) debugPrint('PendingUnpairs $step error: ${error.runtimeType}');
  }
}
