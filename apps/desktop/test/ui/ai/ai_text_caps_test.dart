import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_log_dialog.dart';
import 'package:shellx_desktop/src/ui/ai/ai_markdown.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// I-5 of the final review: what an agent (or the user) writes has no length,
/// and a card must not freeze the window for it. Every place that shows such
/// text keeps about 32 KB of its start and end, and cuts a line at 2 000
/// characters (the tool card's own are in `ai_tool_card_test.dart`).
void main() {
  final at = DateTime(2026, 10, 14, 9);

  /// Everything the [finder] matches shows as text, in order.
  List<String> texts(WidgetTester t, Finder finder) => [
    for (final w in t.widgetList(finder))
      switch (w) {
        SelectableText(:final data) => data ?? '',
        Text(:final data) => data ?? '',
        _ => '',
      },
  ];

  testWidgets('the user\'s message: 1 MB pasted on one line shows at once, '
      'cut at 2 000 characters', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state.beginTurn([TextBlock('a' * (1 << 20))], at);
    final clock = Stopwatch()..start();
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    clock.stop();
    // ignore: avoid_print
    print(
      'TIMING user message, 1 MB on one line: ${clock.elapsedMilliseconds} ms',
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    final shown = texts(
      t,
      find.descendant(
        of: find.byType(AiUserMessage),
        matching: find.byType(SelectableText),
      ),
    );
    expect(shown, hasLength(1));
    expect(shown.single.length, lessThanOrEqualTo(2001));
    expect(shown.single, endsWith('…'));
  });

  testWidgets('the user\'s message: a long log pasted keeps its start and '
      'end, and says how many lines are left out', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final log = [for (var i = 0; i < 5000; i++) 'log line $i ${'z' * 80}'];
    runtime.state.beginTurn([TextBlock(log.join('\n'))], at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    final shown = texts(
      t,
      find.descendant(
        of: find.byType(AiUserMessage),
        matching: find.byType(SelectableText),
      ),
    ).single;
    expect(shown.length, lessThanOrEqualTo(34 * 1024));
    expect(shown, startsWith('log line 0 '));
    expect(shown, contains('log line 4999 '));
    expect(shown, isNot(contains('log line 2500 ')));
    expect(shown, matches(RegExp(r'… \d+ lines hidden …')));
  });

  testWidgets('the agent\'s words: a block of 1 MB on one line (plain text '
      'past 20 000 characters) is cut like an output', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(AgentMessageChunk(TextBlock('b' * (1 << 20))), at);
    final clock = Stopwatch()..start();
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    clock.stop();
    // ignore: avoid_print
    print(
      'TIMING agent text, 1 MB on one line: ${clock.elapsedMilliseconds} ms',
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    final shown = texts(
      t,
      find.descendant(of: find.byType(AiMarkdown), matching: find.byType(Text)),
    );
    expect(shown, hasLength(1));
    expect(shown.single.length, lessThanOrEqualTo(2001));
    expect(shown.single, endsWith('…'));
  });

  testWidgets('the agent\'s words: a huge code block keeps its start and '
      'end', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final code = [for (var i = 0; i < 6000; i++) 'final v$i = ${'x' * 40};'];
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(
        AgentMessageChunk(TextBlock('```dart\n${code.join('\n')}\n```')),
        at,
      );
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    final shown = texts(
      t,
      find.descendant(of: find.byType(AiMarkdown), matching: find.byType(Text)),
    ).single;
    expect(shown.length, lessThanOrEqualTo(34 * 1024));
    expect(shown, contains('final v0 = '));
    expect(shown, contains('final v5999 = '));
    expect(shown, isNot(contains('final v3000 = ')));
    expect(shown, matches(RegExp(r'… \d+ lines hidden …')));
  });

  testWidgets('a thought, once opened, is cut like an output too', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(AgentThoughtChunk(TextBlock('t' * (1 << 20))), at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    await t.tap(find.text('Thinking'));
    final clock = Stopwatch()..start();
    await t.pump();
    clock.stop();
    // ignore: avoid_print
    print('TIMING thought, 1 MB on one line: ${clock.elapsedMilliseconds} ms');
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    final shown = texts(
      t,
      find.descendant(
        of: find.byType(AiThought),
        matching: find.byType(SelectableText),
      ),
    ).single;
    expect(shown.length, lessThanOrEqualTo(2001));
    expect(shown, endsWith('…'));
  });

  testWidgets('"View log": 256 KiB of stderr on one line is cut like an '
      'output', (t) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.stderr('e' * (256 << 10))],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    await runtime.send([const TextBlock('go')]);
    await runtime.whenIdle();
    late BuildContext inner;
    await pumpAiPart(
      t,
      Builder(
        builder: (context) {
          inner = context;
          return const SizedBox();
        },
      ),
      runtime: runtime,
    );
    expect(runtime.stderrTail.length, greaterThan(250 << 10));
    final clock = Stopwatch()..start();
    unawaited(showAiLogDialog(inner, runtime));
    await t.pump();
    await t.pump();
    clock.stop();
    // ignore: avoid_print
    print(
      'TIMING log dialog, 256 KiB on one line: ${clock.elapsedMilliseconds} ms',
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    final shown = t
        .widget<SelectableText>(find.byKey(const Key('ai.log.text')))
        .data!;
    expect(shown, contains('RECV initialize'), reason: 'the log is there');
    expect(shown, contains('e' * 100));
    expect(shown, isNot(contains('e' * 2002)));
    expect(shown.length, lessThan(8000));
    await runtime.dispose();
  });

  testWidgets('"View log": a long log keeps its start and end, and says how '
      'many lines are left out', (t) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [
            for (var i = 0; i < 4000; i++)
              FakeSteps.stderr('stderr line $i ${'q' * 80}'),
          ],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    await runtime.send([const TextBlock('go')]);
    await runtime.whenIdle();
    late BuildContext inner;
    await pumpAiPart(
      t,
      Builder(
        builder: (context) {
          inner = context;
          return const SizedBox();
        },
      ),
      runtime: runtime,
    );
    unawaited(showAiLogDialog(inner, runtime));
    await t.pump();
    await t.pump();
    final shown = t
        .widget<SelectableText>(find.byKey(const Key('ai.log.text')))
        .data!;
    expect(shown.length, lessThanOrEqualTo(34 * 1024));
    expect(shown, contains('RECV initialize'));
    expect(shown, contains('stderr line 3999 '));
    expect(shown, isNot(contains('stderr line 2000 ')));
    expect(shown, matches(RegExp(r'… \d+ lines hidden …')));
    await runtime.dispose();
  });
}
