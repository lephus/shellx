import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import 'ai_gitignore.dart';
import 'ai_off_thread.dart';
import 'ai_paths.dart' show aiFolderIsBroad;

/// What a file holds, as the AI pane shows it (§4.4).
sealed class AiFileContent {
  const AiFileContent();
}

final class AiFileText extends AiFileContent {
  const AiFileText(this.text);
  final String text;

  @override
  String toString() => '…';
}

/// A NUL byte in its first 8 000 bytes (git's own test): "Binary file".
final class AiFileBinary extends AiFileContent {
  const AiFileBinary();
}

/// Over [kAiFileViewMax]: "Too large to show".
final class AiFileTooLarge extends AiFileContent {
  const AiFileTooLarge();
}

/// Not there: deleted, or added after the restore point.
final class AiFileMissing extends AiFileContent {
  const AiFileMissing();
}

/// The largest file the viewer and the diffs show (1 MiB).
const int kAiFileViewMax = 1 << 20;

/// [bytes] as the pane shows them; null: missing.
AiFileContent aiFileContentOf(List<int>? bytes) {
  if (bytes == null) return const AiFileMissing();
  if (bytes.length > kAiFileViewMax) return const AiFileTooLarge();
  final head = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < head; i++) {
    if (bytes[i] == 0) return const AiFileBinary();
  }
  return AiFileText(utf8.decode(bytes, allowMalformed: true));
}

/// The project's files as the AI pane reads them (the diff of a change, the
/// viewer, the Files tree, `@`). A seam: widget tests never touch the disk
/// under fake async.
abstract interface class AiProjectFiles {
  /// The file at [path] (absolute).
  Future<AiFileContent> read(String path);

  /// D18: folder [dir] of project [root] ('' is the root), as [aiListDir].
  Future<List<AiDirEntry>> list(String root, String dir);

  /// D16: the files `@` offers, as [aiIndexProject].
  Future<List<String>> index(String root);
}

/// The disk; listings and the index run off the UI isolate.
final class DiskProjectFiles implements AiProjectFiles {
  DiskProjectFiles(this._run, {this.home = '', bool? isWindows})
    : _isWindows = isWindows;
  final OffThread _run;

  /// The user's home folder, to tell a folder too broad to be a project.
  final String home;
  final bool? _isWindows;

  @override
  Future<List<AiDirEntry>> list(String root, String dir) =>
      _run(aiListDir, (root, dir));

  /// Final review I-1: the home folder, a folder above it and a disk root
  /// are not walked — a crawl of all of it, with macOS asking for Desktop,
  /// Documents and Downloads on the way. `@` offers nothing there; the
  /// Files panel still lists one folder at a time, as the user opens it.
  @override
  Future<List<String>> index(String root) {
    if (aiFolderIsBroad(root, home: home, isWindows: _isWindows)) {
      return Future.value(const <String>[]);
    }
    return _run(aiIndexProject, root);
  }

  @override
  Future<AiFileContent> read(String path) async {
    try {
      final file = File(path);
      if (await file.length() > kAiFileViewMax) return const AiFileTooLarge();
      return aiFileContentOf(await file.readAsBytes());
    } on FileSystemException {
      return const AiFileMissing();
    }
  }
}

final aiProjectFilesProvider = Provider<AiProjectFiles>(
  (ref) => DiskProjectFiles(
    ref.read(aiOffThreadProvider),
    home: ref.read(homeDirectoryProvider),
  ),
);
