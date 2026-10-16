import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_markdown.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  testWidgets('the user, the answer as markdown, a folded thought', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    s.beginTurn([const TextBlock('Fix the login')], at);
    s.applyUpdate(AgentThoughtChunk(const TextBlock('secret plan')), at);
    s.applyUpdate(AgentMessageChunk(const TextBlock('**Done.**')), at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Fix the login'), findsOneWidget);
    expect(find.textContaining('Done.', findRichText: true), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('secret plan'), findsNothing, reason: 'folded, not built');
    await t.tap(find.text('Thinking'));
    await t.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });

  testWidgets('2 000 chunks: one rebuild per frame, of that message only, '
      'and of its last block only (Review Focus 4)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    AiTimeline.debugItemBuilds = 0;
    AiMarkdown.debugBlockBuilds = 0;
    for (var frame = 0; frame < 20; frame++) {
      for (var i = 0; i < 100; i++) {
        // A new paragraph every 50 chunks: 40 blocks in the end.
        final text = i % 50 == 49 ? 'end.\n\n' : 'word ';
        s.applyUpdate(AgentMessageChunk(TextBlock(text)), at);
      }
      await t.pump();
    }
    expect(AiTimeline.debugItemBuilds, lessThanOrEqualTo(21));
    expect(AiMarkdown.debugBlockBuilds, lessThanOrEqualTo(20 + 40 + 2));
  });

  testWidgets('markdown never loads images; links open on a click, '
      'http/https only (B15)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(
        AgentMessageChunk(
          const TextBlock(
            '![tracker](https://tracker.example/p.png) '
            '[site](https://shellx.pro) [local](file:///etc/passwd)',
          ),
        ),
        at,
      );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('[tracker]', findRichText: true), findsWidgets);
    expect(w.harness.urlOpener.webLinks, isEmpty, reason: 'no click yet');
    await t.tapOnText(find.textRange.ofSubstring('site'));
    await t.pump();
    await t.tapOnText(find.textRange.ofSubstring('local'));
    await t.pump();
    expect(w.harness.urlOpener.webLinks, [Uri.parse('https://shellx.pro')]);
  });

  testWidgets('it follows the bottom; scrolled up it stays, with Jump to '
      'latest', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    for (var i = 0; i < 30; i++) {
      s.beginTurn([TextBlock('question $i')], at);
      s.applyUpdate(AgentMessageChunk(TextBlock('answer $i\n\nmore')), at);
      s.endTurn(outcome: TurnOutcome.finished, at: at);
    }
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pumpAndSettle();
    ScrollPosition pos() =>
        t.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(pos().pixels, pos().maxScrollExtent);
    await t.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 400));
    await t.pumpAndSettle();
    final kept = pos().pixels;
    expect(find.byKey(const Key('ai.jumpToLatest')), findsOneWidget);
    s.applyUpdate(AgentMessageChunk(const TextBlock(' and more')), at);
    await t.pumpAndSettle();
    expect(pos().pixels, kept, reason: 'the reader keeps their place');
    await t.tap(find.byKey(const Key('ai.jumpToLatest')));
    await t.pumpAndSettle();
    expect(pos().pixels, pos().maxScrollExtent);
    expect(find.byKey(const Key('ai.jumpToLatest')), findsNothing);
  });
}
