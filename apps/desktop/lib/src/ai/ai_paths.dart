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
