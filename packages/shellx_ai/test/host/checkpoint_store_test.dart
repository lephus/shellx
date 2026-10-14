import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

import '../support/git_project.dart';

void main() {
  late GitTool git;
  late GitProject gp;
  setUpAll(() async => git = await GitProject.git());
  setUp(() => gp = GitProject());
  tearDown(() => gp.dispose());

  CheckpointStore store({
    Map<String, String>? env,
    int maxFiles = 200000,
    Duration first = const Duration(seconds: 30),
    int maxFileBytes = kMaxCheckpointFileBytes,
    DateTime Function()? now,
  }) => CheckpointStore(
    project: gp.project,
    gitDir: gp.gitDir,
    git: git,
    env: env ?? Platform.environment,
    maxFiles: maxFiles,
    firstSnapshotLimit: first,
    maxFileBytes: maxFileBytes,
    now: now,
  );

  test('snapshot, diff and restore give back the exact bytes', () async {
    gp
      ..put('a.txt', 'one\r\ntwo\r\n')
      ..put('bin.dat', [0, 1, 2, 255, 254])
      ..put('keep.txt', 'keep');
    final s = store();
    final ck = (await s.snapshot('sess/1'))!;
    gp
      ..put('a.txt', 'one\nTWO\n')
      ..put('new/dir/n.txt', 'new\n');
    File(p.join(gp.project, 'bin.dat')).deleteSync();

    final changes = {for (final c in await s.changes(ck.tree)) c.path: c};
    expect(
      changes.keys,
      unorderedEquals(['a.txt', 'bin.dat', 'new/dir/n.txt']),
    );
    expect(changes['a.txt']!.kind, ChangeKind.modified);
    expect(changes['bin.dat']!.kind, ChangeKind.deleted);
    expect(changes['bin.dat']!.binary, isTrue);
    expect(changes['new/dir/n.txt']!.kind, ChangeKind.added);
    expect(
      [changes['new/dir/n.txt']!.added, changes['new/dir/n.txt']!.removed],
      [1, 0],
    );
    expect(await s.fileAt(ck.tree, 'a.txt'), utf8.encode('one\r\ntwo\r\n'));
    expect(await s.fileAt(ck.tree, 'new/dir/n.txt'), isNull);

    await s.restore(ck.commit, changes.keys);
    expect(gp.bytes('a.txt'), utf8.encode('one\r\ntwo\r\n'));
    expect(gp.bytes('bin.dat'), [0, 1, 2, 255, 254]);
    expect(gp.exists('new/dir/n.txt'), isFalse);
    expect(
      gp.exists('new'),
      isFalse,
      reason: 'the folders the turn made are gone (R5)',
    );
    expect(gp.bytes('keep.txt'), utf8.encode('keep'));
  });

  test('the project own .git is never touched', () async {
    gp.put('a.txt', 'v1');
    gp.userGit(['init', '-q']);
    gp.userGit(['add', '-A']);
    gp.userGit(['commit', '-q', '-m', 'init']);
    gp.put('a.txt', 'v2');
    final index = File(p.join(gp.project, '.git', 'index'));
    // --no-optional-locks: the test's own `git status` must not rewrite the index.
    String state() => [
      gp.userGit(['--no-optional-locks', 'status', '--porcelain']).stdout,
      gp.userGit(['rev-parse', 'HEAD']).stdout,
      gp.userGit(['for-each-ref']).stdout,
      gp.userGit(['stash', 'list']).stdout,
    ].join('|');
    final before = state();
    final indexBytes = index.readAsBytesSync();
    final mtime = index.lastModifiedSync();

    final s = store();
    final ck = (await s.snapshot('sess/1'))!;
    gp.put('a.txt', 'v3');
    await s.changes(ck.tree);
    await s.restore(ck.commit, ['a.txt']);

    expect(index.readAsBytesSync(), indexBytes);
    expect(index.lastModifiedSync(), mtime);
    expect(state(), before);
    expect(gp.userGit(['for-each-ref', 'refs/shellx']).stdout, '');
    expect(File(p.join(gp.project, 'a.txt')).readAsStringSync(), 'v2');
  });

  test('.gitignore is honoured', () async {
    gp
      ..put('.gitignore', 'secret.env\nbuild/\n')
      ..put('secret.env', 'A=1')
      ..put('build/out.js', 'x');
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('secret.env', 'A=2')
      ..put('build/out.js', 'y');
    expect(await s.changes(ck.tree), isEmpty);
  });

  test(
    'a nested repository without commits does not break the snapshot (R4)',
    () async {
      gp
        ..put('top.txt', 'a')
        ..put('sub/repo/x.txt', 'x');
      gp.userGit(['init', '-q'], dir: p.join(gp.project, 'sub', 'repo'));
      final s = store();
      final ck = await s.snapshot('s/1');
      expect(ck, isNotNull);
      gp.put('sub/repo/x.txt', 'changed');
      expect(await s.changes(ck!.tree), isEmpty);
      expect(
        File(p.join(gp.gitDir, 'info', 'exclude')).readAsStringSync(),
        contains('/sub/repo/'),
      );
    },
  );

  test('a nested repository with commits is not added as a gitlink', () async {
    gp.put('lib/x.txt', 'x');
    final lib = p.join(gp.project, 'lib');
    gp.userGit(['init', '-q'], dir: lib);
    gp.userGit(['add', '-A'], dir: lib);
    gp.userGit(['commit', '-q', '-m', 'x'], dir: lib);
    gp.put('top.txt', 'a');
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    final tree =
        Process.runSync('git', [
              '--git-dir',
              gp.gitDir,
              'ls-tree',
              '-r',
              ck.tree,
            ]).stdout
            as String;
    expect(tree, contains('top.txt'));
    expect(tree, isNot(contains('160000')));
    expect(tree, isNot(contains('lib')));
  });

  test('too many files: undo off, remembered', () async {
    for (var i = 0; i < 5; i++) {
      gp.put('f$i.txt', '$i');
    }
    expect(await store(maxFiles: 3).snapshot('s/1'), isNull);
    expect(
      store().off,
      UndoOff.tooManyFiles,
      reason: 'a new store for the same repo reads it back',
    );
  });

  test(
    'the first snapshot runs over its time: undo off, no lock left',
    () async {
      gp.put('a.txt', 'a');
      final s = store(first: Duration.zero);
      expect(await s.snapshot('s/1'), isNull);
      expect(s.off, UndoOff.tooSlow);
      expect(File(p.join(gp.gitDir, 'index.lock')).existsSync(), isFalse);
    },
  );

  test('changed after the turn', () async {
    gp
      ..put('a.txt', '1')
      ..put('b.txt', '1');
    final s = store();
    await s.snapshot('s/1');
    gp.put('a.txt', '2'); // the agent
    final after = (await s.currentTree())!;
    gp.put('a.txt', '3'); // the user, later
    expect(await s.changedSince(after), {'a.txt'});
  });

  test('odd names: spaces, Vietnamese, glob characters', () async {
    final names = [
      'with space.txt',
      'Tiếng Việt.md',
      'br[1].txt',
      if (!Platform.isWindows) ...[
        'star*.txt',
        'q?.txt',
        'colon:x.txt',
        'back\\slash.txt',
      ],
    ];
    for (final n in names) {
      gp.put(n, 'old $n');
    }
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    for (final n in names) {
      gp.put(n, 'new $n');
    }
    final changed = (await s.changes(ck.tree)).map((c) => c.path).toSet();
    expect(changed, names.toSet());
    for (final n in names) {
      expect(utf8.decode((await s.fileAt(ck.tree, n))!), 'old $n');
    }
    await s.restore(ck.commit, [names.first, names.last]);
    expect(
      File(p.join(gp.project, names.first)).readAsStringSync(),
      'old ${names.first}',
    );
    expect(
      File(p.join(gp.project, names.last)).readAsStringSync(),
      'old ${names.last}',
    );
    expect(
      File(p.join(gp.project, names[1])).readAsStringSync(),
      'new ${names[1]}',
      reason: 'not asked for',
    );
  });

  test('project attributes cannot change bytes (R3)', () async {
    gp
      ..put(
        '.gitattributes',
        '* text=auto eol=crlf\n*.bin filter=lfs diff=lfs merge=lfs -text\n',
      )
      ..put('lf.txt', 'a\nb\n')
      ..put('data.bin', [1, 2, 3]);
    final s = store();
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('lf.txt', 'changed')
      ..put('data.bin', [9]);
    await s.restore(ck.commit, ['lf.txt', 'data.bin']);
    expect(gp.bytes('lf.txt'), utf8.encode('a\nb\n'));
    expect(gp.bytes('data.bin'), [1, 2, 3]);
  });

  test('a hostile global git config is neutralised (R3)', () async {
    final home = Directory(p.join(gp.tmp.path, 'home'))..createSync();
    final hooks = Directory(p.join(home.path, 'hooks'))..createSync();
    final marker = p.join(home.path, 'hook-ran');
    for (final h in [
      'pre-commit',
      'post-commit',
      'post-checkout',
      'reference-transaction',
    ]) {
      final f = File(p.join(hooks.path, h))
        ..writeAsStringSync('#!/bin/sh\necho ran > "$marker"\nexit 1\n');
      if (!Platform.isWindows) Process.runSync('chmod', ['+x', f.path]);
    }
    File(p.join(home.path, 'ignore')).writeAsStringSync('*.log\n');
    File(p.join(home.path, '.gitconfig')).writeAsStringSync('''
[core]
  autocrlf = true
  hooksPath = ${hooks.path.replaceAll(r'\', '/')}
  excludesFile = ${p.join(home.path, 'ignore').replaceAll(r'\', '/')}
[commit]
  gpgSign = true
[gpg]
  program = /nonexistent/gpg
''');
    final env = {
      ...Platform.environment,
      'HOME': home.path,
      'USERPROFILE': home.path,
      'XDG_CONFIG_HOME': home.path,
    };
    gp
      ..put('lf.txt', 'a\nb\n')
      ..put('debug.log', 'noise');
    final s = store(env: env);
    final ck = await s.snapshot('s/1');
    expect(ck, isNotNull, reason: 'no GPG, no hook');
    gp
      ..put('lf.txt', 'x')
      ..put('debug.log', 'more noise');
    expect(
      (await s.changes(ck!.tree)).map((c) => c.path),
      ['lf.txt'],
      reason: 'the global excludesFile still applies',
    );
    await s.restore(ck.commit, ['lf.txt']);
    expect(gp.bytes('lf.txt'), utf8.encode('a\nb\n'));
    expect(File(marker).existsSync(), isFalse);
  });

  test('files over the size cap are not tracked (R4)', () async {
    gp
      ..put('big.bin', List.filled(2048, 7))
      ..put('small.txt', 's');
    final s = store(maxFileBytes: 1024);
    final ck = (await s.snapshot('s/1'))!;
    gp
      ..put('big.bin', List.filled(2048, 8))
      ..put('small.txt', 't');
    expect((await s.changes(ck.tree)).map((c) => c.path), ['small.txt']);
  });

  test('prune drops checkpoints older than the retention', () async {
    gp.put('a.txt', 'a');
    final old = DateTime.now().subtract(const Duration(days: 30));
    await store(now: () => old).snapshot('s/1');
    gp.put('a.txt', 'b');
    await store().snapshot('s/2');
    expect(await store().prune(const Duration(days: 14)), 1);
    final refs =
        Process.runSync('git', [
              '--git-dir',
              gp.gitDir,
              'for-each-ref',
              '--format=%(refname)',
            ]).stdout
            as String;
    expect(refs.trim(), 'refs/shellx/s/2');
  });

  test('operations on one project run one at a time', () async {
    gp.put('a.txt', 'a');
    final s = store();
    final results = await Future.wait([
      s.snapshot('s/1'),
      s.currentTree(),
      s.snapshot('s/2'),
      s.currentTree(),
    ]);
    expect(results.every((r) => r != null), isTrue);
  });

  test('excludePattern anchors and escapes', () {
    expect(excludePattern('sub/repo/'), '/sub/repo/');
    expect(excludePattern(r'a*b?[c]\d'), r'/a\*b\?\[c]\\d');
    expect(excludePattern('#x !y'), r'/\#x \!y');
    expect(excludePattern('trail '), r'/trail\ ');
  });

  test('projectId: 12 hex of sha1(realpath); case-insensitive on Windows', () {
    final a = CheckpointStores.projectId('/Users/a/proj', isWindows: false);
    expect(a, matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(
      CheckpointStores.projectId('/Users/a/Proj', isWindows: false),
      isNot(a),
    );
    expect(
      CheckpointStores.projectId(r'C:\Users\A\Proj', isWindows: true),
      CheckpointStores.projectId(r'c:\users\a\proj', isWindows: true),
    );
  });

  test(
    'CheckpointStores: one store per project; pruneAll deletes repos of projects that are gone',
    () async {
      final stores = CheckpointStores(
        root: p.join(gp.tmp.path, 'support', 'ai', 'checkpoints'),
      );
      final env = LoginEnv(
        Platform.environment,
        source: LoginEnvSource.process,
      );
      gp.put('a.txt', 'a');
      final (s1, _) = await stores.forProject(gp.project, env);
      final (s2, _) = await stores.forProject(
        '${gp.project}${Platform.pathSeparator}',
        env,
      );
      expect(identical(s1, s2), isTrue);
      await s1!.snapshot('s/1');
      final gone = Directory(p.join(gp.tmp.path, 'gone'))..createSync();
      File(p.join(gone.path, 'x')).writeAsStringSync('x');
      final (s3, _) = await CheckpointStores(
        root: stores.root,
      ).forProject(gone.path, env);
      await s3!.snapshot('s/1');
      gone.deleteSync(recursive: true);
      await CheckpointStores(
        root: stores.root,
      ).pruneAll(const Duration(days: 14), env);
      expect(Directory(s1.gitDir).existsSync(), isTrue);
      expect(Directory(s3.gitDir).existsSync(), isFalse);
    },
  );
}
