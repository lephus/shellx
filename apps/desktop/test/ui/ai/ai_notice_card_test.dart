import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
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
}
