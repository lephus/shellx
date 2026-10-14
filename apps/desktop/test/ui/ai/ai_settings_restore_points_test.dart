import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/ui/ai/ai_agents_section.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1 D12, D7: Settings › Agents — "Delete all restore points" only when
/// no turn runs and it says when it cannot; the agents are checked again
/// from the login shell's environment as it is now.
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

  Future<void> deleteAllRestorePoints(WidgetTester t) async {
    await reveal(t, find.byKey(const Key('ai.checkpoints')));
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
  }

  Finder caption(String text) => find.descendant(
    of: find.byKey(const Key('ai.checkpoints')),
    matching: find.text(text),
  );

  testWidgets('a turn runs somewhere: nothing is deleted, the row says to '
      'wait; once it ended the delete goes through', (t) async {
    var deleted = 0;
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
        ],
      ),
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiDeleteCheckpointsProvider.overrideWithValue(() async => deleted++),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(fakes.made.single.state.turn, isNotNull, reason: 'a turn runs');
    await openAgents(t, c);
    await deleteAllRestorePoints(t);
    expect(deleted, 0, reason: 'its precondition: no turn may be running');
    expect(caption('Wait for the running turn to finish.'), findsOneWidget);
    expect(caption('Restore points deleted.'), findsNothing);
    fakes.made.single.cancel();
    await t.pumpAndSettle();
    await deleteAllRestorePoints(t);
    expect(deleted, 1);
    expect(caption('Restore points deleted.'), findsOneWidget);
    expect(caption('Wait for the running turn to finish.'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a delete that fails is said, not only logged', (t) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNotFound('x'),
        ),
        aiDeleteCheckpointsProvider.overrideWithValue(
          () async => throw const FileSystemException('busy'),
        ),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await deleteAllRestorePoints(t);
    expect(
      caption('Something went wrong (restore-points). Try again.'),
      findsOneWidget,
    );
    expect(caption('Restore points deleted.'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('opening Settings › Agents checks the agents against the login '
      'shell\'s environment as it is now (a Node installed after launch)', (
    t,
  ) async {
    final shells = <String>[];
    final env = LoginShellEnv(
      shell: '/bin/zsh',
      processEnv: const {'PATH': '/usr/bin'},
      isWindows: false,
      run: (shell, args, environment, timeout) async {
        shells.add(shell);
        return (0, utf8.encode('\x1ePATH=/usr/bin\x00\x1e'));
      },
    );
    final support = Directory.systemTemp.createTempSync('ai_env');
    addTearDown(() => support.deleteSync(recursive: true));
    final host = AiHost(
      supportDir: support.path,
      clientVersion: 'test',
      env: env,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiHostProvider.overrideWithValue(host),
        // What the real source does first: the environment.
        aiReadinessSourceProvider.overrideWithValue((agent) async {
          await host.env.resolve();
          return const AgentReady(AgentCommand(executable: 'node'));
        }),
      ],
    );
    final c = w.container;
    await env.resolve(); // the app resolved it once, at launch
    expect(shells, hasLength(1));
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.settings')));
    expect(shells, hasLength(2), reason: 'the section forgot the cached one');
    await disposeWorkspace(t, c);
  }, variant: mac);
}
