import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/integration_probe.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';

/// A file system of text: reads only, and records what was read.
final class FakeFs implements IntegrationFs {
  final files = <String, String>{};
  final dirs = <String>{};
  final read = <String>[];
  Object? readError;

  @override
  Future<String?> readText(String path) async {
    read.add(path);
    final error = readError;
    if (error != null) throw error;
    return files[path];
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || dirs.contains(path);
}

const subs = [
  'session-start',
  'prompt-submit',
  'notification',
  'stop',
  'session-end',
];

String hooks(String agent, [List<String> only = subs]) =>
    '{\n  "hooks": {\n${[for (final s in only) '    "$s": [{"hooks": [{"type": "command", "command": "shellx agent-event $agent $s"}]}]'].join(',\n')}\n  }\n}\n';

const codexLine =
    'notify = ["shellx", "agent-event", "codex", "turn-complete"]';
const opencodePlugin =
    '// shellx-agent-integration v1 (managed by "shellx integrations")\nexport const ShellxAgent = async () => ({})\n';

IntegrationProbe probe(
  FakeFs fs, {
  Map<String, String> env = const {},
  bool windows = false,
}) => IntegrationProbe(fs: fs, env: env, home: '/h', windows: windows);

Future<bool> installed(IntegrationProbe p, AgentKind a) async =>
    (await p.probe())[a]!.installed;

void main() {
  test('every agent installed on the fixtures the CLI writes', () async {
    final fs = FakeFs()
      ..files['/h/.claude/settings.json'] = hooks('claude')
      ..files['/h/.gemini/settings.json'] = hooks('gemini')
      ..files['/h/.codex/config.toml'] = '# mine\n$codexLine\n'
      ..files['/h/.config/opencode/plugins/shellx-agent.js'] = opencodePlugin;
    final all = await probe(fs).probe();
    expect(all.keys.toSet(), AgentKind.values.toSet());
    for (final a in AgentKind.values) {
      expect(all[a]!.installed, isTrue, reason: '$a');
    }
  });

  test(
    'not installed: no file, hooks of the user only, a partial set, '
    'another agent\'s hooks, another notify, a plugin that is not ours',
    () async {
      final fs = FakeFs();
      final p = probe(fs);
      for (final a in AgentKind.values) {
        expect(await installed(p, a), isFalse, reason: 'no file $a');
      }
      fs
        ..files['/h/.claude/settings.json'] =
            '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine"}]}]}}'
        ..files['/h/.gemini/settings.json'] = hooks('gemini', subs.sublist(1))
        ..files['/h/.codex/config.toml'] =
            'notify = ["my-notifier", "agent-event", "codex"]\n'
        ..files['/h/.config/opencode/plugins/shellx-agent.js'] =
            'export const Mine = async () => ({})\n';
      for (final a in AgentKind.values) {
        expect(await installed(p, a), isFalse, reason: 'foreign $a');
      }
      // One agent's hooks in another's file do not count.
      fs.files['/h/.claude/settings.json'] = hooks('gemini');
      expect(await installed(p, AgentKind.claude), isFalse);
      // Four of the five hooks are not installed.
      fs.files['/h/.claude/settings.json'] = hooks('claude', subs.sublist(1));
      expect(await installed(p, AgentKind.claude), isFalse);
      fs.files['/h/.claude/settings.json'] = hooks('claude');
      expect(await installed(p, AgentKind.claude), isTrue);
    },
  );

  test('unreadable or throwing reads mean not installed, never an error, '
      'and nothing is logged', () async {
    final log = <String>[];
    final saved = debugPrint;
    debugPrint = (m, {wrapWidth}) => log.add(m ?? '');
    addTearDown(() => debugPrint = saved);
    final fs = FakeFs()
      ..files['/h/.claude/settings.json'] = hooks('claude')
      ..readError = const FileSystemException('secret-path-token');
    final all = await probe(fs).probe();
    for (final a in AgentKind.values) {
      expect(all[a]!.installed, isFalse);
    }
    expect(log, isEmpty);
  });

  test(
    'a file over 1 MiB reads as not installed (the CLI refuses it too)',
    () async {
      final dir = Directory.systemTemp.createTempSync('probe');
      addTearDown(() => dir.deleteSync(recursive: true));
      final big = File('${dir.path}/settings.json')
        ..writeAsStringSync(
          '${hooks('claude')}${' ' * (kIntegrationFileMax + 1)}',
        );
      final small = File('${dir.path}/small.json')
        ..writeAsStringSync(hooks('claude'));
      const fs = DiskIntegrationFs();
      expect(await fs.readText(big.path), isNull);
      expect(await fs.readText(small.path), contains('agent-event claude'));
      expect(await fs.readText('${dir.path}/missing'), isNull);
      expect(await fs.exists(dir.path), isTrue);
      expect(await fs.exists('${dir.path}/missing'), isFalse);
      // Not text.
      final bin = File('${dir.path}/bin')..writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect(await fs.readText(bin.path), isNull);
    },
  );

  test(
    'the folders follow CLAUDE_CONFIG_DIR, CODEX_HOME and '
    'OPENCODE_CONFIG_DIR; empty values are ignored; Gemini is fixed',
    () async {
      final fs = FakeFs()
        ..files['/c/settings.json'] = hooks('claude')
        ..files['/x/config.toml'] = codexLine
        ..files['/o/plugins/shellx-agent.js'] = opencodePlugin
        ..files['/h/.gemini/settings.json'] = hooks('gemini');
      final p = probe(
        fs,
        env: {
          'CLAUDE_CONFIG_DIR': '/c',
          'CODEX_HOME': '/x',
          'OPENCODE_CONFIG_DIR': '/o',
          'GEMINI_HOME': '/nowhere',
        },
      );
      for (final a in AgentKind.values) {
        expect(await installed(p, a), isTrue, reason: '$a');
      }
      final empty = probe(fs, env: {'CLAUDE_CONFIG_DIR': '', 'CODEX_HOME': ''});
      expect(await installed(empty, AgentKind.claude), isFalse);
      expect(await installed(empty, AgentKind.codex), isFalse);
    },
  );

  test(
    'reads only: the probe asks for the agents\' files and no other',
    () async {
      final fs = FakeFs();
      await probe(fs).probe();
      expect(fs.read.toSet(), {
        '/h/.claude/settings.json',
        '/h/.codex/config.toml',
        '/h/.gemini/settings.json',
        '/h/.config/opencode/plugins/shellx-agent.js',
      });
    },
  );

  group('"not found"', () {
    test(
      'only when neither the agent\'s folder nor its program is found',
      () async {
        final fs = FakeFs();
        var all = await probe(fs).probe();
        for (final a in AgentKind.values) {
          expect(all[a]!.notFound, isTrue, reason: '$a');
        }
        fs.dirs.add('/h/.claude');
        all = await probe(fs).probe();
        expect(all[AgentKind.claude]!.notFound, isFalse);
        expect(all[AgentKind.codex]!.notFound, isTrue);
        fs.files['/opt/homebrew/bin/codex'] = '';
        fs.files['/h/.npm-global/bin/gemini'] = '';
        fs.files['/h/.claude/local/opencode'] = '';
        all = await probe(fs).probe();
        expect(all[AgentKind.codex]!.notFound, isFalse);
        expect(all[AgentKind.gemini]!.notFound, isFalse);
        expect(all[AgentKind.opencode]!.notFound, isFalse);
      },
    );

    test('an installed integration is never "not found"', () async {
      final fs = FakeFs()..files['/h/.codex/config.toml'] = codexLine;
      expect((await probe(fs).probe())[AgentKind.codex]!.notFound, isFalse);
    });

    test(
      'on Windows it is never claimed (the programs are not located)',
      () async {
        final all = await probe(FakeFs(), windows: true).probe();
        for (final a in AgentKind.values) {
          expect(all[a]!.notFound, isFalse);
        }
      },
    );
  });

  test('the command is fixed words and a name from the closed set', () {
    expect(
      integrationCommand(AgentKind.claude, remove: false),
      'shellx integrations install claude',
    );
    expect(
      integrationCommand(AgentKind.opencode, remove: true),
      'shellx integrations uninstall opencode',
    );
    expect(
      integrationCommand(
        AgentKind.claude,
        remove: false,
        program: "'/a b/shellx'",
      ),
      "'/a b/shellx' integrations install claude",
    );
    for (final a in AgentKind.values) {
      expect(
        integrationCommand(a, remove: false),
        isNot(contains('--yes')),
        reason: 'consent is the CLI\'s',
      );
    }
  });

  test('toString shows nothing', () async {
    final all = await probe(FakeFs()).probe();
    expect(all[AgentKind.claude].toString(), '…');
  });

  test('the probe has no way to write', () {
    final source = File(
      'lib/src/integrations/integration_probe.dart',
    ).readAsStringSync();
    for (final bad in [
      'writeAs',
      'openWrite',
      '.rename(',
      '.delete(',
      'createSync',
      'create(',
      'Process.',
    ]) {
      expect(source, isNot(contains(bad)), reason: bad);
    }
  });
}
