import 'dart:io' show Platform;

import 'package:shellx_ai/host.dart' show isBroadFolder;

/// V2-1 D6, D12: the folder the AI host keeps its data under — `<it>/ai`
/// holds the agents' npm adapters (hundreds of MB), the restore points'
/// repositories and `running.json`.
///
/// macOS: the app support folder. Windows: `%LOCALAPPDATA%\ShellX`, like the
/// restore files (`restoreDirectoryPath`), never `getApplicationSupportDirectory`
/// there — that is Roaming `%APPDATA%`, which a domain roaming profile syncs.
/// Without `LOCALAPPDATA` the app support folder is used (the AI tab works,
/// its data may roam).
String aiSupportDirectoryPath({
  required bool windows,
  required Map<String, String> environment,
  required String appSupportPath,
}) {
  if (!windows) return appSupportPath;
  final local = environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) return appSupportPath;
  return '$local\\ShellX';
}

/// V2-1b final review I-1: whether [folder] is too broad to be a project —
/// the home folder, a folder above it or a disk root, by this computer's
/// rules. Undo snapshots and the `@` index would crawl all of it (and macOS
/// asks for Desktop, Documents and Downloads on the way), so "New AI
/// session" never takes such a folder from the tab in front and `@` never
/// walks one. [home] is the user's home (`HOME`, `USERPROFILE`); empty: only
/// disk roots count. [isWindows] is a test's way to pick the rules.
bool aiFolderIsBroad(String folder, {required String home, bool? isWindows}) =>
    isBroadFolder(
      folder,
      home: home,
      isWindows: isWindows ?? Platform.isWindows,
    );
