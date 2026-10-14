import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/ui/ai/ai_agents_section.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import 'ai_run_sheet_test.dart' show SheetPtys;

const _install = AgentCommand(
  executable: '/usr/local/bin/node',
  args: ['/usr/local/lib/node_modules/npm/bin/npm-cli.js', 'install'],
  environment: {'TERM': 'dumb'},
  workingDirectory: '/support/ai/agents/codex',
);

/// V2-1 D7, D12, D21, D23: Settings › Agents › AI interface.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> openAgents(WidgetTester t, ProviderContainer c) async {
    c.read(settingsStartPageProvider.notifier).set(SettingPage.agents);
    c.read(configUiRequestProvider.notifier).request(ConfigUiRequest.settings);
    await t.pumpAndSettle();
    expect(find.byType(AgentsPage), findsOneWidget);
  }

  /// Scrolls Agents until [target] is built (a lazy list), then to it.
  Future<void> reveal(WidgetTester t, Finder target) async {
    final list = find
        .descendant(
          of: find.byType(AgentsPage),
          matching: find.byType(ListView),
        )
        .first;
    for (var n = 0; n < 24 && target.evaluate().isEmpty; n++) {
      await t.drag(list, const Offset(0, -200));
      await t.pump();
    }
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }

  String status(WidgetTester t, String id) =>
      t.widget<Text>(find.byKey(Key('ai.agent.status.$id'))).data!;

  testWidgets('one row per agent with its state; Install runs in the run '
      'sheet; the default agent', (t) async {
    var installed = false;
    final ptys = SheetPtys();
    final made = <String>[];
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (agent) async => switch (agent.id) {
            'claude' => const AgentReady(AgentCommand(executable: 'node')),
            'codex' =>
              installed
                  ? const AgentReady(AgentCommand(executable: 'node'))
                  : const AgentNeedsInstall(_install),
            'gemini' => const AgentNeedsNode(required: 20, found: 'v18.0.0'),
            _ => const AgentNotFound('opencode'),
          },
        ),
        aiPtyFactoryProvider.overrideWithValue(ptys),
        aiMakeFolderProvider.overrideWithValue((path) async => made.add(path)),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.defaultAgent')));
    expect(status(t, 'claude'), 'Ready');
    expect(status(t, 'codex'), 'Not installed');
    expect(status(t, 'gemini'), 'Needs Node 20');
    expect(status(t, 'opencode'), 'Not installed');
    expect(find.text('Command not found: opencode'), findsOneWidget);
    await reveal(t, find.byKey(const Key('ai.agent.install.codex')));
    await t.tap(find.byKey(const Key('ai.agent.install.codex')));
    await t.pumpAndSettle();
    expect(find.text('Install Codex'), findsOneWidget);
    expect(made, ['/support/ai/agents/codex']);
    final run = ptys.spawned.single;
    expect(run.command.executable, '/usr/local/bin/node');
    expect(run.env['TERM'], 'xterm-256color');
    installed = true;
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(status(t, 'codex'), 'Ready');
    await reveal(t, find.byKey(const Key('ai.defaultAgent')));
    await t.tap(find.byKey(const Key('ai.defaultAgent')));
    await t.pumpAndSettle();
    await t.tap(find.text('Codex').last);
    await t.pumpAndSettle();
    expect(c.read(aiDefaultAgentChoiceProvider), 'codex');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a custom agent needs a name and a command; it is added with '
      'its args and env, and removed', (t) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNotFound('x'),
        ),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.custom.save')));
    await t.tap(find.byKey(const Key('ai.custom.save')));
    await t.pumpAndSettle();
    expect(find.text('Enter a name and a command.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.custom.name')), 'Local');
    await t.enterText(
      find.byKey(const Key('ai.custom.command')),
      '/usr/local/bin/my-agent',
    );
    await t.enterText(find.byKey(const Key('ai.custom.args')), 'acp\n--fast');
    await t.enterText(find.byKey(const Key('ai.custom.env')), 'TOKEN=x\nBAD');
    await t.tap(find.byKey(const Key('ai.custom.save')));
    await t.pumpAndSettle();
    final agent = c.read(aiCustomAgentsProvider).single;
    expect(agent.name, 'Local');
    expect(agent.command, '/usr/local/bin/my-agent');
    expect(agent.args, ['acp', '--fast']);
    expect(agent.env, {'TOKEN': 'x'});
    await reveal(t, find.byKey(Key('ai.agent.remove.${agent.id}')));
    await t.tap(find.byKey(Key('ai.agent.remove.${agent.id}')));
    await t.pumpAndSettle();
    expect(c.read(aiCustomAgentsProvider), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the Claude switch and "Delete all restore points" (asked '
      'first)', (t) async {
    var deleted = 0;
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNotFound('x'),
        ),
        aiDeleteCheckpointsProvider.overrideWithValue(() async => deleted++),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.checkpoints')));
    expect(find.byKey(const ValueKey('row.ai-agent-claude')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('ai.checkpoints')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Delete all restore points?'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.checkpoints.delete')));
    await t.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('Restore points deleted.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Sign in runs the agent\'s own login from the session that '
      'met it; the session opens', (t) async {
    final auth = Directory.systemTemp.createTempSync('ai_auth');
    addTearDown(() => auth.deleteSync(recursive: true));
    final fakes = FakeAiRuntimes(
      FakeScenario(
        requireAuth: true,
        authFile: '${auth.path}/signed-in',
        authMethods: const [
          {
            'id': 'login',
            'name': 'Log in',
            'type': 'terminal',
            'args': ['/login'],
          },
        ],
      ),
    );
    final ptys = SheetPtys();
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [...fakes.overrides, aiPtyFactoryProvider.overrideWithValue(ptys)],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    expect(fakes.made.single.state.phase, AgentPhase.needsAuth);
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.agent.signin.claude')));
    expect(status(t, 'claude'), 'Needs sign-in');
    await t.tap(find.byKey(const Key('ai.agent.signin.claude')));
    await t.pumpAndSettle();
    final run = ptys.spawned.single;
    expect(run.command.arguments, ['/login']);
    File('${auth.path}/signed-in').writeAsStringSync('ok');
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    expect(status(t, 'claude'), 'Ready');
    await disposeWorkspace(t, c);
  }, variant: mac);
}
