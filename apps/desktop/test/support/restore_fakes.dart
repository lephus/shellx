import 'dart:async';

import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';

/// A [RestoreFiles] that records every call (A5a tests).
final class RecordingFiles implements RestoreFiles {
  final layouts = <RestoreSnapshot>[];
  final scrollbacks = <String, String>{};
  final deleted = <String>[];
  int clears = 0;
  Set<String>? keptOrphans;

  /// What [readScrollback] returns, by key.
  Map<String, String> stored = {};

  /// The time [scrollbackSavedAt] reports for a key in [stored].
  DateTime storedAt = DateTime(2026, 10, 7, 14, 32);

  /// Keys [readScrollback] was asked for, in order.
  final reads = <String>[];

  /// When true, writes fail as on a full disk (nothing recorded).
  bool failLayoutWrites = false;
  bool failScrollbackWrites = false;

  /// When true, [writeLayout] throws (a store that fails unexpectedly).
  bool throwLayoutWrites = false;

  /// When set, [writeLayout] waits for it (a slow disk).
  Completer<void>? layoutGate;

  @override
  Future<bool> prepare() async => true;
  @override
  Future<RestoreLoad> loadLayout() async => RestoreLoad(
    snapshot: diskLayout ? layouts.lastOrNull : null,
    recovered: diskRecovered,
  );

  /// [loadLayout] returns the last layout written, as a disk would.
  bool diskLayout = false;

  /// [loadLayout] says the snapshot came from an earlier generation.
  bool diskRecovered = false;
  @override
  Future<bool> writeLayout(RestoreSnapshot snapshot) async {
    await layoutGate?.future;
    if (throwLayoutWrites) throw StateError('layout write failed');
    if (failLayoutWrites) return false;
    layouts.add(snapshot);
    return true;
  }

  /// When set, [writeScrollbacks] waits for it (a slow disk).
  Completer<void>? scrollbackGate;

  @override
  Future<bool> writeScrollbacks(Map<String, String> textByKey) async {
    await scrollbackGate?.future;
    if (failScrollbackWrites) return false;
    scrollbacks.addAll(textByKey);
    return true;
  }

  /// When set, [readScrollback] throws it.
  Object? readError;

  @override
  Future<String?> readScrollback(String key) async {
    reads.add(key);
    final error = readError;
    if (error != null) throw error;
    return stored[key];
  }

  @override
  Future<DateTime?> scrollbackSavedAt(String key) async =>
      stored.containsKey(key) ? storedAt : null;
  @override
  Future<void> deleteScrollback(String key) async {
    deleted.add(key);
    scrollbacks.remove(key);
  }

  @override
  Future<void> deleteAllScrollback() async {
    clears++;
    scrollbacks.clear();
  }

  @override
  Future<bool> hasScrollback() async => scrollbacks.isNotEmpty;
  @override
  Future<void> removeOrphans(Set<String> keep) async => keptOrphans = keep;
}
