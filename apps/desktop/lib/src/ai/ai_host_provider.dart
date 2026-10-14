import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';

/// The app's one [AiHost] (agents, login environment, checkpoints, crash
/// registry). `main.dart` overrides it (V2-1b Task 11); a test that needs
/// one overrides it too — reading it unset is a programming error.
final aiHostProvider = Provider<AiHost>(
  (ref) => throw StateError('aiHostProvider is set by main.dart'),
);

/// V2-1b final review M-11: how the app asks the system to leave a folder out
/// of its backups (macOS Time Machine: `tmutil addexclusion`). `main.dart`
/// sets it where the system has such a thing; null (the default, and every
/// test) asks for nothing.
final aiBackupExcluderProvider = Provider<Future<void> Function(String path)?>(
  (ref) => null,
);
