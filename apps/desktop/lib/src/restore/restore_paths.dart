/// D2: macOS `<app support>/restore`; Windows `%LOCALAPPDATA%\ShellX\restore`
/// — never Roaming `%APPDATA%` (domain roaming profiles sync it).
String restoreDirectoryPath({
  required bool windows,
  required Map<String, String> environment,
  required String appSupportPath,
}) {
  if (!windows) return '$appSupportPath/restore';
  final local = environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) {
    throw StateError('LOCALAPPDATA is not set');
  }
  return '$local\\ShellX\\restore';
}
