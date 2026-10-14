// Pins what the brief's checkpoint tests leave open: the git runner around
// the process (environment, flags, limits, redaction), the locator's edges,
// restore at its limits, and how the stores prune and delete.
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

LoginEnv _path(String path) =>
    LoginEnv({'PATH': path}, source: LoginEnvSource.interactiveLogin);

/// Answers each `<exe> <args>` with its entry; anything else is "cannot run".
ProbeRunner _answers(Map<String, ProbeResult?> answers) =>
    (exe, args, {environment}) async => answers['$exe ${args.join(' ')}'];

Future<(GitTool?, UndoOff?)> _locate({
  required String path,
  required Set<String> exes,
  Map<String, ProbeResult?> answers = const {},
  bool isMacOS = false,
  bool isWindows = false,
}) => GitLocator(
  isMacOS: isMacOS,
  isWindows: isWindows,
  files: _Exes(exes),
  probe: _answers(answers),
).locate(_path(path));

void main() {
  group('GitLocator', () {
    ProbeResult version(String v) => ProbeResult(0, 'git version $v\n');

    test(
      'macOS /usr/bin/git with the Command Line Tools: asks, then runs',
      () async {
        final (git, off) = await _locate(
          path: '/usr/bin',
          exes: {'/usr/bin/git'},
          isMacOS: true,
          answers: {
            '/usr/bin/xcode-select -p': const ProbeResult(
              0,
              '/Library/Developer/CommandLineTools\n',
            ),
            '/usr/bin/git --version': version('2.39.5 (Apple Git-154)'),
          },
        );
        expect(off, isNull);
        expect(
          [git!.executable, git.major, git.minor],
          ['/usr/bin/git', 2, 39],
        );
      },
    );

    test('macOS xcode-select that cannot run: no Command Line Tools', () async {
      final (git, off) = await _locate(
        path: '/usr/bin',
        exes: {'/usr/bin/git'},
        isMacOS: true,
      );
      expect([git, off], [null, UndoOff.noCommandLineTools]);
    });

    test(
      'a git outside /usr/bin never asks xcode-select, and neither does Linux',
      () async {
        final asked = <String>[];
        Future<ProbeResult?> probe(
          String exe,
          List<String> args, {
          Map<String, String>? environment,
        }) async {
          asked.add(exe);
          return version('2.45.0');
        }

        final brew = await GitLocator(
          isMacOS: true,
          isWindows: false,
          files: _Exes({'/opt/homebrew/bin/git'}),
          probe: probe,
        ).locate(_path('/opt/homebrew/bin:/usr/bin'));
        final linux = await GitLocator(
          isMacOS: false,
          isWindows: false,
          files: _Exes({'/usr/bin/git'}),
          probe: probe,
        ).locate(_path('/usr/bin'));
        expect(
          [brew.$1!.executable, linux.$1!.executable],
          ['/opt/homebrew/bin/git', '/usr/bin/git'],
        );
        expect(asked, ['/opt/homebrew/bin/git', '/usr/bin/git']);
      },
    );

    test('the first git on PATH wins', () async {
      final (git, _) = await _locate(
        path: '/a:/b',
        exes: {'/a/git', '/b/git'},
        answers: {
          '/a/git --version': version('2.30.0'),
          '/b/git --version': version('2.50.0'),
        },
      );
      expect(git!.executable, '/a/git');
    });

    test('the version floor is 2.26', () async {
      Future<UndoOff?> offFor(String v) async => (await _locate(
        path: '/g',
        exes: {'/g/git'},
        answers: {'/g/git --version': version(v)},
      )).$2;
      expect(await offFor('2.25.1'), UndoOff.gitTooOld);
      expect(await offFor('1.9.5'), UndoOff.gitTooOld);
      expect(await offFor('2.26.0'), isNull);
      expect(await offFor('2.26.0.windows.1'), isNull);
      expect(await offFor('3.0.0'), isNull);
    });

    test(
      'a git that cannot say its version, or says something else, is not git',
      () async {
        for (final answer in <ProbeResult?>[
          null,
          const ProbeResult(1, 'git version 2.40.0'),
          const ProbeResult(0, 'usage: tool'),
        ]) {
          final (git, off) = await _locate(
            path: '/g',
            exes: {'/g/git'},
            answers: {'/g/git --version': answer},
          );
          expect([git, off], [null, UndoOff.noGit], reason: '$answer');
        }
      },
    );

    test('Windows: git.exe on PATH', () async {
      final (git, _) = await _locate(
        path: r'C:\bin;C:\Git\cmd',
        exes: {r'C:\Git\cmd\git.exe'},
        isWindows: true,
        answers: {r'C:\Git\cmd\git.exe --version': version('2.45.1.windows.1')},
      );
      expect(
        [git!.executable, git.major, git.minor],
        [r'C:\Git\cmd\git.exe', 2, 45],
      );
    });
  });

  group('GitRunner', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('runner'));
    tearDown(() => tmp.deleteSync(recursive: true));

    final noSh = Platform.isWindows ? 'the fake git is a shell script' : null;

    /// A "git" that is a shell script running [body].
    GitTool fakeGit(String body) {
      final f = File(p.join(tmp.path, 'fake-git'))
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return GitTool(f.path, 2, 40);
    }

    GitRunner runner(GitTool git, {Map<String, String> env = const {}}) =>
        GitRunner(
          git: git,
          gitDir: p.join(tmp.path, 'shadow'),
          workTree: tmp.path,
          env: env,
        );

    test(
      'flags keep the user config from changing bytes, signing or running code',
      () {
        final r = runner(const GitTool('git', 2, 40));
        final f = r.flags;
        expect([
          for (var i = 0; i < f.length; i += 2) f[i],
        ], everyElement('-c'));
        final settings = [for (var i = 1; i < f.length; i += 2) f[i]];
        expect(
          settings,
          containsAll([
            'core.autocrlf=false',
            'core.safecrlf=false',
            'core.fsmonitor=false',
            'core.quotePath=false',
            'commit.gpgSign=false',
            'gc.auto=0',
            'maintenance.auto=false',
          ]),
        );
        expect(
          settings.where((s) => s.startsWith('core.hooksPath=')),
          [
            'core.hooksPath=${p.join(tmp.path, 'shadow')}${Platform.pathSeparator}hooks',
          ],
          reason: 'hooks come from inside the shadow repo only',
        );
      },
    );

    test(
      'GIT_DIR and GIT_WORK_TREE are set, every inherited GIT_ variable is dropped, the rest is kept',
      () async {
        final r = runner(
          fakeGit('env; pwd -P; for a in "\$@"; do echo "arg:\$a"; done'),
          env: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'HOME': '/some/home',
            'KEEP_ME': 'kept',
            'GIT_DIR': '/evil/dir',
            'GIT_INDEX_FILE': '/evil/index',
            'GIT_CONFIG_GLOBAL': '/evil/config',
            'git_work_tree': '/evil/tree',
            'Git_Object_Directory': '/evil/objects',
          },
        );
        final out = (await r.text(['status', '--short'])).split('\n');
        expect(out, contains('GIT_DIR=${p.join(tmp.path, 'shadow')}'));
        expect(out, contains('GIT_WORK_TREE=${tmp.path}'));
        expect(out, contains('GIT_LITERAL_PATHSPECS=1'));
        expect(out, contains('GIT_TERMINAL_PROMPT=0'));
        expect(
          out,
          containsAll(['GIT_AUTHOR_NAME=ShellX', 'GIT_COMMITTER_NAME=ShellX']),
        );
        expect(out, containsAll(['HOME=/some/home', 'KEEP_ME=kept']));
        expect(
          out.where((l) => l.contains('/evil')),
          isEmpty,
          reason: 'nothing the app was started with leaks in',
        );
        expect(
          out,
          contains(Directory(tmp.path).resolveSymbolicLinksSync()),
          reason: 'git runs in the project',
        );
        expect(
          out.where((l) => l.startsWith('arg:')).skip(r.flags.length).toList(),
          ['arg:status', 'arg:--short'],
        );
        expect(
          out.where((l) => l.startsWith('arg:')).take(r.flags.length).toList(),
          [for (final a in r.flags) 'arg:$a'],
        );
      },
      skip: noSh,
    );

    test('the commit date is the injected clock', () async {
      final r = GitRunner(
        git: fakeGit('echo "\$GIT_COMMITTER_DATE|\$GIT_AUTHOR_DATE"'),
        gitDir: tmp.path,
        workTree: tmp.path,
        env: {'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin'},
        now: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      expect(
        (await r.text(const [])).trim(),
        '1767323045 +0000|1767323045 +0000',
      );
    }, skip: noSh);

    test(
      'input reaches git on stdin; a failure carries the exit code and never git stderr',
      () async {
        final echo = runner(fakeGit('cat'));
        expect(
          await echo.text(const [], input: utf8.encode('Tiếng Việt\x00ok')),
          'Tiếng Việt\x00ok',
        );

        final failing = runner(
          fakeGit('echo "fatal: secret-project/passwords.txt" >&2; exit 3'),
        );
        await expectLater(
          failing.run(const []),
          throwsA(
            isA<GitFailed>()
                .having((e) => e.exitCode, 'exitCode', 3)
                .having((e) => e.timedOut, 'timedOut', false)
                .having((e) => '$e', 'toString', 'GitFailed(3)'),
          ),
        );
      },
      skip: noSh,
    );

    test(
      'a git over its time is killed, its index.lock removed, and it says timed out',
      () async {
        final lock = File(p.join(tmp.path, 'shadow', 'index.lock'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');
        final r = runner(fakeGit('exec sleep 30'));
        await expectLater(
          r.run(const [], timeout: const Duration(milliseconds: 300)),
          throwsA(
            isA<GitFailed>()
                .having((e) => e.timedOut, 'timedOut', true)
                .having((e) => '$e', 'toString', 'GitFailed(timeout)'),
          ),
        );
        expect(lock.existsSync(), isFalse);
      },
      skip: noSh,
    );

    test(
      'output held open by a child after git exited is under the same limit',
      () async {
        final r = runner(fakeGit('(sleep 4) &\nexit 0'));
        final clock = Stopwatch()..start();
        await expectLater(
          r.run(const [], timeout: const Duration(milliseconds: 300)),
          throwsA(isA<GitFailed>().having((e) => e.timedOut, 'timedOut', true)),
        );
        expect(
          clock.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'did not wait for the child to let go',
        );
      },
      skip: noSh,
    );
  });

  group('redaction', () {
    test(
      'the git and store types print nothing about the machine or the project',
      () {
        const tool = GitTool('/nonexistent/someone/bin/git', 2, 40);
        final runner = GitRunner(
          git: tool,
          gitDir: '/nonexistent/someone/g',
          workTree: '/nonexistent/someone/proj',
          env: const {'SECRET': 'x'},
        );
        final store = CheckpointStore(
          project: '/nonexistent/someone/proj',
          gitDir: '/nonexistent/someone/g',
          git: tool,
          env: const {},
        );
        final stores = CheckpointStores(
          root: '/nonexistent/someone/ai/checkpoints',
        );
        for (final o in <Object>[tool, runner, store, stores]) {
          expect('$o', '…');
        }
        expect(store, isA<Checkpoints>());
      },
    );
  });

  group('CheckpointStore', () {
    late GitTool git;
    late GitProject gp;
    setUpAll(() async => git = await GitProject.git());
    setUp(() => gp = GitProject());
    tearDown(() => gp.dispose());

    CheckpointStore store({
      Map<String, String>? env,
      int maxFiles = 200000,
      int maxFileBytes = kMaxCheckpointFileBytes,
      DateTime Function()? now,
      GitTool? tool,
      String? gitDir,
    }) => CheckpointStore(
      project: gp.project,
      gitDir: gitDir ?? gp.gitDir,
      git: tool ?? git,
      env: env ?? Platform.environment,
      maxFiles: maxFiles,
      maxFileBytes: maxFileBytes,
      now: now,
    );

    String refs() =>
        (Process.runSync('git', [
                  '--git-dir',
                  gp.gitDir,
                  'for-each-ref',
                  '--format=%(refname)',
                ]).stdout
                as String)
            .trim();

    /// A HOME whose git config and template folder try to run [hooks].
    Map<String, String> hostileTemplateHome(List<String> hooks, String marker) {
      final home = Directory(p.join(gp.tmp.path, 'home'))..createSync();
      final template = Directory(p.join(home.path, 'tpl', 'hooks'))
        ..createSync(recursive: true);
      for (final h in hooks) {
        final f = File(p.join(template.path, h))
          ..writeAsStringSync('#!/bin/sh\necho ran >> "$marker"\nexit 1\n');
        if (!Platform.isWindows) Process.runSync('chmod', ['+x', f.path]);
      }
      File(p.join(home.path, '.gitconfig')).writeAsStringSync(
        '[init]\n  templateDir = ${p.join(home.path, 'tpl').replaceAll(r'\', '/')}\n',
      );
      return {
        ...Platform.environment,
        'HOME': home.path,
        'USERPROFILE': home.path,
        'XDG_CONFIG_HOME': home.path,
      };
    }

    test(
      'a global init.templateDir cannot put hooks into the shadow repo',
      () async {
        final marker = p.join(gp.tmp.path, 'hook-ran');
        final env = hostileTemplateHome([
          'reference-transaction',
          'post-index-change',
          'pre-commit',
          'post-commit',
          'post-checkout',
          'pre-auto-gc',
        ], marker);
        gp.put('a.txt', 'one');
        final s = store(env: env);
        final ck = await s.snapshot('s/1');
        expect(
          ck,
          isNotNull,
          reason: 'git init and update-ref run no template hook',
        );
        gp.put('a.txt', 'two');
        await s.restore(ck!.commit, ['a.txt']);
        expect(gp.bytes('a.txt'), utf8.encode('one'));
        expect(File(marker).existsSync(), isFalse);
        expect(
          Directory(p.join(gp.gitDir, 'hooks')).existsSync(),
          isFalse,
          reason: 'no templates were copied',
        );
        expect(
          File(p.join(gp.gitDir, 'info', 'attributes')).readAsStringSync(),
          contains('-text'),
        );
      },
    );

    test(
      'the repo records the project it belongs to (pruneAll finds the project by it)',
      () async {
        gp.put('a.txt', 'a');
        await store().snapshot('s/1');
        final meta =
            jsonDecode(
                  File(p.join(gp.gitDir, 'shellx.json')).readAsStringSync(),
                )
                as Map;
        expect(meta, {'project': gp.project});
      },
    );

    test(
      'a git that cannot start: no checkpoint, undo off, nothing thrown',
      () async {
        gp.put('a.txt', 'a');
        const missing = GitTool('/nonexistent/dir/git', 2, 40);
        final s = store(tool: missing);
        expect(await s.snapshot('s/1'), isNull);
        expect(s.off, UndoOff.failed);
        final other = store(
          tool: missing,
          gitDir: p.join(gp.tmp.path, 'other-shadow'),
        );
        expect(await other.currentTree(), isNull);
        expect(
          other.off,
          isNull,
          reason: 'only a first snapshot switches undo off',
        );
      },
    );

    test('changes between two checkpoints, with line counts', () async {
      gp
        ..put('a.txt', 'a\nb\nc\n')
        ..put('gone.txt', 'x\n')
        ..put('dir/y.txt', 'y\n');
      final s = store();
      final one = (await s.snapshot('s/1'))!;
      gp.put('a.txt', 'a\nB\nc\nd\n');
      File(p.join(gp.project, 'gone.txt')).deleteSync();
      final two = (await s.snapshot('s/2'))!;
      gp.put('a.txt', 'changed after the second checkpoint');
      final changes = {
        for (final c in await s.changes(one.tree, two.tree)) c.path: c,
      };
      expect(changes.keys, unorderedEquals(['a.txt', 'gone.txt']));
      expect(
        [
          changes['a.txt']!.kind,
          changes['a.txt']!.added,
          changes['a.txt']!.removed,
        ],
        [ChangeKind.modified, 2, 1],
      );
      expect(
        [
          changes['gone.txt']!.kind,
          changes['gone.txt']!.added,
          changes['gone.txt']!.removed,
        ],
        [ChangeKind.deleted, 0, 1],
      );
      expect(await s.changes(two.tree, two.tree), isEmpty);
      expect(await s.fileAt(one.tree, 'gone.txt'), utf8.encode('x\n'));
      expect(await s.fileAt(two.tree, 'gone.txt'), isNull);
      expect(
        await s.fileAt(one.tree, 'dir'),
        isNull,
        reason: 'a folder is not a file',
      );
    });

    test('the size cap holds across batches of files', () async {
      for (var i = 0; i < 600; i++) {
        gp.put('many/f$i.txt', 'x');
      }
      gp
        ..put('many/big-early.bin', List.filled(20, 1))
        ..put('z-big-late.bin', List.filled(20, 2));
      final s = store(maxFileBytes: 10);
      final ck = (await s.snapshot('s/1'))!;
      final tree =
          Process.runSync('git', [
                '--git-dir',
                gp.gitDir,
                'ls-tree',
                '-r',
                '--name-only',
                ck.tree,
              ]).stdout
              as String;
      final names = tree.split('\n').where((n) => n.isNotEmpty).toSet();
      expect(names.length, 600);
      expect(names, isNot(contains('many/big-early.bin')));
      expect(names, isNot(contains('z-big-late.bin')));
      expect(names, contains('many/f599.txt'));
    });

    test(
      'restore asks git for exactly these paths: glob and pathspec characters match nothing else',
      () async {
        if (Platform.isWindows) return;
        gp
          ..put('star*.txt', 'old')
          ..put('starX.txt', 'old')
          ..put(':!bang.txt', 'old')
          ..put('other.txt', 'old');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        for (final n in ['star*.txt', 'starX.txt', ':!bang.txt', 'other.txt']) {
          gp.put(n, 'new');
        }
        await s.restore(ck.commit, ['star*.txt', ':!bang.txt']);
        expect(utf8.decode(gp.bytes('star*.txt')), 'old');
        expect(utf8.decode(gp.bytes(':!bang.txt')), 'old');
        expect(
          utf8.decode(gp.bytes('starX.txt')),
          'new',
          reason: 'star*.txt is a name, not a pattern',
        );
        expect(utf8.decode(gp.bytes('other.txt')), 'new');
      },
    );

    test('restore never touches a path outside the project', () async {
      final outside = File(p.join(gp.tmp.path, 'outside.txt'))
        ..writeAsStringSync('keep');
      final sibling = File(p.join(gp.tmp.path, 'project-evil', 'x.txt'))
        ..parent.createSync()
        ..writeAsStringSync('keep');
      gp.put('a.txt', 'a');
      final s = store();
      final ck = (await s.snapshot('s/1'))!;
      await s.restore(ck.commit, [
        '../outside.txt',
        'sub/../../outside.txt',
        outside.path,
        '../project-evil/x.txt',
        sibling.path,
      ]);
      expect(outside.readAsStringSync(), 'keep');
      expect(sibling.readAsStringSync(), 'keep');
      expect(gp.bytes('a.txt'), utf8.encode('a'));
    });

    test(
      'restore deletes files only; a folder named in the paths stays, and so does a folder holding other files',
      () async {
        gp.put('keep.txt', 'k');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        gp
          ..put('gen/agent.txt', 'agent')
          ..put('gen/mine.txt', 'the user made this after the turn');
        await s.restore(ck.commit, ['gen']);
        expect(gp.exists('gen/agent.txt'), isTrue);
        await s.restore(ck.commit, ['gen/agent.txt', 'never/was/here.txt']);
        expect(gp.exists('gen/agent.txt'), isFalse);
        expect(gp.exists('gen/mine.txt'), isTrue);
        expect(gp.exists('gen'), isTrue);
        expect(gp.exists('never'), isFalse);
        expect(gp.exists('keep.txt'), isTrue);
      },
    );

    test(
      'restore deletes many new files over several batches, and the folders they leave empty',
      () async {
        gp.put('keep.txt', 'k');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        for (var i = 0; i < 700; i++) {
          gp.put('gen/f$i.txt', 'x$i');
        }
        gp
          ..put('gen/deep/er/a.txt', 'a')
          ..put('gen/deep/b.txt', 'b')
          ..put('other/c.txt', 'c');
        final changes = await s.changes(ck.tree);
        expect(changes.length, 703);
        await s.restore(ck.commit, changes.map((c) => c.path));
        expect(gp.exists('gen'), isFalse);
        expect(gp.exists('other'), isFalse);
        expect(gp.exists('keep.txt'), isTrue);
        expect(
          Directory(gp.project).listSync().map((e) => p.basename(e.path)),
          ['keep.txt'],
        );
      },
    );

    test(
      'restore when a file became a folder and a folder became a file',
      () async {
        gp
          ..put('a', 'a was a file')
          ..put('d/x.txt', 'x was in a folder');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        File(p.join(gp.project, 'a')).deleteSync();
        gp.put('a/b.txt', 'a is a folder now');
        Directory(p.join(gp.project, 'd')).deleteSync(recursive: true);
        gp.put('d', 'd is a file now');
        final paths = (await s.changes(ck.tree)).map((c) => c.path).toList();
        expect(paths, unorderedEquals(['a', 'a/b.txt', 'd', 'd/x.txt']));
        await s.restore(ck.commit, paths);
        expect(utf8.decode(gp.bytes('a')), 'a was a file');
        expect(utf8.decode(gp.bytes('d/x.txt')), 'x was in a folder');
        expect(gp.exists('a/b.txt'), isFalse);
        expect(await s.changes(ck.tree), isEmpty);
      },
    );

    test(
      'a nested repository added after the first snapshot leaves the snapshot working',
      () async {
        gp.put('top.txt', 'a');
        final s = store();
        expect(await s.snapshot('s/1'), isNotNull);
        gp.put('sub/x.txt', 'x');
        gp.userGit(['init', '-q'], dir: p.join(gp.project, 'sub'));
        gp.put('top.txt', 'b');
        final ck = await s.snapshot('s/2');
        expect(
          ck,
          isNotNull,
          reason:
              'a later snapshot never switches undo off, and this one works',
        );
        expect(
          File(p.join(gp.gitDir, 'info', 'exclude')).readAsStringSync(),
          contains('/sub/'),
        );
      },
    );

    test(
      'dropIfEmpty is one queued step: snapshots queued behind it start the repo again',
      () async {
        gp.put('a.txt', 'a');
        final old = DateTime.now().subtract(const Duration(days: 30));
        await store(now: () => old).snapshot('s/1');
        final later = store(
          now: () => DateTime.now().add(const Duration(days: 30)),
        );
        expect(await later.prune(const Duration(days: 14)), 1);
        expect(refs(), '');
        final results = await Future.wait<Object?>([
          later.dropIfEmpty(),
          later.snapshot('s/2'),
          later.snapshot('s/3'),
        ]);
        expect(
          [results[1], results[2]],
          everyElement(isNotNull),
          reason: 'no snapshot meets a half-deleted repository',
        );
        expect(refs().split('\n'), ['refs/shellx/s/2', 'refs/shellx/s/3']);
      },
    );

    test(
      'dropIfEmpty keeps a repository that has a checkpoint, even one taken right after a prune',
      () async {
        gp.put('a.txt', 'a');
        final old = DateTime.now().subtract(const Duration(days: 30));
        await store(now: () => old).snapshot('s/1');
        gp.put('a.txt', 'b');
        final s = store();
        final results = await Future.wait<Object?>([
          s.prune(const Duration(days: 14)),
          s.snapshot('s/2'),
          s.dropIfEmpty(),
        ]);
        expect(results[0], 1);
        expect(results[1], isNotNull);
        expect(refs(), 'refs/shellx/s/2');
      },
    );

    test(
      'a moved file is a deleted path and an added path, and one restore puts both right',
      () async {
        gp
          ..put('old.txt', 'content')
          ..put('keep.txt', 'k');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        final moved = Directory(p.join(gp.project, 'moved'))..createSync();
        File(
          p.join(gp.project, 'old.txt'),
        ).renameSync(p.join(moved.path, 'new.txt'));
        final changes = {
          for (final c in await s.changes(ck.tree)) c.path: c.kind,
        };
        expect(changes, {
          'old.txt': ChangeKind.deleted,
          'moved/new.txt': ChangeKind.added,
        });
        await s.restore(ck.commit, changes.keys);
        expect(utf8.decode(gp.bytes('old.txt')), 'content');
        expect(gp.exists('moved'), isFalse);
        expect(await s.changes(ck.tree), isEmpty);
      },
    );

    test(
      'restore says so when a file cannot be deleted',
      () async {
        gp.put('keep.txt', 'k');
        final s = store();
        final ck = (await s.snapshot('s/1'))!;
        gp.put('locked/new.txt', 'x');
        final locked = Directory(p.join(gp.project, 'locked'));
        Process.runSync('chmod', ['555', locked.path]);
        try {
          await expectLater(
            s.restore(ck.commit, ['locked/new.txt']),
            throwsA(isA<FileSystemException>()),
          );
          expect(gp.exists('locked/new.txt'), isTrue);
        } finally {
          Process.runSync('chmod', ['755', locked.path]);
        }
      },
      skip:
          Platform.isWindows ||
              Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'needs a user that permissions apply to'
          : null,
    );

    test(
      'ignored files are not listed, so they neither count nor get stat-ed nor excluded',
      () async {
        gp
          ..put('.gitignore', 'ignored/\n')
          ..put('ignored/big.bin', List.filled(20, 1))
          ..put('a.txt', 'a')
          ..put('b.txt', 'b');
        for (var i = 0; i < 10; i++) {
          gp.put('ignored/f$i.txt', 'x');
        }
        final s = store(maxFiles: 5, maxFileBytes: 10);
        expect(
          await s.snapshot('s/1'),
          isNotNull,
          reason: '3 files count, not 13',
        );
        expect(s.off, isNull);
        expect(await s.currentTree(), isNotNull);
        expect(
          File(p.join(gp.gitDir, 'info', 'exclude')).readAsStringSync(),
          isNot(contains('ignored')),
        );
      },
    );

    test(
      'project attributes: no filter driver, no \$Id\$ expansion, no re-encoding (R3)',
      () async {
        if (Platform.isWindows) return;
        final marker = p.join(gp.tmp.path, 'filter-ran');
        final home = Directory(p.join(gp.tmp.path, 'home'))..createSync();
        final script = File(p.join(home.path, 'filter.sh'))
          ..writeAsStringSync('#!/bin/sh\necho ran >> $marker\nexit 1\n');
        Process.runSync('chmod', ['+x', script.path]);
        File(p.join(home.path, '.gitconfig')).writeAsStringSync(
          '[filter "evil"]\n  clean = ${script.path}\n  smudge = ${script.path}\n  required = true\n',
        );
        final env = {
          ...Platform.environment,
          'HOME': home.path,
          'XDG_CONFIG_HOME': home.path,
        };
        gp
          ..put(
            '.gitattributes',
            '*.dat filter=evil\nident.txt ident\nu16.txt working-tree-encoding=UTF-16\n',
          )
          ..put('a.dat', 'data one')
          ..put('ident.txt', 'x \$Id\$ y')
          ..put('u16.txt', 'héllo');
        final s = store(env: env);
        final ck = await s.snapshot('s/1');
        expect(ck, isNotNull, reason: 'no filter, no encoding conversion');
        gp
          ..put('a.dat', 'changed')
          ..put('ident.txt', 'changed')
          ..put('u16.txt', 'changed');
        await s.restore(ck!.commit, ['a.dat', 'ident.txt', 'u16.txt']);
        expect(utf8.decode(gp.bytes('a.dat')), 'data one');
        expect(utf8.decode(gp.bytes('ident.txt')), 'x \$Id\$ y');
        expect(utf8.decode(gp.bytes('u16.txt')), 'héllo');
        expect(File(marker).existsSync(), isFalse);
      },
    );

    test('the note that undo is off lasts seven days', () async {
      for (var i = 0; i < 5; i++) {
        gp.put('f$i.txt', '$i');
      }
      expect(await store(maxFiles: 3).snapshot('s/1'), isNull);
      DateTime inDays(int d) => DateTime.now().add(Duration(days: d));
      expect(store(now: () => inDays(6)).off, UndoOff.tooManyFiles);
      expect(
        store(now: () => inDays(8)).off,
        isNull,
        reason: 'the next start tries again',
      );
    });

    test('prune frees what only the dropped checkpoints held', () async {
      gp.put('a.txt', 'only the old checkpoint has this');
      final old = DateTime.now().subtract(const Duration(days: 30));
      final first = (await store(now: () => old).snapshot('s/1'))!;
      final blob =
          (Process.runSync('git', [
                    '--git-dir',
                    gp.gitDir,
                    'rev-parse',
                    '${first.tree}:a.txt',
                  ]).stdout
                  as String)
              .trim();
      gp.put('a.txt', 'and the new one has this');
      final s = store();
      expect(await s.snapshot('s/2'), isNotNull);
      Object has(String sha) => Process.runSync('git', [
        '--git-dir',
        gp.gitDir,
        'cat-file',
        '-e',
        sha,
      ]).exitCode;
      expect(has(blob), 0);
      expect(await s.prune(const Duration(days: 14)), 1);
      expect(has(blob), isNot(0), reason: 'gc --prune=now ran');
    });

    test(
      'restore recreates a folder the turn deleted, and hasCheckpoints follows the refs',
      () async {
        gp
          ..put('docs/guide/a.md', 'a')
          ..put('docs/b.md', 'b');
        final s = store();
        expect(await s.hasCheckpoints(), isFalse, reason: 'no repository yet');
        final ck = (await s.snapshot('s/1'))!;
        expect(await s.hasCheckpoints(), isTrue);
        Directory(p.join(gp.project, 'docs')).deleteSync(recursive: true);
        expect(await s.changedSince(ck.tree), {'docs/guide/a.md', 'docs/b.md'});
        await s.restore(ck.commit, ['docs/guide/a.md', 'docs/b.md']);
        expect(utf8.decode(gp.bytes('docs/guide/a.md')), 'a');
        expect(utf8.decode(gp.bytes('docs/b.md')), 'b');
        expect(await s.changedSince(ck.tree), isEmpty);
      },
    );

    test(
      'the attributes and excludes are in place before git init runs',
      () async {
        if (Platform.isWindows) return;
        final seen = File(p.join(gp.tmp.path, 'seen'));
        final script = File(p.join(gp.tmp.path, 'fake-git'))
          ..writeAsStringSync(
            '#!/bin/sh\n'
            'for a in "\$@"; do [ "\$a" = init ] && '
            '{ ls "\$GIT_DIR/info" > "${seen.path}"; exit 1; }; done\n'
            'exit 0\n',
          );
        Process.runSync('chmod', ['+x', script.path]);
        gp.put('a.txt', 'a');
        final s = store(tool: GitTool(script.path, 2, 40));
        expect(await s.snapshot('s/1'), isNull, reason: 'init "failed"');
        expect(seen.readAsStringSync().split('\n').where((n) => n.isNotEmpty), [
          'attributes',
          'exclude',
        ]);
        expect(
          File(p.join(gp.gitDir, 'info', 'attributes')).readAsStringSync(),
          contains('-text'),
        );
      },
    );
  });

  group('CheckpointStores', () {
    late GitProject gp;
    late String root;
    final env = LoginEnv(Platform.environment, source: LoginEnvSource.process);
    setUp(() {
      gp = GitProject();
      root = p.join(gp.tmp.path, 'support', 'ai', 'checkpoints');
    });
    tearDown(() => gp.dispose());

    CheckpointStores stores({
      int maxFiles = 200000,
      DateTime Function()? now,
      List<String>? made,
    }) => CheckpointStores(
      root: root,
      create: (project, gitDir, git, e) {
        made?.add(project);
        return CheckpointStore(
          project: project,
          gitDir: gitDir,
          git: git,
          env: e,
          maxFiles: maxFiles,
          now: now,
        );
      },
    );

    test(
      'pruneAll deletes a repository whose last checkpoint is older than the retention',
      () async {
        gp.put('a.txt', 'a');
        final old = DateTime.now().subtract(const Duration(days: 30));
        final (s, _) = await stores(now: () => old).forProject(gp.project, env);
        expect(await s!.snapshot('s/1'), isNotNull);
        await stores().pruneAll(const Duration(days: 14), env);
        expect(Directory(s.gitDir).existsSync(), isFalse);
      },
    );

    test('pruneAll keeps a repository that has a recent checkpoint', () async {
      gp.put('a.txt', 'a');
      final (s, _) = await stores().forProject(gp.project, env);
      expect(await s!.snapshot('s/1'), isNotNull);
      await stores().pruneAll(const Duration(days: 14), env);
      expect(Directory(s.gitDir).existsSync(), isTrue);
    });

    test('pruneAll keeps the repository that remembers undo is off', () async {
      for (var i = 0; i < 5; i++) {
        gp.put('f$i.txt', '$i');
      }
      final (s, _) = await stores(maxFiles: 3).forProject(gp.project, env);
      expect(await s!.snapshot('s/1'), isNull);
      expect(s.off, UndoOff.tooManyFiles);
      await stores().pruneAll(const Duration(days: 14), env);
      expect(
        Directory(s.gitDir).existsSync(),
        isTrue,
        reason: 'the note must outlive an app start',
      );
      final (again, _) = await stores().forProject(gp.project, env);
      expect(again!.off, UndoOff.tooManyFiles);
    });

    test('pruneAll uses the store a tab uses, whichever came first', () async {
      gp.put('a.txt', 'a');
      final made = <String>[];
      final one = stores(made: made);
      final (s, _) = await one.forProject(gp.project, env);
      await s!.snapshot('s/1');
      await one.pruneAll(const Duration(days: 14), env);
      expect(
        made,
        hasLength(1),
        reason: 'pruneAll took the store forProject made',
      );

      final fresh = stores(made: made..clear());
      await fresh.pruneAll(const Duration(days: 14), env);
      final (t, _) = await fresh.forProject(gp.project, env);
      expect(
        made,
        hasLength(1),
        reason: 'forProject took the store pruneAll made',
      );
      expect(t!.gitDir, s.gitDir);
    });

    test(
      'pruneAll deletes the repository of a project that is gone, and of one it cannot read',
      () async {
        final gone = Directory(p.join(gp.tmp.path, 'gone'))..createSync();
        File(p.join(gone.path, 'x')).writeAsStringSync('x');
        final (g, _) = await stores().forProject(gone.path, env);
        await g!.snapshot('s/1');
        gone.deleteSync(recursive: true);
        final noMeta = Directory(p.join(root, 'no-meta-at-all'))
          ..createSync(recursive: true);
        final badMeta = Directory(p.join(root, 'bad-meta'))
          ..createSync(recursive: true);
        File(p.join(badMeta.path, 'shellx.json')).writeAsStringSync('not json');
        File(
          p.join(root, 'stray-file'),
        ).writeAsStringSync('not a repository folder');
        await stores().pruneAll(const Duration(days: 14), env);
        expect(
          [
            g.gitDir,
            noMeta.path,
            badMeta.path,
          ].map((d) => Directory(d).existsSync()),
          everyElement(isFalse),
        );
        expect(File(p.join(root, 'stray-file')).existsSync(), isTrue);
      },
    );

    test(
      'pruneAll without git deletes nothing (a probe that timed out must not cost every checkpoint)',
      () async {
        final gone = Directory(p.join(gp.tmp.path, 'gone'))..createSync();
        File(p.join(gone.path, 'x')).writeAsStringSync('x');
        final (g, _) = await stores().forProject(gone.path, env);
        expect(await g!.snapshot('s/1'), isNotNull);
        gone.deleteSync(recursive: true);
        final orphan = Directory(p.join(root, 'orphan'))
          ..createSync(recursive: true);
        final noGit = LoginEnv({
          'PATH': '/nonexistent',
        }, source: LoginEnvSource.process);
        await CheckpointStores(
          root: root,
        ).pruneAll(const Duration(days: 14), noGit);
        expect(Directory(g.gitDir).existsSync(), isTrue);
        expect(orphan.existsSync(), isTrue);
      },
    );

    test('forProject says why when there is no git', () async {
      final (s, off) = await CheckpointStores(root: root).forProject(
        gp.project,
        LoginEnv({'PATH': '/nonexistent'}, source: LoginEnvSource.process),
      );
      expect([s, off], [null, UndoOff.noGit]);
    });

    test('pruneAll with no checkpoints folder does nothing', () async {
      await stores().pruneAll(const Duration(days: 14), env);
      expect(Directory(root).existsSync(), isFalse);
    });

    test(
      'deleteAll removes every repository; the next forProject starts clean',
      () async {
        gp.put('a.txt', 'a');
        final s = stores();
        final (first, _) = await s.forProject(gp.project, env);
        expect(await first!.snapshot('s/1'), isNotNull);
        await s.deleteAll();
        expect(Directory(root).existsSync(), isFalse);
        final (second, _) = await s.forProject(gp.project, env);
        expect(identical(first, second), isFalse);
        expect(await second!.snapshot('s/1'), isNotNull);
      },
    );
  });
}
