import 'dart:io';

/// Asks Time Machine to leave [path] out of backups (macOS only; the one
/// helper for the restore folder and the pasted images).
Future<void> excludeFromBackupMacOS(String path) async {
  await Process.run('/usr/bin/tmutil', ['addexclusion', path]);
}
