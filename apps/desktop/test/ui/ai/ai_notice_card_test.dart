import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/ui/ai/ai_notice_card.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  testWidgets('sign-in: one button per method; a terminal one asks for the '
      'run sheet (D8)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state.addNotice(
      const LoginNeeded([
        AuthMethodTerminal(id: 'claude-login', name: 'Log in with Claude'),
        AuthMethodAgent(id: 'api', name: 'Use an API key'),
      ]),
    );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    final asked = <AiRunRequest>[];
    w.ui.onRun = asked.add;
    await t.pump();
    expect(find.text('Claude needs you to sign in'), findsOneWidget);
    expect(find.text('Use an API key'), findsOneWidget);
    await t.tap(find.text('Log in with Claude'));
    expect((asked.single as AiRunLogin).method.id, 'claude-login');
  });

  testWidgets('the others of §4.5: Node, install, exit, resume, folder, undo', (
    t,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..addNotice(const NodeMissing(required: 22, found: 'v20.1.0'))
      ..addNotice(const AgentNotInstalled())
      ..addNotice(const AgentExited(1))
      ..addNotice(const CannotResume())
      ..addNotice(const FolderMissing())
      ..addNotice(const UndoUnavailable(UndoOff.tooManyFiles))
      ..addNotice(const AgentMissing('opencode', shimOnly: true));
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    final asked = <AiRunRequest>[];
    var folder = 0;
    w.ui
      ..onRun = asked.add
      ..onChooseFolder = () => folder++;
    await t.pump();
    expect(find.text('Claude needs Node.js 22 or newer'), findsOneWidget);
    expect(find.text('Claude is not installed'), findsOneWidget);
    expect(find.text('Claude stopped unexpectedly (exit 1)'), findsOneWidget);
    expect(find.textContaining('cannot restore'), findsOneWidget);
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    expect(
      find.text('Undo is off for this project (more than 200,000 files)'),
      findsOneWidget,
    );
    expect(find.textContaining('.cmd or .bat'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.node.guide')));
    await t.tap(find.byKey(const Key('ai.install')));
    await t.tap(find.byKey(const Key('ai.chooseFolder')));
    await t.pump();
    expect(w.harness.urlOpener.opened.single, kNodeDownloadPage);
    expect(asked.single, isA<AiRunInstall>());
    expect(folder, 1);
    await t.tap(find.byKey(const Key('ai.log')));
    await t.pumpAndSettle();
    expect(find.text('(empty)'), findsOneWidget);
  });

  testWidgets('turn summaries: changes, stopped, interrupted (spec §4.2)', (
    t,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    s.beginTurn([const TextBlock('one')], at);
    s.endTurn(
      outcome: TurnOutcome.finished,
      at: at.add(const Duration(seconds: 41)),
      changes: const [
        FileChange(
          path: 'a.ts',
          kind: ChangeKind.modified,
          added: 40,
          removed: 5,
        ),
        FileChange(path: 'b.ts', kind: ChangeKind.added, added: 4, removed: 0),
      ],
    );
    s.beginTurn([const TextBlock('two')], at);
    s.endTurn(
      outcome: TurnOutcome.cancelled,
      at: at.add(const Duration(seconds: 5)),
    );
    s.beginTurn([const TextBlock('three')], at);
    s.endTurn(
      outcome: TurnOutcome.interrupted,
      at: at.add(const Duration(seconds: 2)),
    );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('Turn 1 · 0:41 · 2 files changed'), findsOneWidget);
    expect(find.text('+44'), findsOneWidget);
    expect(find.text('−5'), findsOneWidget);
    expect(find.text('Stopped turn 2 · 0:05'), findsOneWidget);
    expect(find.text('Turn 3 was interrupted · 0:02'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.turn.view')));
    expect(w.ui.panelOpen, isTrue);
  });

  group('the user can do something about a card (final review I-4, I-6)', () {
    /// A host whose login environment counts how often the shell was asked.
    ({AiHost host, int Function() runs}) countingHost() {
      final tmp = Directory.systemTemp.createTempSync('notice_card');
      addTearDown(() => tmp.deleteSync(recursive: true));
      var runs = 0;
      final host = AiHost(
        supportDir: tmp.path,
        clientVersion: 'test',
        env: LoginShellEnv(
          processEnv: const {'PATH': '/usr/bin'},
          isWindows: false,
          run: (shell, args, environment, timeout) async {
            runs++;
            return (0, utf8.encode('\x1ePATH=/usr/bin\x00\x1e'));
          },
        ),
      );
      return (host: host, runs: () => runs);
    }

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.pump();
      }
    }

    for (final (name, readiness, shows) in <(String, AgentReadiness, String)>[
      (
        'Node is missing',
        const AgentNeedsNode(required: 22, found: 'v20.1.0'),
        'Claude needs Node.js 22 or newer',
      ),
      (
        'the agent command is not found',
        const AgentNotFound('claude'),
        'Command not found: claude',
      ),
      (
        'the agent cannot be installed (no npm)',
        const AgentNeedsInstall(null),
        'Claude is not installed',
      ),
    ]) {
      testWidgets('Check again when $name: the environment is asked again, '
          'then the start is tried again', (t) async {
        final fakes = FakeAiRuntimes(
          const FakeScenario(),
          readiness: readiness,
        );
        final runtime = partRuntime(fakes);
        await runtime.start();
        expect(runtime.state.phase, AgentPhase.failed);
        final h = countingHost();
        await h.host.env.resolve();
        expect(h.runs(), 1);
        await pumpAiPart(
          t,
          const AiTimeline(),
          runtime: runtime,
          overrides: [aiHostProvider.overrideWithValue(h.host)],
        );
        await t.pump();
        expect(find.textContaining(shows), findsOneWidget);
        expect(find.byKey(const Key('ai.checkAgain')), findsOneWidget);
        expect(find.text('Check again'), findsOneWidget);

        fakes.readiness = null; // the user installs it
        await t.tap(find.byKey(const Key('ai.checkAgain')));
        await settle(t);

        await h.host.env.resolve();
        expect(
          h.runs(),
          2,
          reason: 'the environment was forgotten, then asked',
        );
        expect(runtime.state.phase, AgentPhase.ready);
        expect(find.byKey(const Key('ai.checkAgain')), findsNothing);
        await runtime.dispose();
      });
    }

    testWidgets('Check again that finds nothing: the card is there again', (
      t,
    ) async {
      final fakes = FakeAiRuntimes(
        const FakeScenario(),
        readiness: const AgentNeedsNode(required: 22),
      );
      final runtime = partRuntime(fakes);
      await runtime.start();
      final h = countingHost();
      await pumpAiPart(
        t,
        const AiTimeline(),
        runtime: runtime,
        overrides: [aiHostProvider.overrideWithValue(h.host)],
      );
      await t.pump();
      await t.tap(find.byKey(const Key('ai.checkAgain')));
      await settle(t);
      expect(runtime.state.phase, AgentPhase.failed);
      expect(find.byKey(const Key('ai.checkAgain')), findsOneWidget);
      expect(
        find.text('Claude needs Node.js 22 or newer'),
        findsNWidgets(2),
        reason: 'the old card folded to a line, the new one asks again',
      );
    });

    testWidgets('Check again with no AI host in the window still tries again', (
      t,
    ) async {
      final fakes = FakeAiRuntimes(
        const FakeScenario(),
        readiness: const AgentNotFound('claude'),
      );
      final runtime = partRuntime(fakes);
      await runtime.start();
      await pumpAiPart(t, const AiTimeline(), runtime: runtime);
      await t.pump();
      fakes.readiness = null;
      await t.tap(find.byKey(const Key('ai.checkAgain')));
      await settle(t);
      expect(runtime.state.phase, AgentPhase.ready);
      await runtime.dispose();
    });

    testWidgets(
      'an agent that can be installed gets Install, not Check again',
      (t) async {
        final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
        runtime.state.addNotice(const AgentNotInstalled());
        await pumpAiPart(t, const AiTimeline(), runtime: runtime);
        await t.pump();
        expect(find.byKey(const Key('ai.install')), findsOneWidget);
        expect(find.byKey(const Key('ai.checkAgain')), findsNothing);
      },
    );

    for (final (platform, hint) in [
      (TargetPlatform.windows, true),
      (TargetPlatform.macOS, false),
    ]) {
      testWidgets(
        'the restart hint under the button: $platform',
        (t) async {
          final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
          runtime.state
            ..addNotice(const NodeMissing(required: 22))
            ..addNotice(const AgentMissing('opencode'))
            ..addNotice(const AgentNotInstalled(canInstall: false))
            ..addNotice(const AgentExited(1));
          await pumpAiPart(t, const AiTimeline(), runtime: runtime);
          await t.pump();
          expect(
            find.text(
              'Still not found? Restart ShellX so it sees the new PATH.',
            ),
            hint ? findsNWidgets(3) : findsNothing,
            reason: 'on the Node card, the agent card and the no-npm card only',
          );
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }

    testWidgets(
      'the hint sits under the buttons of its card (Windows)',
      (t) async {
        final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
        runtime.state.addNotice(const NodeMissing(required: 22));
        await pumpAiPart(t, const AiTimeline(), runtime: runtime);
        await t.pump();
        final button = t.getRect(find.byKey(const Key('ai.checkAgain')));
        final hint = t.getRect(find.byKey(const Key('ai.restartHint')));
        expect(hint.top, greaterThanOrEqualTo(button.bottom));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    group('a session that cannot be reopened', () {
      const boom = {'code': -32603, 'message': 'boom'};
      const history = [
        {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'q1'},
        },
      ];
      AiRuntime resuming(FakeAiRuntimes fakes, {String? id = 'old-1'}) =>
          fakes.make(
            AiRuntimeRequest(
              agent: kKnownAgents.first,
              cwd: testAiCwd,
              resumeSessionId: id,
            ),
          );

      testWidgets('Start a new session lets the old one go (Try again would '
          'repeat the same load)', (t) async {
        final fakes = FakeAiRuntimes(
          const FakeScenario(loadSessionError: boom, history: history),
          later: const [FakeScenario()],
        );
        final runtime = resuming(fakes);
        await runtime.start();
        expect(runtime.state.phase, AgentPhase.failed);
        await pumpAiPart(t, const AiTimeline(), runtime: runtime);
        await t.pump();
        expect(find.text('Claude could not start'), findsOneWidget);
        expect(find.text('Start a new session'), findsOneWidget);

        await t.tap(find.byKey(const Key('ai.newSession')));
        await settle(t);

        expect(runtime.state.phase, AgentPhase.ready);
        expect(fakes.agent(1).received, contains('session/new'));
        expect(
          fakes.agent(1).received.where((e) => e.startsWith('session/load')),
          isEmpty,
        );
        expect(find.textContaining('cannot restore'), findsOneWidget);
        expect(find.byKey(const Key('ai.newSession')), findsNothing);
        await runtime.dispose();
      });

      testWidgets('Try again is still the same load', (t) async {
        final fakes = FakeAiRuntimes(
          const FakeScenario(loadSessionError: boom),
          later: const [FakeScenario(loadSessionError: boom)],
        );
        final runtime = resuming(fakes);
        await runtime.start();
        await pumpAiPart(t, const AiTimeline(), runtime: runtime);
        await t.pump();
        await t.tap(find.byKey(const Key('ai.retry')));
        await settle(t);
        expect(runtime.state.phase, AgentPhase.failed);
        expect(find.byKey(const Key('ai.newSession')), findsOneWidget);
        expect(fakes.agent(1).received, contains('session/load:old-1'));
        await runtime.dispose();
      });

      testWidgets('no such button when there is no session to let go of, or '
          'when it was not the session that failed', (t) async {
        final runtime = resuming(
          FakeAiRuntimes(const FakeScenario()),
          id: null,
        );
        runtime.state
          ..addNotice(const StartFailed(StartFailure.session))
          ..addNotice(const StartFailed(StartFailure.timeout));
        await pumpAiPart(t, const AiTimeline(), runtime: runtime);
        await t.pump();
        expect(find.byKey(const Key('ai.newSession')), findsNothing);
        expect(find.byKey(const Key('ai.retry')), findsNWidgets(2));

        final resumed = resuming(FakeAiRuntimes(const FakeScenario()));
        resumed.state.addNotice(const StartFailed(StartFailure.timeout));
        await pumpAiPart(t, const AiTimeline(), runtime: resumed);
        await t.pump();
        expect(find.byKey(const Key('ai.newSession')), findsNothing);
      });
    });

    testWidgets('the undo note for a broad folder says what the folder is', (
      t,
    ) async {
      final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
      runtime.state.addNotice(const UndoUnavailable(UndoOff.broadFolder));
      await pumpAiPart(t, const AiTimeline(), runtime: runtime);
      await t.pump();
      expect(
        find.text(
          'Undo is off for this project '
          '(this folder is your home folder or a disk root)',
        ),
        findsOneWidget,
      );
    });
  });
}
