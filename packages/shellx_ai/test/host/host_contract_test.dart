// Pins what the brief's two host test files leave open: the Windows shim rule
// for explicit names, the real-process helpers, the shell choice, the
// package.json shapes the resolver reads and every catalog entry.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

/// An in-memory file system for both platforms.
final class _Files implements FileProbe {
  final files = <String, String>{};
  final executables = <String>{};

  @override
  bool isFile(String path) =>
      files.containsKey(path) || executables.contains(path);

  @override
  bool isExecutable(String path) => executables.contains(path);

  @override
  String? read(String path) => files[path];
}

/// Whether process [pid] is still running after up to two seconds.
Future<bool> stillRunning(String pid) async {
  for (var i = 0; i < 40; i++) {
    if (Process.runSync('kill', ['-0', pid]).exitCode != 0) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

List<int> marked(Map<String, String> vars) => utf8.encode(
  '\x1e${vars.entries.map((e) => '${e.key}=${e.value}').join('\x00')}\x00\x1e',
);

LoginEnv env(Map<String, String> vars) =>
    LoginEnv(vars, source: LoginEnvSource.interactiveLogin);
AgentSpec known(String id) => kKnownAgents.firstWhere((a) => a.id == id);
ProbeRunner nodeVersion(String v) =>
    (exe, args, {environment}) async => ProbeResult(0, '$v\n');

void main() {
  group('findExecutable on Windows', () {
    final vars = {'pAtH': r'C:\tools;;C:\bin\'};
    late _Files fs;
    setUp(() => fs = _Files());

    String? find(
      String command, {
      Map<String, String>? from,
      bool shims = false,
    }) => findExecutable(
      command,
      from ?? vars,
      isWindows: true,
      files: fs,
      shims: shims,
    );

    test(
      'PATH order first, .exe before .com in one folder; any spelling of Path; empty entries skipped',
      () {
        fs.executables.addAll([
          'tool.exe',
          r'C:\bin\tool.exe',
          r'C:\tools\tool.com',
        ]);
        expect(
          find('tool'),
          r'C:\tools\tool.com',
          reason: 'the first folder wins',
        );
        fs.executables.add(r'C:\tools\tool.exe');
        expect(find('tool'), r'C:\tools\tool.exe');
        expect(find('tool', from: const {}), isNull, reason: 'no PATH at all');
      },
    );

    test(
      'a name that already ends in .exe or .com is taken as given, in any case',
      () {
        fs.executables.addAll([r'C:\tools\Tool.EXE', r'C:\tools\old.Com']);
        expect(find('Tool.EXE'), r'C:\tools\Tool.EXE');
        expect(find(r'C:\tools\old.Com', from: const {}), r'C:\tools\old.Com');
      },
    );

    test('a dot that is not an extension still gets .exe (python3.11)', () {
      fs.executables.add(r'C:\tools\python3.11.exe');
      expect(find('python3.11'), r'C:\tools\python3.11.exe');
    });

    test(
      'a .cmd or .bat is never returned, by name or by path, unless asked for (spec D6)',
      () {
        for (final path in [
          r'C:\tools\a.cmd',
          r'C:\tools\b.BAT',
          r'C:\tools\c.Cmd',
          r'C:\tools\d.bat',
        ]) {
          fs.executables.add(path);
          final name = p.windows.basename(path);
          expect(find(name), isNull, reason: name);
          expect(find(path, from: const {}), isNull, reason: path);
          expect(
            find(path, from: const {}, shims: true),
            path,
            reason: '$path with shims',
          );
          expect(find(name, shims: true), path, reason: '$name with shims');
        }
        fs.executables.add(r'C:\tools\e.cmd');
        expect(find('e'), isNull, reason: 'without the extension too');
        expect(find('e', shims: true), r'C:\tools\e.cmd');
      },
    );

    test(
      'a name hiding a shim behind .exe or a trailing dot is no executable either',
      () {
        fs.executables.addAll([r'C:\tools\f.exe.cmd', r'C:\tools\g.cmd.']);
        expect(find('f.exe.cmd'), isNull);
        expect(find('g.cmd.'), isNull);
      },
    );

    test(
      'through the resolver: a custom agent that is a .cmd file is shim-only',
      () async {
        fs.executables.add(r'C:\tools\mine.cmd');
        final resolver = AgentResolver(
          agentsDir: r'C:\support\ai\agents',
          isWindows: true,
          files: fs,
        );
        const spec = AgentSpec(
          id: 'custom:mine',
          name: 'Mine',
          launch: CustomLaunch(command: r'C:\tools\mine.cmd'),
        );
        expect(
          await resolver.resolve(spec, env(vars)),
          isA<AgentNotFound>()
              .having((r) => r.shimOnly, 'shimOnly', isTrue)
              .having((r) => r.command, 'command', r'C:\tools\mine.cmd'),
        );
        fs.executables.add(r'C:\tools\mine.exe');
        const exe = AgentSpec(
          id: 'custom:mine',
          name: 'Mine',
          launch: CustomLaunch(command: r'C:\tools\mine'),
        );
        final r = await resolver.resolve(exe, env(vars)) as AgentReady;
        expect(r.command.executable, r'C:\tools\mine.exe');
      },
    );
  });

  group('findExecutable on POSIX (fake file system)', () {
    test(
      'PATH order; a file that is not executable is passed over; no PATH is no match',
      () {
        final fs = _Files()
          ..files['/a/tool'] = ''
          ..executables.addAll(['tool', '/b/tool', '/c/tool']);
        final vars = {'PATH': '::/a::/b:/c'};
        expect(
          findExecutable('tool', vars, isWindows: false, files: fs),
          '/b/tool',
        );
        expect(
          findExecutable('tool', const {}, isWindows: false, files: fs),
          isNull,
        );
        expect(
          findExecutable('nope', vars, isWindows: false, files: fs),
          isNull,
        );
      },
    );

    test('a command with a slash is not looked up on PATH', () {
      final fs = _Files()..executables.add('/b/tool');
      expect(
        findExecutable('b/tool', {'PATH': '/'}, isWindows: false, files: fs),
        isNull,
      );
      expect(
        findExecutable('/b/tool', const {}, isWindows: false, files: fs),
        '/b/tool',
      );
    });
  });

  test('envValue: the exact name first, then any case, else null', () {
    expect(envValue({'Path': 'b', 'PATH': 'a'}, 'PATH'), 'a');
    expect(envValue({'Path': 'b'}, 'PATH'), 'b');
    expect(envValue({'path': 'c'}, 'Path'), 'c');
    expect(envValue(const {}, 'PATH'), isNull);
  });

  group('RealFileProbe', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('real_files'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('files, folders, links and missing paths', () {
      const files = RealFileProbe();
      final file = File('${tmp.path}/f')..writeAsStringSync('hello');
      Process.runSync('chmod', ['+x', file.path]);
      final folder = Directory('${tmp.path}/d')..createSync();
      final link = Link('${tmp.path}/l')..createSync(file.path);
      final dangling = Link('${tmp.path}/x')..createSync('${tmp.path}/gone');

      expect([file.path, link.path].map(files.isFile), [true, true]);
      expect(
        [folder.path, dangling.path, '${tmp.path}/none'].map(files.isFile),
        [false, false, false],
      );
      expect(
        [file.path, link.path].map(files.isExecutable),
        [true, true],
        reason: 'a link counts through',
      );
      expect(
        [
          folder.path,
          dangling.path,
          '${tmp.path}/none',
        ].map(files.isExecutable),
        [false, false, false],
      );
      expect(files.read(file.path), 'hello');
      expect(files.read(folder.path), isNull);
      expect(files.read('${tmp.path}/none'), isNull);
    });
  }, testOn: '!windows');

  group('runProbe (real processes)', () {
    test('the exit code and stdout, even when the exit is not zero', () async {
      final r = await runProbe('/bin/sh', ['-c', 'echo v22.1.0; exit 3']);
      expect(r?.exitCode, 3);
      expect(r?.stdout, 'v22.1.0\n');
    });

    test(
      'given an environment, the child gets that and nothing else; without one, the parent environment',
      () async {
        final given = await runProbe(
          '/usr/bin/env',
          const [],
          environment: {'ONLY': 'this'},
        );
        expect(given!.stdout, contains('ONLY=this'));
        expect(
          given.stdout,
          isNot(contains('PATH=')),
          reason: 'the app environment stays out',
        );
        final inherited = await runProbe('/usr/bin/env', const []);
        expect(inherited!.stdout, contains('PATH='));
      },
    );

    test(
      'an executable that does not exist is null, not an exception',
      () async {
        expect(await runProbe('/nonexistent/tool', const []), isNull);
      },
    );

    test('over its time: null, and the process is killed', () async {
      final tmp = Directory.systemTemp.createTempSync('probe');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final pidFile = File('${tmp.path}/pid');
      final sw = Stopwatch()..start();
      final r = await runProbe('/bin/sh', [
        '-c',
        'echo \$\$ > "${pidFile.path}"; exec sleep 20',
      ], timeout: const Duration(seconds: 1));
      expect(r, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      final pid = pidFile.readAsStringSync().trim();
      expect(
        await stillRunning(pid),
        isFalse,
        reason: 'pid $pid is still running',
      );
    });

    test('a loud stderr does not block the child', () async {
      final r = await runProbe('/bin/sh', [
        '-c',
        'head -c 300000 /dev/zero >&2; echo done',
      ]);
      expect(r?.stdout, 'done\n');
    });
  }, testOn: '!windows');

  group('the marked environment', () {
    test(
      'entries without a name or an = are skipped; non-ASCII values survive',
      () {
        final parsed = parseMarkedEnv(
          utf8.encode(
            'x\x1eHOME=/Users/Nguyễn\x00junk\x00=nameless\x00B=2\x00\x1ey',
          ),
        );
        expect(parsed, {'HOME': '/Users/Nguyễn', 'B': '2'});
      },
    );

    test('markers around nothing: an empty environment, not null', () {
      expect(parseMarkedEnv(utf8.encode('\x1e\x1e')), isEmpty);
    });

    test('cleanAgentEnv drops the SHELLX_ prefix only and copies', () {
      final input = {
        'MY_SHELLX_THING': '1',
        'Shellx_Mixed': '2',
        'SHELLX_': '3',
        'KEEP': '4',
      };
      expect(cleanAgentEnv(input), {'MY_SHELLX_THING': '1', 'KEEP': '4'});
      expect(input, hasLength(4), reason: 'the input is not changed');
    });

    test('LoginEnv prints its source and size, never a value', () {
      expect(
        env({'TOKEN': 'hunter2'}).toString(),
        'LoginEnv(interactiveLogin, 1 vars)',
      );
    });
  });

  group('LoginShellEnv', () {
    Future<String> shellFor(String? shellVar, {required bool mac}) async {
      final used = <String>[];
      await LoginShellEnv(
        processEnv: {'SHELL': ?shellVar},
        isWindows: false,
        isMacOS: mac,
        run: (shell, args, environment, timeout) async {
          used.add(shell);
          return (0, marked({'PATH': '/x'}));
        },
      ).resolve();
      return used.first;
    }

    test(
      r'only an absolute $SHELL of a known shell is used; else /bin/zsh on macOS and /bin/sh elsewhere',
      () async {
        for (final shell in [
          '/bin/zsh',
          '/bin/bash',
          '/bin/sh',
          '/usr/bin/fish',
          '/bin/dash',
          '/usr/bin/ksh',
        ]) {
          expect(await shellFor(shell, mac: false), shell);
        }
        expect(
          await shellFor('/opt/homebrew/bin/fish', mac: false),
          '/opt/homebrew/bin/fish',
        );
        expect(await shellFor('/usr/bin/nu', mac: true), '/bin/zsh');
        expect(await shellFor('zsh', mac: false), '/bin/sh');
        expect(await shellFor('/bin/zsh/', mac: false), '/bin/sh');
        expect(await shellFor(null, mac: true), '/bin/zsh');
        expect(await shellFor(null, mac: false), '/bin/sh');
      },
    );

    test(
      'the same shell, environment and timeout both times; TERM is dumb and the flag is set',
      () async {
        final calls = <(String, List<String>, Map<String, String>, Duration)>[];
        final r = await LoginShellEnv(
          processEnv: {
            'PATH': '/app',
            'SHELL': '/bin/zsh',
            'SHELLX_SOCKET': 's',
            'TERM': 'xterm',
          },
          isWindows: false,
          timeout: const Duration(seconds: 3),
          run: (shell, args, environment, timeout) async {
            calls.add((shell, args, environment, timeout));
            return (0, utf8.encode('nothing useful'));
          },
        ).resolve();
        expect(r.source, LoginEnvSource.process);
        expect(calls.map((c) => c.$2.take(c.$2.length - 1).join(' ')), [
          '-i -l -c',
          '-l -c',
        ]);
        expect(calls.map((c) => c.$2.last), everyElement(LoginShellEnv.script));
        expect(calls.map((c) => c.$1), everyElement('/bin/zsh'));
        expect(
          calls.map((c) => c.$4),
          everyElement(const Duration(seconds: 3)),
        );
        expect(calls[0].$3, calls[1].$3);
        expect(calls[0].$3, containsPair('TERM', 'dumb'));
        expect(calls[0].$3, containsPair('SHELLX_RESOLVING_ENVIRONMENT', '1'));
        expect(calls[0].$3, containsPair('PATH', '/app'));
      },
    );

    test(
      'a shell without a PATH in its answer is not an answer: the next way is asked',
      () async {
        var n = 0;
        final r = await LoginShellEnv(
          processEnv: {'PATH': '/app'},
          isWindows: false,
          run: (shell, args, environment, timeout) async => n++ == 0
              ? (0, marked({'HOME': '/h'}))
              : (0, marked({'PATH': '/p'})),
        ).resolve();
        expect(r.source, LoginEnvSource.login);
        expect(r.vars, {'PATH': '/p'});

        final none = await LoginShellEnv(
          processEnv: {'PATH': '/app', 'HOME': '/h'},
          isWindows: false,
          run: (shell, args, environment, timeout) async =>
              (0, marked({'HOME': '/elsewhere'})),
        ).resolve();
        expect(none.source, LoginEnvSource.process);
        expect(none.vars['HOME'], '/h');
      },
    );

    group('real shells', () {
      late Directory tmp;
      setUp(
        () => tmp = Directory.systemTemp.createTempSync('login_env_contract'),
      );
      tearDown(() => tmp.deleteSync(recursive: true));

      String script(String name, String body) {
        final f = File('${tmp.path}/$name')
          ..writeAsStringSync('#!/bin/sh\n$body\n');
        Process.runSync('chmod', ['+x', f.path]);
        return f.path;
      }

      test(
        'nothing of SHELLX_* or the shell noise comes back from a real round trip',
        () async {
          final shell = script('plain', r'''
for last; do :; done
exec /bin/sh -c "$last"''');
          final r = await LoginShellEnv(
            shell: shell,
            processEnv: {
              'PATH': '/usr/bin:/bin',
              'HOME': '/Users/x',
              'SHELLX_CLI_TOKEN': 'secret',
              'SHELLX_SOCKET': '/tmp/s',
              'PWD': '/stale',
            },
            isWindows: false,
          ).resolve();
          expect(r.source, LoginEnvSource.interactiveLogin);
          expect(r.vars['HOME'], '/Users/x');
          expect(
            r.vars.keys.where((k) => k.toUpperCase().startsWith('SHELLX_')),
            isEmpty,
          );
          expect(
            r.vars.keys.toSet().intersection({'PWD', 'OLDPWD', 'SHLVL', '_'}),
            isEmpty,
          );
          // Only the given environment reaches the shell, not the one of this test.
          const given = {'PATH', 'HOME', 'TERM', 'PWD', 'OLDPWD', 'SHLVL', '_'};
          final parentOnly = Platform.environment.keys.where(
            (k) => !given.contains(k) && !k.startsWith('SHELLX_'),
          );
          expect(parentOnly.where(r.vars.containsKey), isEmpty);
        },
      );

      test('a hung shell is killed, not left running', () async {
        final pids = File('${tmp.path}/pids');
        final shell = script(
          'hang_pid',
          'if [ "\$1" = warm ]; then exit 0; fi\n'
              'echo \$\$ >> "${pids.path}"\n'
              'exec sleep 30',
        );
        // The first run of a new file can take a while (macOS checks it).
        Process.runSync(shell, ['warm']);
        final r = await LoginShellEnv(
          shell: shell,
          processEnv: {'PATH': '/usr/bin:/bin'},
          isWindows: false,
          timeout: const Duration(milliseconds: 500),
        ).resolve();
        expect(r.source, LoginEnvSource.process);
        final started = pids.readAsLinesSync();
        expect(started, isNotEmpty);
        for (final pid in started) {
          expect(
            await stillRunning(pid),
            isFalse,
            reason: 'pid $pid is still running',
          );
        }
      });

      test('a shell that refuses -i is asked again with -l', () async {
        final shell = script('no_i', r'''
if [ "$1" = "-i" ]; then echo "no tty" >&2; exit 2; fi
for last; do :; done
exec /bin/sh -c "$last"''');
        final r = await LoginShellEnv(
          shell: shell,
          processEnv: {'PATH': '/usr/bin:/bin'},
          isWindows: false,
        ).resolve();
        expect(r.source, LoginEnvSource.login);
        expect(r.vars['PATH'], '/usr/bin:/bin');
      });

      test(
        'a background job that keeps stdout open does not hold the answer back',
        () async {
          final shell = script('bg', r'''
sleep 8 &
for last; do :; done
/bin/sh -c "$last"''');
          final sw = Stopwatch()..start();
          final r = await LoginShellEnv(
            shell: shell,
            processEnv: {'PATH': '/usr/bin:/bin'},
            isWindows: false,
          ).resolve();
          expect(r.source, LoginEnvSource.interactiveLogin);
          expect(sw.elapsed, lessThan(const Duration(seconds: 6)));
        },
      );

      test('a shell that is loud on stderr is not blocked by it', () async {
        final shell = script('loud', r'''
head -c 300000 /dev/zero >&2
for last; do :; done
exec /bin/sh -c "$last"''');
        final r = await LoginShellEnv(
          shell: shell,
          processEnv: {'PATH': '/usr/bin:/bin'},
          isWindows: false,
          timeout: const Duration(seconds: 3),
        ).resolve();
        expect(r.source, LoginEnvSource.interactiveLogin);
      });

      test(
        'a profile that reads its stdin sees the end of it at once',
        () async {
          final shell = script('reads', r'''
cat > /dev/null
for last; do :; done
exec /bin/sh -c "$last"''');
          final r = await LoginShellEnv(
            shell: shell,
            processEnv: {'PATH': '/usr/bin:/bin'},
            isWindows: false,
            timeout: const Duration(seconds: 3),
          ).resolve();
          expect(r.source, LoginEnvSource.interactiveLogin);
        },
      );

      test(
        'a shell that does not exist: the app environment, cleaned',
        () async {
          final r = await LoginShellEnv(
            shell: '/nonexistent/zsh',
            processEnv: {'PATH': '/p', 'SHELLX_CLI_TOKEN': 't'},
            isWindows: false,
          ).resolve();
          expect(r.source, LoginEnvSource.process);
          expect(r.vars, {'PATH': '/p'});
        },
      );
    }, testOn: '!windows');
  });

  group('the catalog', () {
    test('every entry: package, pin, bin, args and Node floor', () {
      final rows = [
        for (final a in kKnownAgents)
          switch (a.launch) {
            NpmLaunch(
              :final package,
              :final version,
              :final bin,
              :final args,
              :final minNode,
            ) =>
              '${a.id}/${a.name}: $package@$version bin=$bin args=$args node>=$minNode',
            PathLaunch(:final command, :final args) =>
              '${a.id}/${a.name}: PATH $command $args',
            CustomLaunch() => '${a.id}: custom',
          },
      ];
      expect(rows, [
        'claude/Claude: @agentclientprotocol/claude-agent-acp@0.90.0 bin=dist/index.js args=[] node>=22',
        'codex/Codex: @agentclientprotocol/codex-acp@2.2.2 bin=dist/index.js args=[] node>=20',
        'gemini/Gemini CLI: @google/gemini-cli@0.64.0 bin=bundle/gemini.js args=[--acp] node>=20',
        'opencode/OpenCode: PATH opencode [acp]',
      ]);
    });

    test(
      'withArgs keeps the folder and leaves the original alone; the defaults are empty',
      () {
        const c = AgentCommand(
          executable: 'npm',
          args: ['install'],
          environment: {'A': '1'},
          workingDirectory: '/prefix',
        );
        final more = c.withArgs(['x']);
        expect(more.workingDirectory, '/prefix');
        expect(more.environment, {'A': '1'});
        expect(
          [c.args, c.environment],
          [
            ['install'],
            {'A': '1'},
          ],
        );
        const bare = AgentCommand(executable: 'node');
        expect(
          [bare.args, bare.environment, bare.workingDirectory],
          [isEmpty, isEmpty, isNull],
        );
        const custom = CustomLaunch(command: 'x');
        expect([custom.args, custom.env], [isEmpty, isEmpty]);
        expect(const PathLaunch('x').args, isEmpty);
      },
    );
  });

  group('the resolver reads package.json', () {
    late _Files fs;
    final vars = {'PATH': '/usr/local/bin:/usr/bin', 'HOME': '/Users/a'};
    const pkg =
        '/support/ai/agents/claude/node_modules/@agentclientprotocol/claude-agent-acp';
    AgentResolver resolver({ProbeRunner? probe, String node = 'v22.12.0'}) =>
        AgentResolver(
          agentsDir: '/support/ai/agents',
          isWindows: false,
          probe: probe ?? nodeVersion(node),
          files: fs,
        );

    setUp(
      () =>
          fs = _Files()
            ..executables.addAll({'/usr/local/bin/node', '/usr/local/bin/npm'}),
    );

    Future<AgentReadiness> claude() =>
        resolver().resolve(known('claude'), env(vars));

    void install(String json, {String? entry}) {
      fs.files['$pkg/package.json'] = json;
      if (entry != null) fs.files['$pkg/$entry'] = '';
    }

    test('bin as a plain string', () async {
      install('{"version":"0.90.0","bin":"lib/main.js"}', entry: 'lib/main.js');
      final r = await claude() as AgentReady;
      expect(r.command.args, ['$pkg/lib/main.js']);
    });

    test('bin written with dots is normalized', () async {
      install(
        '{"version":"0.90.0","bin":"./dist/../dist/index.js"}',
        entry: 'dist/index.js',
      );
      final r = await claude() as AgentReady;
      expect(r.command.args, ['$pkg/dist/index.js']);
    });

    test('of several bins, the one named like the package', () async {
      install(
        '{"version":"0.90.0","bin":{"other":"x.js","claude-agent-acp":"lib/main.js"}}',
        entry: 'lib/main.js',
      );
      final r = await claude() as AgentReady;
      expect(r.command.args, ['$pkg/lib/main.js']);
    });

    test(
      'no bin, or several and none named like the package: the catalog bin',
      () async {
        install('{"version":"0.90.0"}', entry: 'dist/index.js');
        expect(((await claude()) as AgentReady).command.args, [
          '$pkg/dist/index.js',
        ]);
        install(
          '{"version":"0.90.0","bin":{"a":"x.js","b":"y.js"}}',
          entry: 'dist/index.js',
        );
        expect(((await claude()) as AgentReady).command.args, [
          '$pkg/dist/index.js',
        ]);
      },
    );

    test(
      'the right version without its entry file, or a package.json nobody can read: install',
      () async {
        install('{"version":"0.90.0","bin":"dist/index.js"}');
        expect(await claude(), isA<AgentNeedsInstall>());
        for (final broken in [
          'not json',
          '[1,2]',
          'null',
          '"0.90.0"',
          '{"version":90}',
        ]) {
          install(broken, entry: 'dist/index.js');
          expect(await claude(), isA<AgentNeedsInstall>(), reason: broken);
        }
      },
    );

    test(
      'the Node floor is a floor: 22.0.0 runs Claude, 21.9.0 does not; Codex wants 20',
      () async {
        install('{"version":"0.90.0"}', entry: 'dist/index.js');
        expect(
          await resolver(node: 'v22.0.0').resolve(known('claude'), env(vars)),
          isA<AgentReady>(),
        );
        expect(
          await resolver(node: 'v21.9.0').resolve(known('claude'), env(vars)),
          isA<AgentNeedsNode>()
              .having((r) => r.found, 'found', 'v21.9.0')
              .having((r) => r.required, 'required', 22),
        );
        expect(
          await resolver(node: 'v20.0.0').resolve(known('codex'), env(vars)),
          isA<AgentNeedsInstall>(),
        );
        expect(
          await resolver(node: 'v19.9.0').resolve(known('codex'), env(vars)),
          isA<AgentNeedsNode>(),
        );
      },
    );

    test(
      'node itself is asked for its version, with the login environment and no shell',
      () async {
        final calls = <(String, List<String>, Map<String, String>?)>[];
        final r = resolver(
          probe: (exe, args, {environment}) async {
            calls.add((exe, args, environment));
            return const ProbeResult(0, 'v22.5.0\n');
          },
        );
        await r.resolve(known('claude'), env(vars));
        expect(calls, hasLength(1));
        expect(calls.single.$1, '/usr/local/bin/node');
        expect(calls.single.$2, ['--version']);
        expect(calls.single.$3, vars);
      },
    );

    test('node that does not answer: Node is needed, nothing found', () async {
      final r = await resolver(
        probe: (exe, args, {environment}) async => null,
      ).resolve(known('claude'), env(vars));
      expect(
        r,
        isA<AgentNeedsNode>()
            .having((r) => r.found, 'found', isNull)
            .having((r) => r.required, 'required', 22),
      );
    });

    test(
      'each npm agent installs its own package at its own pin in its own prefix',
      () async {
        for (final (id, package, version) in [
          ('codex', '@agentclientprotocol/codex-acp', '2.2.2'),
          ('gemini', '@google/gemini-cli', '0.64.0'),
        ]) {
          final r =
              await resolver().resolve(known(id), env(vars))
                  as AgentNeedsInstall;
          expect(
            r.install!.args,
            containsAllInOrder(['--prefix', '/support/ai/agents/$id']),
            reason: id,
          );
          expect(r.install!.args.last, '$package@$version', reason: id);
          expect(
            r.install!.workingDirectory,
            '/support/ai/agents/$id',
            reason: id,
          );
        }
        expect(
          resolver().prefixFor(known('claude')),
          '/support/ai/agents/claude',
        );
      },
    );

    test('a PATH agent in a folder the custom env adds', () async {
      fs.executables.add('/custom/bin/agent');
      const spec = AgentSpec(
        id: 'custom:a',
        name: 'A',
        launch: CustomLaunch(command: 'agent', env: {'PATH': '/custom/bin'}),
      );
      final r = await resolver().resolve(spec, env(vars)) as AgentReady;
      expect(r.command.executable, '/custom/bin/agent');
      expect(r.command.environment, {
        'PATH': '/custom/bin',
        'HOME': '/Users/a',
      });
    });
  });

  group('the resolver on Windows', () {
    late _Files fs;
    final vars = {'Path': r'C:\node;C:\tools', 'SystemRoot': r'C:\Windows'};
    AgentResolver resolver() => AgentResolver(
      agentsDir: r'C:\support\ai\agents',
      isWindows: true,
      probe: nodeVersion('v22.1.0'),
      files: fs,
    );

    setUp(() => fs = _Files()..executables.add(r'C:\node\node.exe'));

    test(
      'npm-cli.js missing next to node: install is null, never npm.cmd',
      () async {
        fs.executables.add(r'C:\node\npm.cmd');
        final r =
            await resolver().resolve(known('claude'), env(vars))
                as AgentNeedsInstall;
        expect(r.install, isNull);
      },
    );

    test(
      'the install runs in the agent prefix with the login environment',
      () async {
        fs.files[r'C:\node\node_modules\npm\bin\npm-cli.js'] = '';
        final r =
            await resolver().resolve(known('gemini'), env(vars))
                as AgentNeedsInstall;
        expect(r.install!.workingDirectory, r'C:\support\ai\agents\gemini');
        expect(r.install!.environment, vars);
        expect(r.install!.args.last, '@google/gemini-cli@0.64.0');
      },
    );

    test(
      'an installed package runs with node.exe and the entry in Windows form',
      () async {
        const g =
            r'C:\support\ai\agents\gemini\node_modules\@google\gemini-cli';
        fs.files['$g\\package.json'] =
            '{"version":"0.64.0","bin":{"gemini":"bundle/gemini.js"}}';
        fs.files['$g\\bundle\\gemini.js'] = '';
        final r =
            await resolver().resolve(known('gemini'), env(vars)) as AgentReady;
        expect(r.command.executable, r'C:\node\node.exe');
        expect(r.command.args, ['$g\\bundle\\gemini.js', '--acp']);
      },
    );

    test('a .bat shim alone is shim-only too', () async {
      fs.executables.add(r'C:\tools\opencode.bat');
      expect(
        await resolver().resolve(known('opencode'), env(vars)),
        isA<AgentNotFound>().having((r) => r.shimOnly, 'shimOnly', isTrue),
      );
    });
  });
}
