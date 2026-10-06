import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The git branch of a directory (A2 C2). Never throws.
abstract interface class GitBranchLookup {
  /// The branch name, a 7-character SHA when HEAD is detached, or null
  /// (not a repo, unreadable, too slow). [refresh] forgets what is cached
  /// for [directory] first (a command just ran: `git init`, `git switch`).
  Future<String?> branchFor(String directory, {bool refresh = false});
}

enum GitEntry { none, file, directory }

/// The file-system calls [GitHeadReader] makes (faked in tests).
abstract interface class GitFiles {
  /// What [path] is; [GitEntry.none] when it is missing or not readable.
  Future<GitEntry> entry(String path);

  /// At most [limit] bytes of [path] as text. Throws [FileSystemException].
  Future<String> readSmall(String path, int limit);
}

final class IoGitFiles implements GitFiles {
  const IoGitFiles();

  @override
  Future<GitEntry> entry(String path) async =>
      switch (await FileSystemEntity.type(path)) {
        FileSystemEntityType.directory => GitEntry.directory,
        FileSystemEntityType.file => GitEntry.file,
        _ => GitEntry.none,
      };

  @override
  Future<String> readSmall(String path, int limit) async {
    final file = await File(path).open();
    try {
      return utf8.decode(await file.read(limit), allowMalformed: true);
    } finally {
      await file.close();
    }
  }
}

final _sha = RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$');

/// `ref: refs/heads/<name>` → `<name>`; another `ref: refs/<x>` → `<x>`;
/// a 40/64-hex SHA (detached) → its first 7 characters; else null. At
/// most 200 characters.
String? parseGitHead(String content) {
  final text = content.trim();
  String clip(String s) =>
      String.fromCharCodes(s.runes.take(GitHeadReader.maxBranchLength));
  if (text.startsWith('ref:')) {
    final ref = text.substring(4).trim();
    if (ref.isEmpty) return null;
    const heads = 'refs/heads/';
    if (ref.startsWith(heads)) return clip(ref.substring(heads.length));
    return clip(ref.startsWith('refs/') ? ref.substring(5) : ref);
  }
  return _sha.hasMatch(text) ? text.substring(0, 7) : null;
}

/// Finds `.git` above a directory (a directory, or a `gitdir:` file for
/// worktrees and submodules) and reads its `HEAD` (C2). Only `.git` is
/// stat-ed per level and only two small files are read, so a huge repo
/// costs the same as a tiny one. `directory → git dir` is cached (LRU,
/// [cacheSize]), including "not a repo"; HEAD is read again every time.
/// One lookup per directory runs at a time; one that takes longer than
/// [timeout] (a slow network mount) answers null and finishes in the
/// background.
final class GitHeadReader implements GitBranchLookup {
  GitHeadReader({
    GitFiles files = const IoGitFiles(),
    this.timeout = const Duration(milliseconds: 500),
    this.maxDepth = 64,
    this.cacheSize = 64,
    bool? windows,
  }) : _files = files,
       _windows = windows ?? Platform.isWindows;

  static const int maxFileBytes = 4096;
  static const int maxBranchLength = 200;

  final GitFiles _files;
  final Duration timeout;
  final int maxDepth;
  final int cacheSize;
  final bool _windows;

  /// A map literal keeps insertion order: the first key is the least
  /// recently used.
  final _gitDirs = <String, String?>{};
  final _inFlight = <String, Future<String?>>{};

  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) {
    if (refresh) _gitDirs.remove(directory);
    final running = _inFlight[directory];
    if (running != null && !refresh) return running;
    final lookup = _resolve(
      directory,
    ).timeout(timeout, onTimeout: () => null).catchError((Object _) => null);
    _inFlight[directory] = lookup;
    unawaited(
      lookup.whenComplete(() {
        if (identical(_inFlight[directory], lookup)) {
          _inFlight.remove(directory);
        }
      }),
    );
    return lookup;
  }

  Future<String?> _resolve(String directory) async {
    final String? gitDir;
    if (_gitDirs.containsKey(directory)) {
      gitDir = _gitDirs.remove(directory);
      _gitDirs[directory] = gitDir; // most recently used
    } else {
      gitDir = await _findGitDir(directory);
      _remember(directory, gitDir);
    }
    if (gitDir == null) return null;
    try {
      return parseGitHead(
        await _files.readSmall(_join(gitDir, 'HEAD'), maxFileBytes),
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _findGitDir(String directory) async {
    var current = _trim(directory);
    for (var depth = 0; depth < maxDepth; depth++) {
      final dotGit = _join(current, '.git');
      switch (await _files.entry(dotGit)) {
        case GitEntry.directory:
          return dotGit;
        case GitEntry.file:
          return _followGitFile(dotGit, current);
        case GitEntry.none:
          break;
      }
      final parent = _parent(current);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  /// A worktree's or submodule's `.git` file: `gitdir: <path>`, relative
  /// to the directory that holds the file.
  Future<String?> _followGitFile(String dotGit, String holder) async {
    final String text;
    try {
      text = await _files.readSmall(dotGit, maxFileBytes);
    } on FileSystemException {
      return null;
    }
    final line = const LineSplitter().convert(text).firstOrNull?.trim() ?? '';
    const prefix = 'gitdir:';
    if (!line.startsWith(prefix)) return null;
    final target = line.substring(prefix.length).trim();
    if (target.isEmpty) return null;
    return _isAbsolute(target) ? target : _join(holder, target);
  }

  void _remember(String directory, String? gitDir) {
    _gitDirs.remove(directory);
    _gitDirs[directory] = gitDir;
    while (_gitDirs.length > cacheSize) {
      _gitDirs.remove(_gitDirs.keys.first);
    }
  }

  bool _isSep(String c) => c == '/' || (_windows && c == r'\');

  String _join(String dir, String name) => _isSep(dir[dir.length - 1])
      ? '$dir$name'
      : '$dir${_windows ? r'\' : '/'}$name';

  static final _windowsAbsolute = RegExp(r'^([A-Za-z]:[\\/]|[\\/]{2})');
  static final _driveRoot = RegExp(r'^[A-Za-z]:[\\/]?$');
  static final _uncRoot = RegExp(r'^[\\/]{2}[^\\/]+[\\/][^\\/]+[\\/]?$');

  bool _isAbsolute(String path) => _windows
      ? _windowsAbsolute.hasMatch(path) || path.startsWith('/')
      : path.startsWith('/');

  bool _isRoot(String path) => _windows
      ? _driveRoot.hasMatch(path) || _uncRoot.hasMatch(path)
      : path == '/';

  String _trim(String path) {
    var p = path;
    while (p.length > 1 && _isSep(p[p.length - 1]) && !_isRoot(p)) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// The parent directory; null at a root (`/`, `C:\`, `\\server\share`).
  String? _parent(String path) {
    if (_isRoot(path)) return null;
    var end = path.length;
    while (end > 0 && !_isSep(path[end - 1])) {
      end--;
    }
    if (end == 0) return null;
    final parent = path.substring(0, end); // with its trailing separator
    return _isRoot(parent) ? parent : _trim(parent);
  }
}
