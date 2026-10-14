import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  void tool(
    AiSessionState s,
    String id,
    ToolKind kind,
    String title, {
    ToolCallStatus? status,
    List<ToolContent>? content,
    List<ToolLocation>? locations,
    Object? rawInput,
  }) => s.applyUpdate(
    ToolCallStarted(
      id,
      ToolCallFields(
        title: title,
        kind: kind,
        status: status,
        content: content,
        locations: locations,
        rawInput: rawInput,
      ),
    ),
    at,
  );

  testWidgets('one card per kind, with its verb and target (spec §4.2)', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    final cwd = s.cwd;
    tool(
      s,
      'r',
      ToolKind.read,
      'Read File',
      locations: [ToolLocation('$cwd/src/a.ts', 3)],
    );
    tool(
      s,
      'c',
      ToolKind.edit,
      'Write',
      content: [ToolDiff(path: '$cwd/new.ts', newText: 'x\n')],
    );
    tool(
      s,
      'e',
      ToolKind.edit,
      'Edit',
      content: [
        ToolDiff(path: '$cwd/b.ts', oldText: 'a\nb\n', newText: 'a\nB\nc\n'),
      ],
    );
    tool(
      s,
      'd',
      ToolKind.delete,
      'Delete',
      locations: [ToolLocation('$cwd/old.ts')],
    );
    tool(s, 's', ToolKind.search, 'TODO in src');
    tool(s, 'x', ToolKind.execute, 'npm test');
    tool(s, 'f', ToolKind.fetch, 'https://example.com');
    tool(s, 'm', ToolKind.other, 'mcp__github__create_issue');
    tool(s, 'w', ToolKind.switchMode, 'plan');
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    for (final text in [
      'src/a.ts',
      'new.ts',
      'b.ts',
      'old.ts',
      'TODO in src',
      'npm test',
      'https://example.com',
      'github · create_issue',
      'Mode changed: plan',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    for (final verb in [
      'Read',
      'Create',
      'Edit',
      'Delete',
      'Search',
      'Run',
      'Fetch',
    ]) {
      expect(find.text(verb), findsOneWidget, reason: verb);
    }
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
  });

  testWidgets('status: waiting, running, done, error, rejected, stopped', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    tool(s, 'p', ToolKind.read, 'pending one');
    tool(
      s,
      'r',
      ToolKind.search,
      'running one',
      status: ToolCallStatus.inProgress,
    );
    tool(s, 'f', ToolKind.search, 'failed one', status: ToolCallStatus.failed);
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    final texts = [
      for (final e in find.byKey(const Key('ai.tool.status')).evaluate())
        (e.widget as Text).data,
    ];
    expect(texts, contains('waiting'));
    expect(texts.any((x) => x!.startsWith('running · ')), isTrue);
    expect(texts, contains('error'));
    s.endTurn(outcome: TurnOutcome.cancelled, at: at);
    await t.pump();
    expect(find.text('stopped'), findsNWidgets(2));
    expect(w.ui.overlay, isNull);
  });

  testWidgets('a long output shows its ends and "Show all N lines"', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    final out = [for (var i = 0; i < 1000; i++) 'line $i'].join('\n');
    tool(
      s,
      'x',
      ToolKind.execute,
      'yes',
      status: ToolCallStatus.completed,
      content: [ToolContentBlock(TextBlock(out))],
    );
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('600 lines hidden'), findsOneWidget);
    expect(find.textContaining('line 500'), findsNothing);
    await t.ensureVisible(find.byKey(const Key('ai.tool.showAll')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.tool.showAll')));
    await t.pump();
    expect(find.byKey(const Key('ai.tool.showAll')), findsNothing);
  });

  testWidgets('a command with no output says the Changes panel still sees '
      'its files', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    tool(s, 'y', ToolKind.execute, 'true', status: ToolCallStatus.completed);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.textContaining('No output.'), findsOneWidget);
  });

  testWidgets('an edit asking permission opens and says how to answer (D10)', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    s.addPermission(
      PermissionRequest(
        sessionId: 's',
        toolCallId: 't1',
        toolCall: ToolCallFields(
          title: 'Edit a.ts',
          kind: ToolKind.edit,
          content: [
            ToolDiff(path: '${s.cwd}/a.ts', oldText: 'a\n', newText: 'b\n'),
          ],
        ),
        options: const [
          PermissionOption(
            optionId: 'y',
            name: 'Yes',
            kind: PermissionKind.allowOnce,
          ),
          PermissionOption(
            optionId: 'a',
            name: 'Yes, always',
            kind: PermissionKind.allowAlways,
          ),
          PermissionOption(
            optionId: 'n',
            name: 'No',
            kind: PermissionKind.rejectOnce,
          ),
        ],
      ),
      at,
    );
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('waiting for you'), findsOneWidget);
    expect(
      find.text('Waiting for your answer below — keys 1–3, Esc to reject'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai.tool.editor')),
      findsOneWidget,
      reason: 'opened',
    );
    s.resolvePermission(s.permissions.single.id, const PermissionSelected('y'));
    await t.pump();
    expect(find.text('You chose: Allow (Yes)'), findsOneWidget);
  });
}
