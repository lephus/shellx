import 'dart:io';
import 'dart:math';

/// A file with its size, for the copy's "already there and the same" check.
typedef FileEntry = ({String path, int length});

/// The file operations the runtime copy needs (a fake in tests).
abstract interface class FileOps {
  Future<bool> directoryExists(String path);

  /// Every file under [directory], recursively; empty when it is missing.
  Future<List<FileEntry>> files(String directory);

  /// The immediate subdirectories of [directory] (full paths); empty when it
  /// is missing.
  Future<List<String>> subdirectories(String directory);
  Future<void> createDirectory(String path);
  Future<void> copyFile(String from, String to);

  /// Renames a directory; throws when [to] exists.
  Future<void> renameDirectory(String from, String to);

  /// Throws when something in it is in use.
  Future<void> deleteDirectory(String path);

  /// Throws when the file is in use (a running exe); a missing file is not
  /// an error.
  Future<void> deleteFile(String path);

  /// Null when [path] is missing.
  Future<DateTime?> modified(String path);
}

final class RealFileOps implements FileOps {
  const RealFileOps();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<List<FileEntry>> files(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list(recursive: true, followLinks: false))
        if (e is File) (path: e.path, length: await e.length()),
    ];
  }

  @override
  Future<List<String>> subdirectories(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list(followLinks: false))
        if (e is Directory) e.path,
    ];
  }

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);

  @override
  Future<void> copyFile(String from, String to) => File(from).copy(to);

  @override
  Future<void> renameDirectory(String from, String to) =>
      Directory(from).rename(to);

  @override
  Future<void> deleteDirectory(String path) =>
      Directory(path).delete(recursive: true);

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<DateTime?> modified(String path) async {
    try {
      return (await Directory(path).stat()).modified;
    } on FileSystemException {
      return null;
    }
  }
}

const _sep = r'\';

String _runtimesDirectory(String localAppData) =>
    '$localAppData${_sep}ShellX${_sep}mux';

/// A version directory (`1.6.0`) or a half-copied one (`1.6.0.tmp-…`).
final _runtimeName = RegExp(r'^\d+\.\d+\.\d+');

/// A half-copied directory this old is nobody's work in progress.
const _staleTemp = Duration(minutes: 5);

final _safeVersion = RegExp(r'^[\w.+-]+$');

/// A version goes into a path: nothing that could leave the directory.
void _checkVersion(String version) {
  if (!_safeVersion.hasMatch(version) || version.startsWith('.')) {
    throw ArgumentError.value(version, 'version');
  }
}

/// A5b D3 (Windows): Windows locks a running exe and its dlls, so the
/// daemon runs from a copy: `ShellX.exe` as `shellx-mux.exe`, every `.dll`
/// and `data\**`, in `<localAppData>\ShellX\mux\<version>\`. The Setup can
/// then replace [installDir], and `taskkill /IM ShellX.exe` only hits the
/// UI. Returns the path of `shellx-mux.exe`.
///
/// Copies into a temporary directory and renames it into place, so a copy
/// that died halfway is never taken for a complete one. When the version
/// directory already holds every file with the same size, nothing is copied.
Future<String> prepareWindowsRuntime({
  required String installDir,
  required String localAppData,
  required String version,
  FileOps ops = const RealFileOps(),
  Random? random,
}) async {
  _checkVersion(version);
  final root = _runtimesDirectory(localAppData);
  final target = '$root$_sep$version';
  final exe = '$target${_sep}shellx-mux.exe';

  // What the install directory has to give: destination (relative) → source.
  final wanted = <String, FileEntry>{};
  for (final f in await ops.files(installDir)) {
    final relative = _relative(installDir, f.path);
    if (relative == 'ShellX.exe') {
      wanted['shellx-mux.exe'] = f;
    } else if (!relative.contains(_sep) &&
        relative.toLowerCase().endsWith('.dll')) {
      wanted[relative] = f;
    } else if (relative.startsWith('data$_sep')) {
      wanted[relative] = f;
    }
  }
  if (!wanted.containsKey('shellx-mux.exe')) {
    throw FileSystemException('ShellX.exe is not in the install directory');
  }

  if (await _complete(ops, target, wanted)) return exe;

  final temp =
      '$target.tmp-${(random ?? Random.secure()).nextInt(1 << 32).toRadixString(16)}';
  try {
    await ops.createDirectory(temp);
    final made = <String>{};
    for (final entry in wanted.entries) {
      final destination = '$temp$_sep${entry.key}';
      final parent = destination.substring(0, destination.lastIndexOf(_sep));
      if (made.add(parent)) await ops.createDirectory(parent);
      await ops.copyFile(entry.value.path, destination);
    }
    // A half-copied or outdated directory of this version is replaced.
    if (await ops.directoryExists(target)) {
      try {
        await ops.deleteDirectory(target);
      } on Object {
        // In use: a daemon of this very version runs from it.
      }
    }
    try {
      await ops.renameDirectory(temp, target);
    } on Object {
      // Another start won the rename (or the old one could not go): fine
      // when what is there is complete.
      if (!await _complete(ops, target, wanted)) rethrow;
    }
  } finally {
    try {
      if (await ops.directoryExists(temp)) await ops.deleteDirectory(temp);
    } on Object {
      // Left for the next cleanup.
    }
  }
  return exe;
}

/// A5b D3: at its start the daemon removes every runtime directory but its
/// own. A version directory whose `shellx-mux.exe` cannot be deleted (a
/// daemon still runs from it) is skipped whole, so it is never left without
/// its exe; a `.tmp-` directory goes only when older than five minutes (a
/// start may be copying into it).
Future<void> cleanupOldRuntimes({
  required String localAppData,
  required String keep,
  FileOps ops = const RealFileOps(),
  DateTime Function()? now,
}) async {
  _checkVersion(keep);
  final clock = now ?? DateTime.now;
  final root = _runtimesDirectory(localAppData);
  for (final path in await ops.subdirectories(root)) {
    final name = path.substring(path.lastIndexOf(_sep) + 1);
    if (name == keep || !_runtimeName.hasMatch(name)) continue;
    try {
      if (name.contains('.tmp-')) {
        final at = await ops.modified(path);
        if (at == null || clock().difference(at) < _staleTemp) continue;
      } else {
        await ops.deleteFile('$path${_sep}shellx-mux.exe');
      }
      await ops.deleteDirectory(path);
    } on Object {
      // In use, or already gone.
    }
  }
}

String _relative(String base, String path) =>
    path.length > base.length + 1 && path.startsWith(base)
    ? path.substring(base.length + 1)
    : path;

/// Every wanted file is in [target] with the size of its source.
Future<bool> _complete(
  FileOps ops,
  String target,
  Map<String, FileEntry> wanted,
) async {
  final have = {
    for (final f in await ops.files(target))
      _relative(target, f.path): f.length,
  };
  return wanted.entries.every((e) => have[e.key] == e.value.length);
}
