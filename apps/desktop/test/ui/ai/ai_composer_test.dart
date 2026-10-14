import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  Future<(FakeAiRuntimes, AiRuntime)> ready(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  List<String> prompts(FakeAiRuntimes f) => [
    for (final r in f.agent().received)
      if (r.startsWith('session/prompt:')) r.substring(15),
  ];

  testWidgets('Enter sends; Shift+Enter and IME composing never do '
      '(D16, §1.10)', (t) async {
    final (fakes, runtime) = await ready(t, const FakeScenario());
    await t.enterText(find.byKey(const Key('ai.composer')), 'hello');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(prompts(fakes), ['hello']);
    expect(find.text('hello'), findsNothing, reason: 'the field is empty');
    await t.enterText(find.byKey(const Key('ai.composer')), 'two');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'tieng',
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(prompts(fakes), ['hello']);
    await runtime.dispose();
  });

  testWidgets('during a turn: Queue, shown, then sent when the turn ends; '
      'Esc stops at once (D16, §1.4)', (t) async {
    final (fakes, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
          const [],
        ],
      ),
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'one');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('Stop  Esc'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.composer')), 'two');
    await t.pump();
    expect(find.text('Queue  ⏎'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(
      find.text('Queued: “two” — sent when this turn ends'),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    expect(prompts(fakes), ['one', 'two']);
    await runtime.dispose();
  });

  testWidgets('a turn that ignores Stop: Stopping…, then Force stop after '
      '10 s (§1.4)', (t) async {
    final (fakes, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.hang()],
        ],
      ),
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await t.pump();
    expect(find.byKey(const Key('ai.forceStop')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.forceStop')));
    await t.pump();
    await t.pump();
    expect(fakes.launcher.channels.single.killCalls, 1);
    expect(runtime.state.turn, isNull);
    await runtime.dispose();
  });

  testWidgets('context use and the plan (spec §4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final at = DateTime(2026, 10, 14);
    runtime.state
      ..applyUpdate(UsageUpdated(const Usage(used: 160000, size: 1000000)), at)
      ..applyUpdate(
        PlanUpdated(const [
          PlanEntry(content: 'Read the code', status: PlanStatus.completed),
          PlanEntry(content: 'Fix the bug', status: PlanStatus.inProgress),
          PlanEntry(content: 'Run the tests', status: PlanStatus.pending),
        ]),
        at,
      );
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.pump();
    expect(find.text('Context 16%'), findsOneWidget);
    expect(find.text('Plan · 1/3 done'), findsOneWidget);
    expect(find.text('Fix the bug'), findsNothing);
    await t.tap(find.byKey(const Key('ai.plan')));
    await t.pump();
    expect(find.text('Fix the bug'), findsOneWidget);
  });
}
