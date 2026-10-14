// The final review's findings on the checkpoints (V2-1b): a broad folder gets
// no restore points (I-1), "Delete all restore points" keeps the one store
// per project (M-7), and a first snapshot that fails for a moment does not
// switch undo off for a week (M-8).
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

import '../support/git_project.dart';

/// A file system that holds exactly the given executables.
final class _Exes implements FileProbe {
  _Exes(this.exes);

  final Set<String> exes;

  @override
  bool isExecutable(String path) => exes.contains(path);

  @override
  bool isFile(String path) => exes.contains(path);

  @override
  String? read(String path) => null;
}

void main() {
  late GitProject gp;
  late String root;
  late GitTool git;
  setUpAll(() async => git = await GitProject.git());
  setUp(() {
    gp = GitProject();
    root = p.join(gp.tmp.path, 'support', 'ai', 'checkpoints');
  });
  tearDown(() => gp.dispose());

  LoginEnv env() =>
      LoginEnv(Platform.environment, source: LoginEnvSource.process);

  /// The folder of restore points stays after "Delete all": the app excludes
  /// it from Time Machine once a launch, and a folder made again would be
  /// backed up until the next one. Only what is in it goes.
  void expectRootKeptEmpty() {
    expect(
      Directory(root).existsSync(),
      isTrue,
      reason: 'the folder itself stays (its Time Machine exclusion with it)',
    );
    expect(Directory(root).listSync(), isEmpty);
  }

  group('a broad folder gets no restore points (I-1)', () {
    /// A machine where asking for git is a failure of the test: the lookup
    /// would run `git --version`, which the probe refuses.
    CheckpointStores noGitWork({bool isWindows = false}) => CheckpointStores(
      root: root,
      isWindows: isWindows,
      locator: GitLocator(
        isMacOS: false,
        isWindows: false,
        files: _Exes({'/g/git'}),
        probe: (exe, args, {environment}) async =>
            fail('a broad folder asks for no git'),
      ),
      create: (project, gitDir, tool, e) =>
          fail('a broad folder gets no store'),
    );

    LoginEnv onG({String? home, String key = 'HOME'}) =>
        LoginEnv({'PATH': '/g', key: ?home}, source: LoginEnvSource.process);

    test('the home folder, a folder above it and a disk root: undo is off, '
        'and nothing was asked of git or written', () async {
      final stores = noGitWork();
      for (final folder in [
        '/Users/ann',
        '/Users/ann/',
        '/Users/ann/../ann',
        '/Users',
        '/',
      ]) {
        expect(await stores.forProject(folder, onG(home: '/Users/ann')), (
          null,
          UndoOff.broadFolder,
        ), reason: folder);
      }
      expect(Directory(root).existsSync(), isFalse, reason: 'nothing written');
    });

    test('a project inside the home folder is no broad folder', () async {
      final stores = CheckpointStores(
        root: root,
        locator: GitLocator(
          isMacOS: false,
          isWindows: false,
          files: _Exes(<String>{}),
        ),
      );
      // Past the broad-folder check, this machine has no git: the reason says
      // so, which shows the folder was looked at as a project.
      expect(await stores.forProject(gp.project, onG(home: gp.tmp.path)), (
        null,
        UndoOff.noGit,
      ));
      final other = Directory(p.join(gp.tmp.path, 'sibling'))..createSync();
      expect(await stores.forProject(other.path, onG(home: gp.project)), (
        null,
        UndoOff.noGit,
      ));
    });

    test('without a HOME in the environment only a disk root counts', () async {
      final stores = noGitWork();
      expect(await stores.forProject('/', onG()), (null, UndoOff.broadFolder));
      final gitless = CheckpointStores(
        root: root,
        locator: GitLocator(isMacOS: false, isWindows: false, files: _Exes({})),
      );
      expect(await gitless.forProject('/Users/ann', onG()), (
        null,
        UndoOff.noGit,
      ));
    });

    test('Windows: USERPROFILE (whatever its case), the drive root and the '
        'folders above it, compared without case', () async {
      final stores = noGitWork(isWindows: true);
      const home = r'C:\Users\Ann';
      for (final (folder, key) in [
        (r'C:\Users\Ann', 'USERPROFILE'),
        (r'c:\users\ann\', 'USERPROFILE'),
        (r'C:\Users\Ann', 'UserProfile'),
        (r'C:\Users', 'USERPROFILE'),
        (r'C:\', 'USERPROFILE'),
        (r'D:\', 'USERPROFILE'),
      ]) {
        expect(
          await stores.forProject(folder, onG(home: home, key: key)),
          (null, UndoOff.broadFolder),
          reason: '$folder with $key',
        );
      }
      final gitless = CheckpointStores(
        root: root,
        isWindows: true,
        locator: GitLocator(isMacOS: false, isWindows: false, files: _Exes({})),
      );
      expect(
        await gitless.forProject(
          r'C:\Users\Ann\proj',
          onG(home: home, key: 'USERPROFILE'),
        ),
        (null, UndoOff.noGit),
        reason: 'a project inside the home folder',
      );
    });

    test(
      'a link to the home folder is the home folder',
      () async {
        final home = Directory(p.join(gp.tmp.path, 'home'))..createSync();
        final link = Link(p.join(gp.tmp.path, 'home-link'))
          ..createSync(home.path);
        final stores = noGitWork();
        expect(await stores.forProject(link.path, onG(home: home.path)), (
          null,
          UndoOff.broadFolder,
        ));
        // …and the other way round: the home folder given as a link.
        final homeLink = Link(p.join(gp.tmp.path, 'home-as-link'))
          ..createSync(home.path);
        expect(await stores.forProject(home.path, onG(home: homeLink.path)), (
          null,
          UndoOff.broadFolder,
        ));
      },
      skip: Platform.isWindows ? 'links need rights on Windows' : false,
    );
  });

  group('Delete all restore points keeps one store per project (M-7)', () {
    CheckpointStores stores({GitTool? tool, int maxFiles = 200000}) =>
        CheckpointStores(
          root: root,
          create: (project, gitDir, found, e) => CheckpointStore(
            project: project,
            gitDir: gitDir,
            git: tool ?? found,
            env: e,
            maxFiles: maxFiles,
          ),
        );

    test('a store held while everything is deleted is the store the next '
        'forProject returns', () async {
      gp.put('a.txt', 'a');
      final s = stores();
      final (first, _) = await s.forProject(gp.project, env());
      expect(await first!.snapshot('s/1'), isNotNull);
      await s.deleteAll();
      final (second, _) = await s.forProject(gp.project, env());
      expect(identical(first, second), isTrue, reason: 'one queue a project');
    });

    test(
      'the repository is gone, and a snapshot after it works again',
      () async {
        gp.put('a.txt', 'one');
        final s = stores();
        final (store, _) = await s.forProject(gp.project, env());
        final before = (await store!.snapshot('s/1'))!;
        await s.deleteAll();
        expect(Directory(store.gitDir).existsSync(), isFalse);
        expectRootKeptEmpty();
        gp.put('a.txt', 'two');
        final after = (await store.snapshot('s/2'))!;
        expect(after.commit, isNot(before.commit));
        expect(
          Process.runSync('git', [
            '--git-dir',
            store.gitDir,
            'for-each-ref',
            '--format=%(refname)',
          ]).stdout.toString().trim(),
          'refs/shellx/s/2',
          reason: 'a fresh repository holds only the new checkpoint',
        );
        expect(utf8.decode((await store.fileAt(after.tree, 'a.txt'))!), 'two');
      },
    );

    test('a snapshot that is running when it starts finishes first', () async {
      if (Platform.isWindows) return;
      gp.put('a.txt', 'a');
      final mark = File(p.join(gp.tmp.path, 'in-write-tree'));
      // A git that holds `write-tree` for a second, after saying so.
      final slow = File(p.join(gp.tmp.path, 'slow-git'))
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'for a in "\$@"; do\n'
          '  if [ "\$a" = write-tree ]; then : > "${mark.path}"; sleep 1; fi\n'
          'done\n'
          'exec "${git.executable}" "\$@"\n',
        );
      Process.runSync('chmod', ['+x', slow.path]);
      final s = stores(tool: GitTool(slow.path, git.major, git.minor));
      final (store, _) = await s.forProject(gp.project, env());
      final snapshot = store!.snapshot('s/1');
      for (var i = 0; i < 400 && !mark.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(mark.existsSync(), isTrue, reason: 'the snapshot is under way');
      var deleted = false;
      final deleting = s.deleteAll().then((_) => deleted = true);
      expect(await snapshot, isNotNull, reason: 'it was not cut off');
      expect(deleted, isFalse, reason: 'the delete waited its turn');
      await deleting;
      expect(Directory(store.gitDir).existsSync(), isFalse);
    });

    test('undo that was off comes back with the fresh repository', () async {
      for (var i = 0; i < 5; i++) {
        gp.put('f$i.txt', '$i');
      }
      final s = stores(maxFiles: 3);
      final (store, _) = await s.forProject(gp.project, env());
      expect(await store!.snapshot('s/1'), isNull);
      expect(store.off, UndoOff.tooManyFiles);
      await s.deleteAll();
      expect(store.off, isNull, reason: 'the note was in the deleted folder');
    });

    test('the repositories no store holds go too, and so does what is not '
        'a repository', () async {
      gp.put('a.txt', 'a');
      // A repository of an earlier run: no store of this one holds it.
      final earlier = stores();
      final (old, _) = await earlier.forProject(gp.project, env());
      expect(await old!.snapshot('s/1'), isNotNull);
      final noMeta = Directory(p.join(root, 'no-meta-at-all'))..createSync();
      final stray = File(p.join(root, 'stray-file'))..writeAsStringSync('x');
      final now = stores();
      await now.deleteAll();
      expect(
        [old.gitDir, noMeta.path, stray.path].map(FileSystemEntity.typeSync),
        everyElement(FileSystemEntityType.notFound),
      );
      expectRootKeptEmpty();
    });

    test('with no folder of restore points at all it does nothing, makes none '
        'and throws nothing', () async {
      await stores().deleteAll();
      expect(Directory(root).existsSync(), isFalse);
    });

    test(
      'a store that cannot delete says so, and the others are deleted '
      'all the same',
      () async {
        if (Platform.isWindows) return;
        final other = Directory(p.join(gp.tmp.path, 'other'))..createSync();
        File(p.join(other.path, 'b.txt')).writeAsStringSync('b');
        gp.put('a.txt', 'a');
        final s = stores();
        final (one, _) = await s.forProject(gp.project, env());
        final (two, _) = await s.forProject(other.path, env());
        expect(await one!.snapshot('s/1'), isNotNull);
        expect(await two!.snapshot('s/1'), isNotNull);
        // Nothing can be unlinked inside the first repository.
        Process.runSync('chmod', ['555', one.gitDir]);
        try {
          await expectLater(s.deleteAll(), throwsA(isA<FileSystemException>()));
          expect(Directory(two.gitDir).existsSync(), isFalse);
        } finally {
          Process.runSync('chmod', ['755', one.gitDir]);
        }
      },
      skip: Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'needs a user that permissions apply to'
          : null,
    );
  });

  group('a failure of the first snapshot is for this run only (M-8)', () {
    const missing = GitTool('/nonexistent/dir/git', 2, 40);

    CheckpointStore store({
      GitTool? tool,
      int maxFiles = 200000,
      Duration first = const Duration(seconds: 30),
      String? gitDir,
    }) => CheckpointStore(
      project: gp.project,
      gitDir: gitDir ?? gp.gitDir,
      git: tool ?? git,
      env: Platform.environment,
      maxFiles: maxFiles,
      firstSnapshotLimit: first,
    );

    test('"failed" holds in this run and is not written down', () async {
      gp.put('a.txt', 'a');
      final s = store(tool: missing);
      expect(await s.snapshot('s/1'), isNull);
      expect(s.off, UndoOff.failed);
      expect(await s.snapshot('s/2'), isNull, reason: 'not tried again now');
      final meta = jsonDecode(
        File(p.join(gp.gitDir, 'shellx.json')).readAsStringSync(),
      );
      expect(meta, {'project': gp.project});
    });

    test('the next run tries again, and works', () async {
      gp.put('a.txt', 'a');
      expect(await store(tool: missing).snapshot('s/1'), isNull);
      final next = store();
      expect(next.off, isNull, reason: 'a new store over the same repository');
      expect(await next.snapshot('s/2'), isNotNull);
    });

    test(
      'across a restart of the app: new CheckpointStores, same folder',
      () async {
        gp.put('a.txt', 'a');
        final first = CheckpointStores(
          root: root,
          create: (project, gitDir, found, e) => CheckpointStore(
            project: project,
            gitDir: gitDir,
            git: missing,
            env: e,
          ),
        );
        final (a, _) = await first.forProject(gp.project, env());
        expect(await a!.snapshot('s/1'), isNull);
        expect(a.off, UndoOff.failed);

        final restarted = CheckpointStores(root: root);
        final (b, off) = await restarted.forProject(gp.project, env());
        expect(off, isNull);
        expect(b!.off, isNull, reason: 'undo is not off for a week');
        expect(await b.snapshot('s/1'), isNotNull);
      },
    );

    test('a "failed" an older version wrote down is not believed', () async {
      gp.put('a.txt', 'a');
      Directory(gp.gitDir).createSync(recursive: true);
      File(p.join(gp.gitDir, 'shellx.json')).writeAsStringSync(
        jsonEncode({
          'project': gp.project,
          'off': 'failed',
          'offAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      final s = store();
      expect(s.off, isNull);
      expect(await s.snapshot('s/1'), isNotNull);
    });

    test('too many files and too slow are still remembered', () async {
      for (var i = 0; i < 5; i++) {
        gp.put('f$i.txt', '$i');
      }
      expect(await store(maxFiles: 3).snapshot('s/1'), isNull);
      expect(store().off, UndoOff.tooManyFiles);

      final slowDir = p.join(gp.tmp.path, 'slow-shadow');
      final s = store(gitDir: slowDir, first: Duration.zero);
      expect(await s.snapshot('s/1'), isNull);
      expect(s.off, UndoOff.tooSlow);
      expect(store(gitDir: slowDir).off, UndoOff.tooSlow);
    });
  });
}
