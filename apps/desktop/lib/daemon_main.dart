import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'src/mux/mux_paths.dart';

/// The `shellx-mux` entry point (A5b D2/D3): started by the native runner
/// on a headless engine, never through `main()`, so it takes no arguments.
/// Task 1 stub: proves the engine, plugins and process lifetime by writing
/// `<mux dir>/heartbeat` every 2 s; Task 7 replaces the body.
@pragma('vm:entry-point')
Future<void> daemonMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = Directory(
    muxDirectoryPath(
      windows: Platform.isWindows,
      environment: Platform.environment,
    ),
  );
  await directory.create(recursive: true);
  // The mux dir is owner-only (A5b D5); the default umask may leave 0755.
  if (!Platform.isWindows) {
    await Process.run('chmod', ['700', directory.path]);
  }
  final beat = File('${directory.path}${Platform.pathSeparator}heartbeat');
  // Only the pid; the file's mtime is the liveness signal.
  void write() => beat.writeAsStringSync('$pid');
  write();
  Timer.periodic(const Duration(seconds: 2), (_) => write());
}
