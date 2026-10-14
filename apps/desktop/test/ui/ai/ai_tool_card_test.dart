import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ui/ai/ai_diff_view.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';
import 'package:shellx_desktop/src/ui/ai/ai_tool_card.dart';

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
    Object? rawOutput,
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
        rawOutput: rawOutput,
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

  Future<AiSessionState> pumpCard(
    WidgetTester t,
    void Function(AiSessionState s) fill,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    fill(s);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    return s;
  }

  testWidgets('a patch of several files shows every file\'s diff, with the '
      'lines of all of them in the header', (t) async {
    final s = await pumpCard(t, (s) {
      final cwd = s.cwd;
      tool(
        s,
        'p',
        ToolKind.edit,
        'Patch',
        content: [
          ToolDiff(path: '$cwd/a.ts', oldText: 'a\nb\n', newText: 'a\nB\nc\n'),
          ToolDiff(path: '$cwd/b.ts', newText: 'x\ny\n'),
          ToolDiff(path: '$cwd/c.ts', oldText: 'old\n', newText: 'new\n'),
        ],
      );
    });
    expect(find.text('a.ts, b.ts, c.ts'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('−2'), findsOneWidget);
    expect(s.timeline.items.whereType<ToolItem>(), hasLength(1));
    await t.tap(find.byType(InkWell).first);
    await t.pump();
    expect(find.byType(AiDiffView), findsNWidgets(3));
    expect(find.text('View whole file'), findsNWidgets(3));
    expect(find.text('Open in editor'), findsNWidgets(3));
    for (final file in ['a.ts', 'b.ts', 'c.ts']) {
      expect(find.text(file), findsOneWidget, reason: 'caption of $file');
    }
  });

  testWidgets('a diff over 300 lines is computed off the UI isolate, once '
      'however often its card is built; a short one never is', (t) async {
    var trips = 0;
    Future<R> counting<Q, R>(R Function(Q) work, Q input) async {
      trips++;
      return work(input);
    }

    final big = [for (var i = 0; i < 400; i++) 'line $i'].join('\n');
    final small = [for (var i = 0; i < 100; i++) 'row $i'].join('\n');
    final bigDiff = ToolDiff(
      path: '/p/big.txt',
      oldText: big,
      newText: '$big\nend\n',
    );
    final smallDiff = ToolDiff(
      path: '/p/small.txt',
      oldText: small,
      newText: '$small\nend\n',
    );
    Future<void> show() async {
      final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
      runtime.state
        ..beginTurn([const TextBlock('go')], at)
        ..applyUpdate(
          ToolCallStarted(
            'big',
            ToolCallFields(
              title: 'Edit',
              kind: ToolKind.edit,
              content: [bigDiff],
            ),
          ),
          at,
        )
        ..applyUpdate(
          ToolCallStarted(
            'small',
            ToolCallFields(
              title: 'Edit',
              kind: ToolKind.edit,
              content: [smallDiff],
            ),
          ),
          at,
        );
      await pumpAiPart(
        t,
        const AiTimeline(),
        runtime: runtime,
        overrides: [aiOffThreadProvider.overrideWithValue(counting)],
      );
      await t.pump();
      await t.pump();
    }

    await show();
    expect(trips, 1, reason: 'the 400-line diff, not the 100-line one');
    await show(); // the cards are made again: nothing is diffed again
    expect(trips, 1);
    expect(find.text('+1'), findsNWidgets(2), reason: 'both stats are there');
  });

  testWidgets('a command shows its output without escape codes and its exit '
      'code', (t) async {
    await pumpCard(t, (s) {
      tool(
        s,
        'x',
        ToolKind.execute,
        'ls --color',
        status: ToolCallStatus.completed,
        content: [
          ToolContentBlock(
            const TextBlock(
              '\x1B[1;31mred\x1B[0m text\n\x1B]0;a title\x07done \x1B[2K\x1B[1G!',
            ),
          ),
        ],
        rawOutput: {'exit_code': 0, 'stdout': 'x'},
      );
      tool(
        s,
        'y',
        ToolKind.execute,
        'nope',
        status: ToolCallStatus.failed,
        content: [ToolContentBlock(const TextBlock('boom'))],
        rawOutput: 'Exit code 127\nnope: command not found',
      );
    });
    expect(find.textContaining('red text'), findsOneWidget);
    expect(find.textContaining('done !'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            (w is Text && (w.data ?? '').contains('\x1B')) ||
            (w is EditableText && w.controller.text.contains('\x1B')),
      ),
      findsNothing,
    );
    expect(find.text('Ended with exit code 0'), findsOneWidget);
    expect(find.text('Ended with exit code 127'), findsOneWidget);
  });

  testWidgets('the header\'s hover and press show: its background is the '
      'Material the ink paints on, not a box over it', (t) async {
    await pumpCard(t, (s) {
      tool(s, 'e', ToolKind.search, 'TODO in src');
    });
    final ink = find
        .descendant(of: find.byType(AiToolCard), matching: find.byType(InkWell))
        .first;
    final opaque = <Widget>[];
    Material? paintedOn;
    t.element(ink).visitAncestorElements((e) {
      final w = e.widget;
      if (w is Material) {
        paintedOn = w;
        return false;
      }
      if (w is DecoratedBox || w is ColoredBox) opaque.add(w);
      return true;
    });
    expect(
      opaque,
      isEmpty,
      reason: 'a background between the ink and the Material hides it',
    );
    expect(
      find.descendant(
        of: find.byType(AiToolCard),
        matching: find.byWidget(paintedOn!),
      ),
      findsOneWidget,
      reason: 'the card is its own Material',
    );
  });

  test('exit codes as the agents report them', () {
    expect(aiExitCode({'exit_code': 2, 'stdout': 'x'}), 2);
    expect(
      aiExitCode({
        'metadata': {'exit': 1, 'output': 'x'},
      }),
      1,
    );
    expect(aiExitCode({'exitCode': ' 3 '}), 3);
    expect(aiExitCode('Exit code 127\nnope'), 127);
    expect(aiExitCode('hello'), isNull);
    expect(aiExitCode(null), isNull);
    expect(aiExitCode({'exit': true}), isNull);
    expect(aiExitCode({'stdout': 'x'}), isNull);
  });

  test('terminal escape sequences are stripped, plain text is left alone', () {
    expect(aiStripAnsi('\x1B[31mred\x1B[0m'), 'red');
    expect(aiStripAnsi('\x1B[38;5;208mx\x1B[39m \x1B[2K\x1B[1G!'), 'x !');
    expect(aiStripAnsi('a\x1B]8;;https://x.test\x07link\x1B]8;;\x07'), 'alink');
    expect(aiStripAnsi('a\x1B]0;title\x1B\\b'), 'ab');
    expect(aiStripAnsi('\x1B(B\x1B=ok'), 'ok');
    expect(aiStripAnsi('plain ✓ — text\n'), 'plain ✓ — text\n');
  });

  testWidgets('a command that failed opens by itself, with its output; one '
      'that was refused does not (it ran nothing)', (t) async {
    await pumpCard(t, (s) {
      tool(
        s,
        'f',
        ToolKind.execute,
        'make',
        status: ToolCallStatus.failed,
        content: [ToolContentBlock(const TextBlock('make: *** error'))],
      );
      s.addPermission(
        const PermissionRequest(
          sessionId: 's',
          toolCallId: 'r',
          toolCall: ToolCallFields(title: 'rm -rf x', kind: ToolKind.execute),
          options: [
            PermissionOption(
              optionId: 'n',
              name: 'No',
              kind: PermissionKind.rejectOnce,
            ),
          ],
        ),
        at,
      );
      s.resolvePermission(
        s.permissions.single.id,
        const PermissionSelected('n'),
      );
      s.applyUpdate(
        ToolCallUpdated(
          'r',
          const ToolCallFields(
            status: ToolCallStatus.failed,
            content: [ToolContentBlock(TextBlock('should not be shown'))],
          ),
        ),
        at,
      );
    });
    expect(find.textContaining('make: *** error'), findsOneWidget);
    expect(find.textContaining('should not be shown'), findsNothing);
    expect(find.text('rejected'), findsOneWidget);
  });
}
