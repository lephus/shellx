import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

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

  AiPaneUi uiOf(WidgetTester t) =>
      AiPaneScope.of(t.element(find.byKey(const Key('ai.composer')))).ui;

  String composerText(WidgetTester t) => t
      .widget<TextField>(find.byKey(const Key('ai.composer')))
      .controller!
      .text;

  testWidgets('"Stopping…" and "Force stop" stay while there is text in the '
      'composer (§1.4)', (t) async {
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
    await t.enterText(find.byKey(const Key('ai.composer')), 'and then');
    await t.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await t.pump();
    expect(find.byKey(const Key('ai.forceStop')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.forceStop')));
    await t.pump();
    await t.pump();
    expect(fakes.launcher.channels.single.killCalls, 1);
    await runtime.dispose();
  });

  testWidgets('Esc after the grace only stops; Force stop is the button, '
      'never a key', (t) async {
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
    await t.pump(const Duration(seconds: 10));
    await t.pump();
    expect(find.byKey(const Key('ai.forceStop')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    expect(fakes.launcher.channels.single.killCalls, 0);
    await t.tap(find.byKey(const Key('ai.forceStop')));
    await t.pump();
    await t.pump();
    expect(fakes.launcher.channels.single.killCalls, 1);
    await runtime.dispose();
  });

  bool enabled(WidgetTester t, String key) =>
      t.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  testWidgets('an image alone is a message: Send, and Queue while a turn runs '
      '(D16)', (t) async {
    final (fakes, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
          const [],
        ],
      ),
    );
    final ui = uiOf(t);
    ui.images.add(_png, 'image/png');
    await t.pump();
    expect(enabled(t, 'ai.send'), isTrue, reason: 'Send with an image only');
    await t.tap(find.byKey(const Key('ai.send')));
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'image', 'data': base64Encode(_png), 'mimeType': 'image/png'},
    ]);
    // The turn runs: another image alone queues, it does not offer Stop.
    ui.images.add(_png, 'image/png');
    await t.pump();
    expect(find.text('Queue  ⏎'), findsOneWidget);
    expect(find.byKey(const Key('ai.stop')), findsNothing);
    expect(enabled(t, 'ai.send'), isTrue);
    await t.tap(find.byKey(const Key('ai.send')));
    await t.pump();
    expect(runtime.state.queue, hasLength(1));
    await runtime.dispose();
  });

  testWidgets('while the agent starts the prompt waits: the button says '
      'Queue', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state.setPhase(AgentPhase.starting);
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.enterText(find.byKey(const Key('ai.composer')), 'hello');
    await t.pump();
    expect(find.text('Queue  ⏎'), findsOneWidget);
    expect(find.text('Send  ⏎'), findsNothing);
  });

  testWidgets('a note clears when it is no longer true; a failed agent does '
      'not say "Waiting" (D16)', (t) async {
    final (_, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.hang()],
        ],
      ),
    );
    await runtime.send([const TextBlock('one')]);
    for (var i = 0; i < AiSessionState.maxQueue; i++) {
      expect(await runtime.send([TextBlock('wait $i')]), isTrue);
    }
    await t.pump();
    await t.enterText(find.byKey(const Key('ai.composer')), 'one too many');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('At most 5 messages can wait.'), findsOneWidget);
    expect(composerText(t), 'one too many', reason: 'kept');
    runtime.state.removeQueued(runtime.state.queue.first.id);
    await t.pump();
    expect(find.text('At most 5 messages can wait.'), findsNothing);
    runtime.state.setPhase(AgentPhase.failed);
    await t.pump();
    expect(find.text('Waiting for the agent…'), findsNothing);
    expect(find.text('The agent cannot take a message now.'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a refused send keeps the text, the images and the mentions', (
    t,
  ) async {
    final (_, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.hang()],
        ],
      ),
    );
    await runtime.send([const TextBlock('one')]);
    for (var i = 0; i < AiSessionState.maxQueue; i++) {
      await runtime.send([TextBlock('wait $i')]);
    }
    final ui = uiOf(t);
    ui.fileIndex = () async => ['lib/a.dart'];
    ui.images.add(_png, 'image/png');
    await t.enterText(find.byKey(const Key('ai.composer')), 'look at @lib');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // takes the suggestion
    await t.pump();
    expect(composerText(t), 'look at @lib/a.dart ');
    await t.sendKeyEvent(LogicalKeyboardKey.enter); // sends: refused
    await t.pump();
    expect(find.text('At most 5 messages can wait.'), findsOneWidget);
    expect(composerText(t), 'look at @lib/a.dart ');
    expect(ui.images.items, hasLength(1), reason: 'the image is kept');
    // A place frees up: the same message goes, with its image and its file.
    runtime.state.removeQueued(runtime.state.queue.first.id);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    final sent = runtime.state.queue.last.blocks;
    expect(
      [for (final b in sent) b.runtimeType],
      [TextBlock, ImageBlock, ResourceLinkBlock],
    );
    expect(ui.images.items, isEmpty);
    await runtime.dispose();
  });

  testWidgets('big images are encoded off the UI isolate; small ones are not '
      '(smoothness)', (t) async {
    var trips = 0;
    Future<R> counting<Q, R>(R Function(Q) work, Q input) async {
      trips++;
      return work(input);
    }

    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      const AiDock(),
      runtime: runtime,
      overrides: [aiOffThreadProvider.overrideWithValue(counting)],
    );
    await t.tap(find.byKey(const Key('ai.composer')));
    final ui = uiOf(t);
    ui.images.add(_png, 'image/png');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(trips, 0, reason: 'a 68-byte image is not worth a trip');
    final big = Uint8List(400 << 10)..setRange(0, 4, [0x89, 0x50, 0x4E, 0x47]);
    ui.images.add(big, 'image/png');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(trips, 1);
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'image', 'data': base64Encode(big), 'mimeType': 'image/png'},
    ]);
    await runtime.dispose();
  });

  testWidgets('a message that cannot be prepared comes back whole, and the '
      'next one still goes (the sends are not stuck behind it)', (t) async {
    var calls = 0;
    Future<R> failing<Q, R>(R Function(Q) work, Q input) async {
      if (calls++ == 0) throw StateError('the isolate is gone');
      return work(input);
    }

    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      const AiDock(),
      runtime: runtime,
      overrides: [aiOffThreadProvider.overrideWithValue(failing)],
    );
    await t.tap(find.byKey(const Key('ai.composer')));
    final ui = uiOf(t);
    final big = Uint8List(400 << 10)..setRange(0, 4, [0x89, 0x50, 0x4E, 0x47]);
    ui.images.add(big, 'image/png');
    await t.pump();
    await t.enterText(find.byKey(const Key('ai.composer')), 'look');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(composerText(t), 'look', reason: 'the text is back');
    expect(ui.images.items, hasLength(1), reason: 'the image is back');
    expect(find.text('The agent cannot take a message now.'), findsOneWidget);
    expect(
      fakes.agent().received.where((r) => r.startsWith('session/prompt')),
      isEmpty,
    );
    // Sent again, it goes.
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(
      fakes.agent().received.where((r) => r.startsWith('session/prompt')),
      hasLength(1),
    );
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
