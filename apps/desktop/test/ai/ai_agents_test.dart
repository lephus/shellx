import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

void main() {
  late InMemorySettingsStore settings;
  late MemoryConfigFs fs;

  Future<ProviderContainer> container({
    String config = '',
    Future<AgentReadiness> Function(AgentSpec)? source,
  }) async {
    if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
    final c = ProviderContainer.test(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        ...configOverrides(fs),
        aiReadinessSourceProvider.overrideWithValue(
          source ?? (_) async => const AgentNeedsInstall(null),
        ),
      ],
    );
    await loadConfig(c);
    return c;
  }

  setUp(() {
    settings = InMemorySettingsStore();
    fs = MemoryConfigFs();
  });

  test('D23 order; ai-agent-claude = off hides Claude (D21)', () async {
    var c = await container();
    expect(c.read(aiAgentsProvider).map((a) => a.id), [
      'claude',
      'codex',
      'gemini',
      'opencode',
    ]);
    expect(c.read(aiAgentsProvider).first.name, 'Claude');
    c = await container(config: 'ai-agent-claude = off\n');
    expect(
      c.read(aiAgentsProvider).map((a) => a.id),
      isNot(contains('claude')),
    );
  });

  test(
    'custom agents: added, kept, listed after the known ones, removed',
    () async {
      final c = await container();
      final added = await c
          .read(aiCustomAgentsProvider.notifier)
          .add(
            name: ' Mine ',
            command: '/opt/mine',
            args: ['--acp'],
            env: {'A': '1'},
          );
      expect(added.id, matches(RegExp(r'^custom-[0-9a-f]{8}$')));
      expect(c.read(aiAgentsProvider).last.id, added.id);
      expect(c.read(aiAgentsProvider).last.name, 'Mine');
      expect(settings.getStrings(SettingKeys.aiCustomAgents), hasLength(1));
      expect(added.toString(), '…');
      final again = await container();
      final kept = again.read(aiCustomAgentsProvider).single;
      expect(
        [kept.command, kept.args, kept.env],
        [
          '/opt/mine',
          ['--acp'],
          {'A': '1'},
        ],
      );
      await c.read(aiCustomAgentsProvider.notifier).remove(added.id);
      expect(settings.getStrings(SettingKeys.aiCustomAgents), isEmpty);
      expect(CustomAgent.decode('not json'), isNull);
      expect(CustomAgent.decode('{"id":"x","name":"a","command":"b"}'), isNull);
    },
  );

  test('A12 kinds for the known agents only (B5)', () {
    expect(agentKindOf('claude'), AgentKind.claude);
    expect(agentKindOf('opencode'), AgentKind.opencode);
    expect(agentKindOf('custom-0a0b0c0d'), isNull);
  });

  test('the default agent: the choice, else the first ready, else the first '
      '(never a wait, D23)', () async {
    final c = await container(
      source: (a) async => a.id == 'codex'
          ? const AgentReady(AgentCommand(executable: 'node'))
          : const AgentNeedsInstall(null),
    );
    expect(c.read(aiDefaultAgentProvider)?.id, 'claude', reason: 'unknown yet');
    await c.read(aiReadinessProvider.notifier).warmUp();
    expect(c.read(aiReadinessProvider), hasLength(4));
    expect(c.read(aiDefaultAgentProvider)?.id, 'codex');
    await c.read(aiDefaultAgentChoiceProvider.notifier).set('gemini');
    expect(c.read(aiDefaultAgentProvider)?.id, 'gemini');
    expect(settings.getStrings(SettingKeys.aiDefaultAgent), ['gemini']);
  });

  test('warm-up runs once; refresh runs again', () async {
    var calls = 0;
    final c = await container(
      source: (_) async {
        calls++;
        return const AgentNeedsInstall(null);
      },
    );
    final notifier = c.read(aiReadinessProvider.notifier);
    await Future.wait([notifier.warmUp(), notifier.warmUp()]);
    expect(calls, 4);
    await notifier.refresh();
    expect(calls, 8);
  });

  test('remembered choices per agent; Bypass permissions never (R6)', () async {
    await rememberConfig(settings, 'claude', 'model', 'opus');
    await rememberConfig(settings, 'claude', 'mode', 'acceptEdits');
    await rememberConfig(settings, 'claude', 'mode', 'bypassPermissions');
    await rememberConfig(settings, 'codex', 'model', 'gpt');
    expect(rememberedConfig(settings, 'claude'), {
      'model': 'opus',
      'mode': 'acceptEdits',
    });
    await rememberConfig(settings, 'claude', 'model', 'sonnet');
    expect(rememberedConfig(settings, 'claude')['model'], 'sonnet');
    expect(rememberedConfig(settings, 'codex'), {'model': 'gpt'});
  });
}
