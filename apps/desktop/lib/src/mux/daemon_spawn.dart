import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_runtime_copy.dart';

typedef SpawnStart =
    Future<void> Function(String exe, List<String> args, ProcessStartMode mode);

typedef PrepareRuntime =
    Future<String> Function({
      required String installDir,
      required String localAppData,
      required String version,
    });

/// A5b D3: starts the background service, detached from this process: the
/// UI quitting (or being killed) must not end it, and its shells never
/// belong to the UI's process group or job.
///
/// macOS: this very binary with `--daemon` (the native runner starts the
/// headless engine, no Dock icon). Windows: `shellx-mux.exe`, a copy of the
/// install made by [prepareWindowsRuntime] so the Setup can replace the
/// installed files while the service runs. A failed start throws; the
/// launcher then waits and reports `StartFailed`.
Future<void> spawnDaemon({
  bool? windows,
  String? executable,
  String? localAppData,
  String? version,
  PrepareRuntime? prepareRuntime,
  SpawnStart? start,
}) async {
  final isWindows = windows ?? Platform.isWindows;
  final self = executable ?? Platform.resolvedExecutable;
  var exe = self;
  if (isWindows) {
    final local = localAppData ?? Platform.environment['LOCALAPPDATA'];
    if (local == null || version == null) {
      throw StateError('no place for the runtime copy');
    }
    exe = await (prepareRuntime ?? _prepare)(
      installDir: p.windows.dirname(self),
      localAppData: local,
      version: version,
    );
  }
  final starter = start ?? _defaultStart;
  await starter(exe, const ['--daemon'], ProcessStartMode.detached);
}

Future<String> _prepare({
  required String installDir,
  required String localAppData,
  required String version,
}) => prepareWindowsRuntime(
  installDir: installDir,
  localAppData: localAppData,
  version: version,
);

Future<void> _defaultStart(
  String exe,
  List<String> args,
  ProcessStartMode mode,
) async {
  await Process.start(exe, args, mode: mode);
}
