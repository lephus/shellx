import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart' show AgentPhase;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1b final review: the pane after a folder change (I-6), a restart
/// (I-4) and a stop (M-3).
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<({ProviderContainer container})> workspace(
    WidgetTester t,
    FakeAiRuntimes fakes, {
    List<Override> extra = const [],
    Set<String> folders = const {},
  }) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiFolderExistsProvider.overrideWithValue(
          (path) async => path == testAiCwd || folders.contains(path),
        ),
        ...extra,
      ],
    );
    return (container: w.container);
  }

  TerminalTab tabOf(ProviderContainer c, int id) =>
      c.read(terminalTabsProvider).tabs.firstWhere((x) => x.id == id);

  group('I-6: another folder is a new session', () {
    testWidgets('"Choose folder" on a folder that is gone: the tab opens a '
        'new session in the chosen one, not the old id', (t) async {
      final fakes = FakeAiRuntimes(const FakeScenario(sessionId: 'sess-new'));
      final c = (await workspace(t, fakes)).container;
      final ai = openTestAiTab(
        c,
        cwd: '/gone/project',
        sessionId: 'sess-old',
        title: 'Login fix',
      );
      await t.pumpAndSettle();
      expect(find.text('The project folder no longer exists'), findsOneWidget);
      expect(fakes.launcher.channels, isEmpty);
      await t.tap(find.byKey(const Key('ai.chooseFolder')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
      await t.tap(find.byKey(const Key('ai.folder.use')));
      await t.pumpAndSettle();
      expect(fakes.requests.map((r) => r.cwd), ['/gone/project', testAiCwd]);
      expect(fakes.requests.last.resumeSessionId, isNull);
      final received = fakes.agent().received;
      expect(received, contains('session/new'));
      expect(received.any((r) => r.startsWith('session/load')), isFalse);
      expect(tabOf(c, ai.id).ai!.cwd, testAiCwd);
      expect(tabOf(c, ai.id).ai!.sessionId, 'sess-new');
      expect(tabOf(c, ai.id).label, 'Login fix', reason: 'the name stays');
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('no "Resume session" card for a session that is new', (
      t,
    ) async {
      final fakes = FakeAiRuntimes(const FakeScenario());
      final c = (await workspace(t, fakes)).container;
      openTestAiTab(c, cwd: '/gone/project', sessionId: 'sess-old');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ai.chooseFolder')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
      await t.tap(find.byKey(const Key('ai.folder.use')));
      // Frame by frame: the pane's first line of text, then the new runtime.
      for (var frame = 0; frame < 4; frame++) {
        await t.pump();
        expect(
          find.byKey(const Key('ai.resume')),
          findsNothing,
          reason: 'frame $frame',
        );
      }
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai.composer')), findsOneWidget);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('the same folder, chosen again, keeps its session: it '
        'reopens the one it had', (t) async {
      final fakes = FakeAiRuntimes(const FakeScenario());
      final c = (await workspace(
        t,
        fakes,
        folders: {'/gone/project'},
      )).container;
      final ai = openTestAiTab(c, cwd: '/gone/project', sessionId: 'sess-old');
      await t.pumpAndSettle();
      expect(find.text('The project folder no longer exists'), findsOneWidget);
      await t.tap(find.byKey(const Key('ai.chooseFolder')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('ai.folder.field')),
        '/gone/project',
      );
      await t.tap(find.byKey(const Key('ai.folder.use')));
      await t.pumpAndSettle();
      expect(fakes.requests.map((r) => r.resumeSessionId), [
        'sess-old',
        'sess-old',
      ]);
      expect(tabOf(c, ai.id).ai!.sessionId, 'sess-old');
      await disposeWorkspace(t, c);
    }, variant: mac);
  });

  group('I-4: "Restart agent" looks at the environment again', () {
    testWidgets('the login shell\'s environment is asked for again, so a '
        'Node or git installed since is seen', (t) async {
      final tmp = Directory.systemTemp.createTempSync('ai_restart');
      addTearDown(() => tmp.deleteSync(recursive: true));
      var shells = 0;
      final host = AiHost(
        supportDir: tmp.path,
        clientVersion: 'test',
        env: LoginShellEnv(
          processEnv: const {'PATH': '/usr/bin'},
          isWindows: false,
          run: (_, _, _, _) async {
            shells++;
            return (0, utf8.encode('\x1ePATH=/usr/bin\x00\x1e'));
          },
        ),
      );
      final fakes = FakeAiRuntimes(const FakeScenario());
      final c = (await workspace(
        t,
        fakes,
        extra: [aiHostProvider.overrideWithValue(host)],
      )).container;
      openTestAiTab(c, cwd: testAiCwd);
      await t.pumpAndSettle();
      await host.env.resolve();
      await host.env.resolve();
      expect(shells, 1, reason: 'kept for the whole run');
      await t.tap(find.byKey(const Key('ai.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ai.more.restart')));
      await t.pumpAndSettle();
      expect(fakes.launcher.channels, hasLength(2), reason: 'it restarted');
      await host.env.resolve();
      expect(shells, 2, reason: 'asked again after the restart was chosen');
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('without an AI host (a window of something else) the agent '
        'restarts all the same', (t) async {
      final fakes = FakeAiRuntimes(const FakeScenario());
      final c = (await workspace(t, fakes)).container;
      openTestAiTab(c, cwd: testAiCwd);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ai.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ai.more.restart')));
      await t.pumpAndSettle();
      expect(fakes.launcher.channels, hasLength(2));
      await disposeWorkspace(t, c);
    }, variant: mac);
  });

  group('M-3: "Resume session" only until the session has loaded', () {
    const history = [
      {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Login fixed.'},
      },
    ];

    testWidgets('after a Force stop the conversation is not covered again', (
      t,
    ) async {
      final fakes = FakeAiRuntimes(const FakeScenario(history: history));
      final c = (await workspace(t, fakes)).container;
      openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
      await t.pump();
      expect(find.byKey(const Key('ai.resume')), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      final runtime = fakes.made.single;
      await runtime.forceStop();
      await t.pumpAndSettle();
      expect(runtime.state.phase, AgentPhase.stopped);
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      expect(
        find.textContaining('Login fixed.', findRichText: true),
        findsOneWidget,
      );
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('a restart does not cover it either', (t) async {
      final fakes = FakeAiRuntimes(const FakeScenario(history: history));
      final c = (await workspace(t, fakes)).container;
      openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
      await t.pumpAndSettle();
      final runtime = fakes.made.single;
      await runtime.restart();
      await t.pump();
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      await t.pumpAndSettle();
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('a restored tab that has to sign in first: no card over '
        'the sign-in, none after the session has loaded', (t) async {
      final tmp = Directory.systemTemp.createTempSync('ai_resume');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final signedIn = File('${tmp.path}/signed-in');
      final fakes = FakeAiRuntimes(
        FakeScenario(
          requireAuth: true,
          authFile: signedIn.path,
          authMethods: const [
            {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
          ],
          history: history,
        ),
      );
      final c = (await workspace(t, fakes)).container;
      openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
      await t.pumpAndSettle();
      final runtime = fakes.made.single;
      expect(runtime.state.phase, AgentPhase.needsAuth);
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      signedIn.createSync();
      await runtime.retry();
      await t.pumpAndSettle();
      expect(runtime.state.phase, AgentPhase.ready);
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      expect(
        find.textContaining('Login fixed.', findRichText: true),
        findsOneWidget,
      );
      // Stopped later, the conversation stays.
      await runtime.forceStop();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ai.resume')), findsNothing);
      await disposeWorkspace(t, c);
    }, variant: mac);
  });
}
