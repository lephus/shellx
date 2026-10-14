import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

/// An in-memory file system for both platforms.
final class FakeFiles implements FileProbe {
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

LoginEnv env(Map<String, String> vars) =>
    LoginEnv(vars, source: LoginEnvSource.interactiveLogin);
AgentSpec known(String id) => kKnownAgents.firstWhere((a) => a.id == id);
ProbeRunner nodeVersion(String v) =>
    (exe, args, {environment}) async => ProbeResult(0, '$v\n');

void main() {
  test('the pins (spec D6): bump only on purpose', () {
    final npm = {
      for (final a in kKnownAgents)
        if (a.launch is NpmLaunch) a.id: a.launch as NpmLaunch,
    };
    expect(kKnownAgents.map((a) => a.id), [
      'claude',
      'codex',
      'gemini',
      'opencode',
    ]);
    expect(npm['claude']!.package, '@agentclientprotocol/claude-agent-acp');
    expect(npm['claude']!.version, '0.90.0');
    expect(npm['claude']!.minNode, 22);
    expect(npm['codex']!.version, '2.2.2');
    expect(npm['gemini']!.version, '0.64.0');
    expect(npm['gemini']!.args, ['--acp']);
    expect((known('opencode').launch as PathLaunch).args, ['acp']);
    expect(
      known('claude').name,
      'Claude',
      reason: 'never "Claude Code" (spec D21)',
    );
  });

  group('POSIX', () {
    late FakeFiles fs;
    final vars = {'PATH': '/usr/local/bin:/usr/bin', 'HOME': '/Users/a'};
    const pkg =
        '/support/ai/agents/claude/node_modules/@agentclientprotocol/claude-agent-acp';
    AgentResolver resolver({String node = 'v22.12.0'}) => AgentResolver(
      agentsDir: '/support/ai/agents',
      isWindows: false,
      probe: nodeVersion(node),
      files: fs,
    );

    setUp(
      () =>
          fs = FakeFiles()
            ..executables.addAll({'/usr/local/bin/node', '/usr/local/bin/npm'}),
    );

    test('no node: needs Node 22, none found', () async {
      fs.executables.clear();
      final r = await resolver().resolve(known('claude'), env(vars));
      expect(
        r,
        isA<AgentNeedsNode>()
            .having((r) => r.found, 'found', isNull)
            .having((r) => r.required, 'required', 22),
      );
    });

    test('node 20 is too old for Claude but fine for Codex', () async {
      expect(
        await resolver(node: 'v20.11.1').resolve(known('claude'), env(vars)),
        isA<AgentNeedsNode>().having((r) => r.found, 'found', 'v20.11.1'),
      );
      expect(
        await resolver(node: 'v20.11.1').resolve(known('codex'), env(vars)),
        isA<AgentNeedsInstall>(),
      );
    });

    test(
      'not installed: the npm install command, in the agent prefix',
      () async {
        final r =
            await resolver().resolve(known('claude'), env(vars))
                as AgentNeedsInstall;
        final c = r.install!;
        expect(c.executable, '/usr/local/bin/npm');
        expect(c.args, [
          'install',
          '--prefix',
          '/support/ai/agents/claude',
          '--no-audit',
          '--no-fund',
          '--save-exact',
          '@agentclientprotocol/claude-agent-acp@0.90.0',
        ]);
        expect(c.workingDirectory, '/support/ai/agents/claude');
        expect(c.environment, vars);
      },
    );

    test(
      'installed at the pin: node runs the package bin, no shell, no npx',
      () async {
        fs.files['$pkg/package.json'] =
            '{"version":"0.90.0","bin":{"claude-agent-acp":"dist/index.js"}}';
        fs.files['$pkg/dist/index.js'] = '';
        final r =
            await resolver().resolve(known('claude'), env(vars)) as AgentReady;
        expect(r.command.executable, '/usr/local/bin/node');
        expect(r.command.args, ['$pkg/dist/index.js']);
        expect(r.command.environment, vars);
      },
    );

    test('installed at another version: install again', () async {
      fs.files['$pkg/package.json'] =
          '{"version":"0.89.0","bin":"dist/index.js"}';
      fs.files['$pkg/dist/index.js'] = '';
      expect(
        await resolver().resolve(known('claude'), env(vars)),
        isA<AgentNeedsInstall>(),
      );
    });

    test('Gemini: the bin from package.json, then --acp', () async {
      const g = '/support/ai/agents/gemini/node_modules/@google/gemini-cli';
      fs.files['$g/package.json'] =
          '{"version":"0.64.0","bin":{"gemini":"bundle/gemini.js"}}';
      fs.files['$g/bundle/gemini.js'] = '';
      final r =
          await resolver().resolve(known('gemini'), env(vars)) as AgentReady;
      expect(r.command.args, ['$g/bundle/gemini.js', '--acp']);
    });

    test('npm missing: install is null', () async {
      fs.executables.remove('/usr/local/bin/npm');
      final r =
          await resolver().resolve(known('claude'), env(vars))
              as AgentNeedsInstall;
      expect(r.install, isNull);
    });

    test('a PATH agent', () async {
      expect(
        await resolver().resolve(known('opencode'), env(vars)),
        isA<AgentNotFound>().having((r) => r.shimOnly, 'shim', isFalse),
      );
      fs.executables.add('/usr/bin/opencode');
      final r =
          await resolver().resolve(known('opencode'), env(vars)) as AgentReady;
      expect(
        [r.command.executable, ...r.command.args],
        ['/usr/bin/opencode', 'acp'],
      );
    });

    test(
      'a custom agent: absolute command, its env over the login env',
      () async {
        fs.executables.add('/opt/my/agent');
        const spec = AgentSpec(
          id: 'custom:mine',
          name: 'Mine',
          launch: CustomLaunch(
            command: '/opt/my/agent',
            args: ['--acp'],
            env: {'HOME': '/elsewhere', 'TOKEN_FILE': '/x'},
          ),
        );
        final r = await resolver().resolve(spec, env(vars)) as AgentReady;
        expect(r.command.args, ['--acp']);
        expect(r.command.environment, {
          'PATH': '/usr/local/bin:/usr/bin',
          'HOME': '/elsewhere',
          'TOKEN_FILE': '/x',
        });
      },
    );
  });

  group('Windows', () {
    late FakeFiles fs;
    final vars = {'Path': r'C:\node;C:\tools', 'SystemRoot': r'C:\Windows'};
    AgentResolver resolver() => AgentResolver(
      agentsDir: r'C:\support\ai\agents',
      isWindows: true,
      probe: nodeVersion('v22.1.0'),
      files: fs,
    );

    setUp(() => fs = FakeFiles()..executables.add(r'C:\node\node.exe'));

    test('install runs npm-cli.js with node, never npm.cmd', () async {
      fs.files[r'C:\node\node_modules\npm\bin\npm-cli.js'] = '';
      final r =
          await resolver().resolve(known('claude'), env(vars))
              as AgentNeedsInstall;
      expect(r.install!.executable, r'C:\node\node.exe');
      expect(r.install!.args.take(4), [
        r'C:\node\node_modules\npm\bin\npm-cli.js',
        'install',
        '--prefix',
        r'C:\support\ai\agents\claude',
      ]);
    });

    test('a .cmd shim alone is not run', () async {
      fs.executables.add(r'C:\tools\opencode.cmd');
      expect(
        await resolver().resolve(known('opencode'), env(vars)),
        isA<AgentNotFound>().having((r) => r.shimOnly, 'shim', isTrue),
      );
      fs.executables.add(r'C:\tools\opencode.exe');
      final r =
          await resolver().resolve(known('opencode'), env(vars)) as AgentReady;
      expect(r.command.executable, r'C:\tools\opencode.exe');
    });
  });

  test('AgentCommand.withArgs adds a login method args and env (spec D8)', () {
    const c = AgentCommand(
      executable: 'node',
      args: ['index.js'],
      environment: {'A': '1'},
    );
    final login = c.withArgs(['--cli', 'auth', 'login'], {'B': '2'});
    expect(login.args, ['index.js', '--cli', 'auth', 'login']);
    expect(login.environment, {'A': '1', 'B': '2'});
    expect(c.toString(), '…');
  });

  test('findExecutable on the real file system', () {
    final dir = Directory.systemTemp.createTempSync('which');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/tool').writeAsStringSync('#!/bin/sh\n');
    File('${dir.path}/plain').writeAsStringSync('');
    Process.runSync('chmod', ['+x', '${dir.path}/tool']);
    final vars = {'PATH': '/nonexistent:${dir.path}'};
    expect(findExecutable('tool', vars, isWindows: false), '${dir.path}/tool');
    expect(
      findExecutable('plain', vars, isWindows: false),
      isNull,
      reason: 'not executable',
    );
    expect(
      findExecutable('${dir.path}/tool', const {}, isWindows: false),
      '${dir.path}/tool',
    );
  }, testOn: '!windows');
}
