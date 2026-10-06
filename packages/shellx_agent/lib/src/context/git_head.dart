import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The git branch of a directory (A2 C2).
abstract interface class GitBranchLookup {
  /// The branch name, a 7-character SHA when HEAD is detached, or null
  /// (not a repo, unreadable). [refresh] forgets what is cached for
  /// [directory] first (a command just ran: `git init`, `git switch`).
  ///
  /// Fails only with a [TimeoutException] when the lookup was too slow (a
  /// slow network mount): the branch is then *unknown*, which a caller
  /// must not mistake for "not a repo" (it keeps what it already shows).
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

/// One running lookup of a directory.
final class _Walk {
  late final Future<String?> result;
}

final _sha = RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$');

/// `ref: refs/heads/<name>` → `<name>`; another `ref: refs/<x>` → `<x>`;
/// a 40/64-hex SHA (detached) → its first 7 characters; else null. At
/// most 200 characters.
String? parseGitHead(String content) {
  final text = content
      .trim()
      .split(RegExp(r'[\r\n]'))
      .first
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim();
  String clip(String s) =>
      String.fromCharCodes(s.runes.take(GitHeadReader.maxBranchLength));
  if (text.startsWith('ref:')) {
    final ref = text.substring(4).trim();
    if (ref.isEmpty) return null;
    const heads = 'refs/heads/';
    if (ref.startsWith(heads)) {
      final name = ref.substring(heads.length);
      return name.isEmpty ? null : clip(name);
    }
    final name = ref.startsWith('refs/') ? ref.substring(5) : ref;
    return name.isEmpty ? null : clip(name);
  }
  return _sha.hasMatch(text) ? text.substring(0, 7) : null;
}

/// Finds `.git` above a directory (a directory, or a `gitdir:` file for
/// worktrees and submodules) and reads its `HEAD` (C2). Only `.git` is
/// stat-ed per level and only two small files are read, so a huge repo
/// costs the same as a tiny one. `directory → git dir` is cached (LRU,
/// [cacheSize]), including "not a repo"; HEAD is read again every time.
/// One lookup per directory runs at a time; one that takes longer than
/// [timeout] (a slow network mount) fails with a [TimeoutException] and
/// finishes in the background.
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
  final _inFlight = <String, _Walk>{};

  @override
  Future<String?> branchFor(String directory, {bool refresh = false}) {
    if (directory.isEmpty) return Future.value();
    final key = _trim(directory);
    if (refresh) _gitDirs.remove(key);
    var walk = refresh ? null : _inFlight[key];
    if (walk == null) {
      final started = walk = _Walk();
      started.result = _resolve(key, started).catchError((Object _) => null);
      _inFlight[key] = started;
      unawaited(
        started.result.whenComplete(() {
          if (identical(_inFlight[key], started)) _inFlight.remove(key);
        }),
      );
    }
    // Each caller waits at most [timeout]; the walk itself stays in flight
    // until it finishes, so a hung mount is walked once, not once per call.
    return walk.result.timeout(timeout);
  }

  Future<String?> _resolve(String directory, _Walk walk) async {
    final String? gitDir;
    if (_gitDirs.containsKey(directory)) {
      gitDir = _gitDirs.remove(directory);
      _gitDirs[directory] = gitDir; // most recently used
    } else {
      gitDir = await _findGitDir(directory);
      // A refresh started a newer walk meanwhile: this answer is stale.
      if (identical(_inFlight[directory], walk)) _remember(directory, gitDir);
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
    final result = _isRoot(parent) ? parent : _trim(parent);
    return result == path ? null : result;
  }
}
