import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import '../model/changes.dart';
import 'git_locator.dart';
import 'git_runner.dart';
import 'login_shell_env.dart';
import 'serial_queue.dart';

/// Files bigger than this are not checkpointed (ruling R4).
const kMaxCheckpointFileBytes = 50 * 1024 * 1024;

/// A `.gitignore` line for exactly [relPath] (a folder when it ends with
/// `/`): anchored at the root, special characters escaped.
String excludePattern(String relPath) {
  final b = StringBuffer('/');
  for (final ch in relPath.split('')) {
    if (r'\*?[!#'.contains(ch)) b.write(r'\');
    b.write(ch);
  }
  var s = b.toString();
  var spaces = 0;
  while (s.endsWith(' ')) {
    s = s.substring(0, s.length - 1);
    spaces++;
  }
  return s + r'\ ' * spaces;
}

/// What the runtime needs from checkpoints (a fake in runtime tests).
abstract interface class Checkpoints {
  /// Why undo is off for the project; null when it works.
  UndoOff? get off;

  /// Takes a checkpoint of the project as `refs/shellx/<ref>`; null when
  /// undo is off or the snapshot failed (the turn still runs).
  Future<Checkpoint?> snapshot(String ref);

  /// The project as it is now (a tree); null when undo is off or it fails.
  Future<String?> currentTree();

  /// What changed from [fromTree] to [toTree], or to the project now.
  Future<List<FileChange>> changes(String fromTree, [String? toTree]);

  /// Files that differ between [tree] and the project now.
  Future<Set<String>> changedSince(String tree);

  /// The bytes of [path] in [treeish]; null when it is not there.
  Future<List<int>?> fileAt(String treeish, String path);

  /// Writes [paths] back as they were in [treeish]; a path that was not
  /// there is deleted.
  Future<void> restore(String treeish, Iterable<String> paths);
}

/// Snapshots of one project in a hidden git repository, for undo (spec
/// D12). Never touches the project's own `.git`: every command runs with
/// `GIT_DIR=<gitDir>` and `GIT_WORK_TREE=<project>` ([GitRunner]).
/// Operations run one at a time.
final class CheckpointStore with Redacted implements Checkpoints {
  CheckpointStore({
    required this.project,
    required this.gitDir,
    required GitTool git,
    required Map<String, String> env,
    this.maxFiles = 200000,
    this.firstSnapshotLimit = const Duration(seconds: 30),
    this.maxFileBytes = kMaxCheckpointFileBytes,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _git = GitRunner(
         git: git,
         gitDir: gitDir,
         workTree: project,
         env: env,
         now: now,
       ) {
    _off = _readOff();
  }

  static const _offRetry = Duration(days: 7);
  static const _excludeHeader =
      '# Managed by ShellX: nested repositories and files over 50 MiB are not checkpointed.\n';

  /// How many files one batch of async file system calls covers: the store
  /// runs on the app's UI isolate, and a project can list 200 000 files.
  static const _batch = 256;

  final String project;
  final String gitDir;
  final int maxFiles;
  final Duration firstSnapshotLimit;
  final int maxFileBytes;
  final GitRunner _git;
  final DateTime Function() _now;
  final _queue = SerialQueue();
  UndoOff? _off;
  bool _swept = false;

  /// Why undo is off for this project; null when it works.
  @override
  UndoOff? get off => _off;

  File get _meta => File(p.join(gitDir, 'shellx.json'));

  /// Takes a checkpoint as `refs/shellx/<ref>`. Null when undo is off or
  /// the snapshot failed: the turn still runs (spec §6).
  @override
  Future<Checkpoint?> snapshot(String ref) => _serial(() async {
    if (_off != null) return null;
    final first = !File(p.join(gitDir, 'index')).existsSync();
    final limit = first ? firstSnapshotLimit : const Duration(minutes: 2);
    final clock = Stopwatch()..start();
    Duration left() {
      final l = limit - clock.elapsed;
      return l.isNegative ? Duration.zero : l;
    }

    try {
      await _ensureRepo();
      final untracked = _split(
        await _git.text([
          'ls-files',
          '-z',
          '--others',
          '--exclude-standard',
        ], timeout: left()),
      );
      if (untracked.length > maxFiles) {
        if (first) _setOff(UndoOff.tooManyFiles);
        return null;
      }
      await _exclude(untracked, left());
      await _git.run(['add', '-A'], timeout: left());
      final tree = (await _git.text(['write-tree'])).trim();
      final commit = (await _git.text([
        'commit-tree',
        tree,
        '-m',
        'ShellX checkpoint',
      ])).trim();
      await _git.run(['update-ref', 'refs/shellx/$ref', commit]);
      return Checkpoint(commit: commit, tree: tree);
    } on GitFailed catch (e) {
      if (first) _setOff(e.timedOut ? UndoOff.tooSlow : UndoOff.failed);
      return null;
    } on IOException {
      // The repository cannot be written, or git cannot start.
      if (first) _setOff(UndoOff.failed);
      return null;
    }
  });

  /// The project as it is now (a tree); null when undo is off or it fails.
  @override
  Future<String?> currentTree() => _serial(() async {
    if (_off != null) return null;
    try {
      return await _treeNow();
    } on GitFailed {
      return null;
    } on IOException {
      return null;
    }
  });

  /// What changed from [fromTree] to [toTree], or to the project now.
  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) =>
      _serial(() async {
        final to = toTree ?? await _treeNow();
        final numstat = _split(
          await _git.text([
            'diff-tree',
            '-r',
            '--no-renames',
            '--numstat',
            '-z',
            fromTree,
            to,
          ]),
        );
        final status = _split(
          await _git.text([
            'diff-tree',
            '-r',
            '--no-renames',
            '--name-status',
            '-z',
            fromTree,
            to,
          ]),
        );
        final kinds = <String, ChangeKind>{};
        for (var i = 0; i + 1 < status.length; i += 2) {
          kinds[status[i + 1]] = switch (status[i]) {
            'A' => ChangeKind.added,
            'D' => ChangeKind.deleted,
            _ => ChangeKind.modified,
          };
        }
        return [
          for (final record in numstat)
            if (_numstat(record) case (final added, final removed, final path))
              FileChange(
                path: path,
                kind: kinds[path] ?? ChangeKind.modified,
                added: added,
                removed: removed,
              ),
        ];
      });

  /// Files that differ between [tree] and the project now ("đã sửa sau lượt").
  @override
  Future<Set<String>> changedSince(String tree) => _serial(() async {
    final now = await _treeNow();
    return _split(
      await _git.text([
        'diff-tree',
        '-r',
        '--no-renames',
        '--name-only',
        '-z',
        tree,
        now,
      ]),
    ).toSet();
  });

  /// The bytes of [path] in [treeish]; null when it is not there.
  @override
  Future<List<int>?> fileAt(String treeish, String path) => _serial(() async {
    try {
      return await _git.run(['cat-file', 'blob', '$treeish:$path']);
    } on GitFailed {
      return null;
    }
  });

  /// Writes [paths] back as they were in [treeish], byte for byte. A path
  /// that was not there is deleted, with the folders left empty (R5).
  @override
  Future<void> restore(String treeish, Iterable<String> paths) =>
      _serial(() async {
        final wanted = paths.toSet();
        if (wanted.isEmpty) return;
        final inTree = _split(
          await _git.text(['ls-tree', '-r', '-z', '--name-only', treeish]),
        ).toSet();
        final back = wanted.where(inTree.contains).toList();
        if (back.isNotEmpty) {
          await _git.run([
            'restore',
            '--source=$treeish',
            '--worktree',
            '--pathspec-from-file=-',
            '--pathspec-file-nul',
          ], input: utf8.encode('${back.join('\x00')}\x00'));
        }
        await _deleteNew(wanted.where((w) => !inTree.contains(w)).toList());
      });

  /// Drops checkpoints older than [olderThan] and the data only they kept;
  /// returns how many were dropped.
  Future<int> prune(Duration olderThan) => _serial(() async {
    if (!File(p.join(gitDir, 'HEAD')).existsSync()) return 0;
    final cutoff = _now().subtract(olderThan).millisecondsSinceEpoch ~/ 1000;
    final out = await _git.text([
      'for-each-ref',
      '--format=%(refname) %(committerdate:unix)',
      'refs/shellx/',
    ]);
    final old = <String>[];
    for (final line in const LineSplitter().convert(out)) {
      final space = line.lastIndexOf(' ');
      if (space > 0 &&
          (int.tryParse(line.substring(space + 1)) ?? 0) < cutoff) {
        old.add(line.substring(0, space));
      }
    }
    if (old.isEmpty) return 0;
    await _git.run([
      'update-ref',
      '--stdin',
    ], input: utf8.encode(old.map((r) => 'delete $r\n').join()));
    await _git.run([
      'gc',
      '--prune=now',
      '-q',
    ], timeout: const Duration(minutes: 5));
    return old.length;
  });

  /// Whether any checkpoint is left.
  Future<bool> hasCheckpoints() => _serial(_hasCheckpoints);

  /// Deletes the whole repository when it holds no checkpoint and undo is
  /// not switched off (the repository also keeps that note, so that the
  /// next start does not try again). The check and the delete are one
  /// queued operation: a snapshot never meets a half-deleted repository.
  Future<void> dropIfEmpty() => _serial(() async {
    if (_off != null || await _hasCheckpoints()) return;
    try {
      await Directory(gitDir).delete(recursive: true);
    } on FileSystemException {
      // Gone already, or in use: next start.
    }
  });

  Future<bool> _hasCheckpoints() async {
    if (!File(p.join(gitDir, 'HEAD')).existsSync()) return false;
    return (await _git.text([
      'for-each-ref',
      '--count=1',
      'refs/shellx/',
    ])).trim().isNotEmpty;
  }

  Future<String> _treeNow() async {
    final untracked = _split(
      await _git.text(['ls-files', '-z', '--others', '--exclude-standard']),
    );
    await _exclude(untracked, const Duration(minutes: 2));
    await _git.run(['add', '-A'], timeout: const Duration(minutes: 2));
    return (await _git.text(['write-tree'])).trim();
  }

  Future<void> _ensureRepo() async {
    if (File(p.join(gitDir, 'HEAD')).existsSync()) return;
    Directory(gitDir).createSync(recursive: true);
    // The project is recorded first, in the same step as the folder: a
    // clean-up that lists the checkpoints folder must not take this
    // repository for an orphan.
    _writeMeta();
    // The info files are written before `git init` makes the repository:
    // once there is a HEAD, the project's attributes can no longer change
    // bytes, however this function ends.
    File(p.join(gitDir, 'info', 'attributes'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('* -text -filter -ident -working-tree-encoding\n');
    File(p.join(gitDir, 'info', 'exclude')).writeAsStringSync(_excludeHeader);
    // No templates: a global `init.templateDir` could put hooks into the
    // `hooks` folder that `core.hooksPath` trusts (see [GitRunner.flags]).
    await _git.run(['init', '-q', '--template=']);
  }

  /// Keeps nested repositories and big new files out (ruling R4). The size
  /// checks are async and batched: the store runs on the app's UI isolate,
  /// and a first snapshot can list 200 000 files (smooth-UI requirement).
  Future<void> _exclude(List<String> untracked, Duration timeout) async {
    final nested = [
      for (final e in untracked)
        if (e.endsWith('/')) e,
    ];
    final files = [
      for (final e in untracked)
        if (!e.endsWith('/')) e,
    ];
    final sizes = await _mapBatched(
      files,
      (e) => FileStat.stat(p.join(project, e)).then((s) => s.size),
    );
    final big = [
      for (var i = 0; i < files.length; i++)
        if (sizes[i] > maxFileBytes) files[i],
    ];
    if (nested.isEmpty && big.isEmpty) return;
    final file = File(p.join(gitDir, 'info', 'exclude'));
    final have = file.existsSync()
        ? file.readAsLinesSync().toSet()
        : <String>{};
    final add = [
      for (final e in [...nested, ...big]) excludePattern(e),
    ].where((l) => !have.contains(l)).toList();
    if (add.isNotEmpty) {
      file.writeAsStringSync('${add.join('\n')}\n', mode: FileMode.append);
    }
    if (nested.isNotEmpty) {
      await _git.run([
        'rm',
        '-r',
        '--cached',
        '-q',
        '--ignore-unmatch',
        '--',
        for (final n in nested) n.substring(0, n.length - 1),
      ], timeout: timeout);
    }
  }

  /// Runs [f] on every item, [_batch] at a time, and gives the results in
  /// the order of [items].
  static Future<List<R>> _mapBatched<T, R>(
    List<T> items,
    Future<R> Function(T item) f,
  ) async {
    final results = <R>[];
    for (var i = 0; i < items.length; i += _batch) {
      final end = i + _batch > items.length ? items.length : i + _batch;
      results.addAll(
        await Future.wait([for (final e in items.sublist(i, end)) f(e)]),
      );
    }
    return results;
  }

  /// Deletes the files a turn created, then the folders that are left
  /// empty (R5). Async and batched, like [_exclude]. A path that leaves the
  /// project, or goes through a `.git`, is never touched.
  Future<void> _deleteNew(List<String> paths) async {
    final root = p.canonicalize(project);
    final files = [
      for (final path in paths)
        if (!_inDotGit(path) &&
            p.isWithin(root, p.canonicalize(p.join(project, path))))
          File(p.join(project, path)),
    ];
    await _mapBatched(files, (file) async {
      try {
        await file.delete();
      } on FileSystemException {
        // Already gone, or a folder now: nothing to delete here.
        if (await file.exists()) rethrow;
      }
    });
    // Each folder once, however many files it held; then up to the project.
    for (final folder in {for (final f in files) f.parent.path}) {
      var dir = Directory(folder);
      while (p.isWithin(root, p.canonicalize(dir.path))) {
        try {
          await dir.delete(); // only succeeds on an empty folder
        } on FileSystemException {
          break; // not empty, or not a folder: so are its parents
        }
        dir = dir.parent;
      }
    }
  }

  UndoOff? _readOff() {
    try {
      final j = jsonDecode(_meta.readAsStringSync());
      if (j is! Map) return null;
      final reason = UndoOff.values
          .where((o) => o.name == j['off'])
          .firstOrNull;
      final at = j['offAt'];
      if (reason == null || at is! int) return null;
      final since = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
      return since > _offRetry ? null : reason;
    } on Object {
      return null;
    }
  }

  void _setOff(UndoOff reason) {
    _off = reason;
    _writeMeta(off: reason);
  }

  void _writeMeta({UndoOff? off}) {
    try {
      Directory(gitDir).createSync(recursive: true);
      _meta.writeAsStringSync(
        jsonEncode({
          'project': project,
          if (off != null) 'off': off.name,
          if (off != null) 'offAt': _now().millisecondsSinceEpoch,
        }),
      );
    } on FileSystemException {
      // Read-only support folder: undo is off for this run only.
    }
  }

  static List<String> _split(String z) =>
      z.split('\x00').where((s) => s.isNotEmpty).toList();

  /// Whether [path] is a `.git` or inside one: the project's own repository,
  /// a nested one, or the `.git` file of a worktree or submodule. Git never
  /// tracks these, so they are never in a checkpoint and never ours to
  /// delete. Compared without case: on macOS and Windows `.GIT` is the same
  /// folder.
  static bool _inDotGit(String path) =>
      p.split(path).any((segment) => segment.toLowerCase() == '.git');

  /// `added\tremoved\tpath`; `-` counts mean binary.
  static (int?, int?, String)? _numstat(String record) {
    final a = record.indexOf('\t');
    final b = a < 0 ? -1 : record.indexOf('\t', a + 1);
    if (b < 0) return null;
    return (
      int.tryParse(record.substring(0, a)),
      int.tryParse(record.substring(a + 1, b)),
      record.substring(b + 1),
    );
  }

  Future<T> _serial<T>(Future<T> Function() op) => _queue.run(() {
    if (!_swept) {
      _swept = true;
      _clearStaleLock();
    }
    return op();
  });

  /// A git killed inside `add` (power cut, out of memory, `kill -9`) leaves
  /// `index.lock` behind, and then every `add`, `write-tree` and `restore`
  /// exits 128 for good. This runs once, before the store's first operation.
  /// It is safe there: [CheckpointStores] makes one store per project, all
  /// the git of a store runs inside [_serial], and nothing has run yet, so a
  /// lock found now was left by a git that is dead. A lock that appears later
  /// is never touched (it could be live); [GitRunner] removes the one a
  /// timeout of its own left.
  void _clearStaleLock() {
    final lock = File(p.join(gitDir, 'index.lock'));
    try {
      if (lock.existsSync()) lock.deleteSync();
    } on FileSystemException {
      // Cannot be removed: git fails on it as before, and the first snapshot
      // says so (undo off).
    }
  }
}

/// Every project's [CheckpointStore], one per project so each has one
/// queue (spec D12).
final class CheckpointStores with Redacted {
  CheckpointStores({
    required this.root,
    GitLocator? locator,
    bool? isWindows,
    CheckpointStore Function(
      String project,
      String gitDir,
      GitTool git,
      Map<String, String> env,
    )?
    create,
  }) : _locator = locator ?? GitLocator(),
       _isWindows = isWindows ?? Platform.isWindows,
       _create =
           create ??
           ((project, gitDir, git, env) => CheckpointStore(
             project: project,
             gitDir: gitDir,
             git: git,
             env: env,
           ));

  /// `<app support>/ai/checkpoints`.
  final String root;
  final GitLocator _locator;
  final bool _isWindows;
  final CheckpointStore Function(String, String, GitTool, Map<String, String>)
  _create;
  final _stores = <String, CheckpointStore>{};
  GitTool? _gitTool;
  Future<(GitTool?, UndoOff?)>? _lookup;

  static String projectId(String realPath, {required bool isWindows}) => sha1
      .convert(utf8.encode(isWindows ? realPath.toLowerCase() : realPath))
      .toString()
      .substring(0, 12);

  /// The git to use, or why there is none. A git that was found is kept for
  /// the session; a failed lookup is not, so installing git (or the Command
  /// Line Tools) or fixing the PATH needs no restart: the next request looks
  /// again. Requests that arrive together share one lookup.
  Future<(GitTool?, UndoOff?)> _locate(LoginEnv env) async {
    final known = _gitTool;
    if (known != null) return (known, null);
    final lookup = _lookup ??= _locator.locate(env);
    try {
      final found = await lookup;
      if (found.$1 != null) _gitTool = found.$1;
      return found;
    } finally {
      if (identical(_lookup, lookup)) _lookup = null;
    }
  }

  /// The store for [project], or why undo is off on this machine.
  Future<(CheckpointStore?, UndoOff?)> forProject(
    String project,
    LoginEnv env,
  ) async {
    final (git, off) = await _locate(env);
    if (git == null) return (null, off);
    final real = _real(project);
    final id = projectId(real, isWindows: _isWindows);
    return (
      _stores.putIfAbsent(
        id,
        () => _create(real, p.join(root, id), git, env.vars),
      ),
      null,
    );
  }

  /// At app start: drop old checkpoints; delete the repos of projects that
  /// are gone or have none left (spec D12, `ai-checkpoint-days`). It goes
  /// through the same store (and queue) a tab uses, so a turn that starts
  /// meanwhile never meets a repository being pruned or deleted.
  Future<void> pruneAll(Duration olderThan, LoginEnv env) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    final (git, _) = await _locate(env);
    // Without git nothing can be pruned. Deleting here would turn one probe
    // that timed out into the loss of every project's checkpoints.
    if (git == null) return;
    for (final repo in dir.listSync().whereType<Directory>()) {
      final project = _projectOf(repo);
      if (project == null || !Directory(project).existsSync()) {
        await _delete(repo);
        continue;
      }
      final store = _stores.putIfAbsent(
        p.basename(repo.path),
        () => _create(project, repo.path, git, env.vars),
      );
      try {
        await store.prune(olderThan);
        await store.dropIfEmpty();
      } on Exception {
        // Try again next start.
      }
    }
  }

  /// "Xoá điểm khôi phục" in Settings. No turn may be running, and none may
  /// start before this is done.
  Future<void> deleteAll() async {
    _stores.clear();
    final dir = Directory(root);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  static String? _projectOf(Directory repo) {
    try {
      final j = jsonDecode(
        File(p.join(repo.path, 'shellx.json')).readAsStringSync(),
      );
      return j is Map && j['project'] is String ? j['project'] as String : null;
    } on Object {
      return null;
    }
  }

  static Future<void> _delete(Directory d) async {
    try {
      await d.delete(recursive: true);
    } on FileSystemException {
      // In use: next start.
    }
  }

  String _real(String path) {
    var real = path;
    try {
      real = Directory(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Keep it as given; the snapshot fails and says so.
    }
    while (real.length > 1 &&
        (real.endsWith('/') || real.endsWith(r'\')) &&
        !real.endsWith(r':\')) {
      real = real.substring(0, real.length - 1);
    }
    return real;
  }
}
