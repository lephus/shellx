import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_permission_bar.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';
import 'package:shellx_desktop/src/ui/ai/ai_tool_card.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/ai_semantics.dart';

void main() {
  /// [after]: what the turn does once the request is answered.
  Future<(FakeAiRuntimes, AiRuntime)> asking(
    WidgetTester t, {
    List<Map<String, Object?>> options = FakeSteps.claudeOptions,
    String title = 'Edit a.ts',
    Map<String, Object?>? after,
    Widget Function(Widget dock)? around,
  }) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [
            FakeSteps.permission('t1', title, options: options),
            after ?? FakeSteps.text('done'),
          ],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    final dock = AiDock(
      permissionBar: const AiPermissionBar(),
      keyHook: (e, {required hasText}) =>
          aiPermissionKeys(runtime, e, hasText: hasText),
    );
    await pumpAiPart(t, around == null ? dock : around(dock), runtime: runtime);
    await t.tap(find.byKey(const Key('ai.composer')));
    await runtime.send([const TextBlock('edit it')]);
    await t.pump();
    await t.pump();
    return (fakes, runtime);
  }

  List<String> answers(FakeAiRuntimes f) => [
    for (final r in f.agent().received)
      if (r.startsWith('permission:')) r.substring(11),
  ];

  testWidgets('the bar: title, options by kind with keys, the agent words '
      'for "always" (§4.3)', (t) async {
    final (fakes, runtime) = await asking(t);
    expect(find.text('Claude asks: Edit a.ts'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Always allow'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    expect(
      find.text(
        '“Always allow” as Claude puts it: Yes, allow all edits during '
        'this session',
      ),
      findsOneWidget,
    );
    expect(answers(fakes), isEmpty, reason: 'never answers by itself');
    await runtime.dispose();
  });

  testWidgets('key 2 picks the second option, in the agent order (D10)', (
    t,
  ) async {
    final (fakes, runtime) = await asking(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pump();
    expect(answers(fakes), ['allow-with-updates']);
    expect(find.byKey(const Key('ai.permission')), findsNothing);
    await runtime.whenIdle();
    await runtime.dispose();
  });

  testWidgets('Esc picks the first reject; with none it is cancelled', (
    t,
  ) async {
    var (fakes, runtime) = await asking(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(fakes), ['reject']);
    await runtime.dispose();
    (fakes, runtime) = await asking(
      t,
      options: const [
        {'optionId': 'ok', 'name': 'Yes', 'kind': 'allow_once'},
      ],
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(fakes), ['cancelled']);
    await runtime.dispose();
  });

  testWidgets('with text in the composer, or while composing, digits are '
      'text; ⌘1 is the window\'s (D10, §1.10)', (t) async {
    final (fakes, runtime) = await asking(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'x');
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(fakes), isEmpty);
    await t.enterText(find.byKey(const Key('ai.composer')), '');
    t.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'a', composing: TextRange(start: 0, end: 1)),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(fakes), isEmpty);
    t.testTextInput.updateEditingValue(TextEditingValue.empty);
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    expect(answers(fakes), isEmpty);
    await runtime.dispose();
  });

  testWidgets('the bar never takes the focus from the composer', (t) async {
    final (_, runtime) = await asking(t);
    final composer = t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .focusNode!;
    expect(composer.hasPrimaryFocus, isTrue);
    await t.tap(find.text('Claude asks: Edit a.ts'));
    await t.pump();
    expect(composer.hasPrimaryFocus, isTrue);
    await runtime.dispose();
  });

  testWidgets(
    'a long title (Claude\'s Bash title is the whole command) scrolls '
    'in a box of its own; the buttons and the composer stay in the window',
    (t) async {
      final command = [
        "cat > /tmp/setup.sh <<'EOF'",
        for (var i = 0; i < 38; i++) 'echo "step \$i of the installer"',
        'EOF',
      ].join('\n');
      final (_, runtime) = await asking(t, title: command);
      // The window is 700 px high.
      expect(
        t.getRect(find.byKey(const ValueKey('ai.permission.1'))).bottom,
        lessThanOrEqualTo(700),
      );
      expect(
        t.getRect(find.byKey(const Key('ai.composer'))).bottom,
        lessThanOrEqualTo(700),
      );
      final box = find.byKey(const Key('ai.permission.title'));
      expect(t.getSize(box).height, lessThanOrEqualTo(120));
      // The whole command stays there to read: the box scrolls to its end.
      expect(find.text('Claude asks: $command'), findsOneWidget);
      final scroll = t.state<ScrollableState>(
        find.descendant(of: box, matching: find.byType(Scrollable)),
      );
      expect(scroll.position.maxScrollExtent, greaterThan(300));
      await t.drag(box, const Offset(0, -2000));
      await t.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      await runtime.dispose();
    },
  );

  testWidgets('the agent\'s own words for "always" are as long as it likes: '
      'they scroll in a box too; the buttons and the composer stay in the '
      'window', (t) async {
    final words = [for (var i = 0; i < 40; i++) 'path/$i/**'].join('\n');
    final (_, runtime) = await asking(
      t,
      options: [
        {'optionId': 'once', 'name': 'Yes', 'kind': 'allow_once'},
        {
          'optionId': 'always',
          'name': 'Yes, and do not ask again for:\n$words',
          'kind': 'allow_always',
        },
        {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
      ],
    );
    expect(
      t.getRect(find.byKey(const ValueKey('ai.permission.1'))).bottom,
      lessThanOrEqualTo(700),
    );
    expect(
      t.getRect(find.byKey(const Key('ai.composer'))).bottom,
      lessThanOrEqualTo(700),
    );
    final note = find.byKey(const Key('ai.permission.note'));
    expect(t.getSize(note).height, lessThanOrEqualTo(80));
    expect(find.textContaining('path/39/**', findRichText: true), findsWidgets);
    await runtime.dispose();
  });

  testWidgets('each request opens at its start: the offset of the one before '
      'does not carry over to the next (a user sees the start of the command '
      'they approve)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      const AiDock(permissionBar: AiPermissionBar()),
      runtime: runtime,
    );
    String command(String name) => [
      "cat > /tmp/$name.sh <<'EOF'",
      for (var i = 0; i < 38; i++) 'echo "$name step $i of the installer"',
      'EOF',
    ].join('\n');
    String words(String name) => [
      'Yes, and do not ask again for:',
      for (var i = 0; i < 40; i++) '$name/path/$i/**',
    ].join('\n');
    PermissionRequest request(String id, String name) =>
        PermissionRequest.fromJson({
          'sessionId': 's',
          'toolCall': {
            'toolCallId': id,
            'title': command(name),
            'kind': 'execute',
          },
          'options': [
            {'optionId': 'once', 'name': 'Yes', 'kind': 'allow_once'},
            {'optionId': 'always', 'name': words(name), 'kind': 'allow_always'},
            {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
          ],
        });
    final at = DateTime(2026, 10, 14, 9);
    // Two requests wait together (parallel tool calls): answering the first
    // shows the second at once, with no empty frame between.
    final first = runtime.state.addPermission(request('a', 'first'), at);
    runtime.state.addPermission(request('b', 'second'), at);
    await t.pump();
    await t.pump();
    ScrollableState scrollOf(String key) => t.state<ScrollableState>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Scrollable),
      ),
    );
    for (final key in ['ai.permission.title', 'ai.permission.note']) {
      final scroll = scrollOf(key);
      expect(scroll.position.maxScrollExtent, greaterThan(0), reason: key);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await t.pump();
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
    }
    runtime.state.resolvePermission(first.id, const PermissionSelected('once'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('second step 0 of'), findsOneWidget);
    expect(find.textContaining('first step 0 of'), findsNothing);
    for (final key in ['ai.permission.title', 'ai.permission.note']) {
      expect(
        scrollOf(key).position.pixels,
        0,
        reason: '$key opens at its start',
      );
    }
    final box = find.byKey(const Key('ai.permission.title'));
    expect(
      t.getTopLeft(find.textContaining('second step 0 of')).dy,
      t.getTopLeft(box).dy,
      reason: 'the first line of the command is the first thing in the box',
    );
    await runtime.dispose();
  });

  testWidgets('the dock, top to bottom: plan, permission bar, queue, composer '
      '(spec §4.1)', (t) async {
    final (_, runtime) = await asking(t);
    runtime.state.applyUpdate(
      PlanUpdated(const [
        PlanEntry(content: 'Fix it', status: PlanStatus.inProgress),
      ]),
      DateTime(2026, 10, 14),
    );
    expect(await runtime.send([const TextBlock('then this')]), isTrue);
    await t.pump();
    double top(Finder f) => t.getTopLeft(f).dy;
    final plan = top(find.byKey(const Key('ai.plan')));
    final bar = top(find.byKey(const Key('ai.permission')));
    final queued = top(find.textContaining('Queued: “then this”'));
    final composer = top(find.byKey(const Key('ai.composer')));
    expect(plan, lessThan(bar));
    expect(bar, lessThan(queued));
    expect(queued, lessThan(composer));
    await runtime.dispose();
  });

  testWidgets(
    'a mouse click on Send or on an option keeps the composer\'s focus '
    '(macOS and Windows drop it on a tap outside a field)',
    (t) async {
      final (fakes, runtime) = await asking(t);
      final composer = t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .focusNode!;
      await t.enterText(find.byKey(const Key('ai.composer')), 'and this too');
      await t.pump();
      expect(composer.hasPrimaryFocus, isTrue);
      await t.tap(
        find.byKey(const Key('ai.send')),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      expect(composer.hasPrimaryFocus, isTrue, reason: 'after Send');
      await t.tap(
        find.byKey(const ValueKey('ai.permission.1')),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      expect(answers(fakes), ['allow-once']);
      expect(composer.hasPrimaryFocus, isTrue, reason: 'after Allow');
      await runtime.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a click in the conversation keeps the composer\'s keys too: '
      'keys 1–9 and Esc still answer after a card is opened', (t) async {
    final (fakes, runtime) = await asking(
      t,
      around: (dock) => Column(
        children: [
          const Expanded(child: AiTimeline()),
          dock,
        ],
      ),
    );
    final composer = t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .focusNode!;
    expect(composer.hasPrimaryFocus, isTrue);
    final header = find
        .descendant(of: find.byType(AiToolCard), matching: find.byType(InkWell))
        .first;
    await t.tap(header, kind: PointerDeviceKind.mouse);
    await t.pump();
    expect(composer.hasPrimaryFocus, isTrue, reason: 'after the card');
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pump();
    expect(answers(fakes), ['allow-with-updates']);
    await runtime.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  const planOptions = <Map<String, Object?>>[
    {
      'optionId': 'bypassPermissions',
      'name': 'Yes, and bypass permissions',
      'kind': 'allow_always',
    },
    {
      'optionId': 'acceptEdits',
      'name': 'Yes, and auto-accept edits',
      'kind': 'allow_always',
    },
    {'optionId': 'plan', 'name': 'No, keep planning', 'kind': 'reject_once'},
  ];

  testWidgets('an answer that turns on a mode acting without asking (Claude\'s '
      'ExitPlanMode "Yes, and bypass permissions") shows the Bypass '
      'confirmation first, by click and by key (R6)', (t) async {
    final (fakes, runtime) = await asking(
      t,
      title: 'Ready to code?',
      options: planOptions,
    );
    await t.tap(find.byKey(const ValueKey('ai.permission.1')));
    await t.pumpAndSettle();
    expect(find.text('Turn on “Bypass permissions”?'), findsOneWidget);
    expect(answers(fakes), isEmpty);
    await t.tap(find.byKey(const Key('ai.bypass.cancel')));
    await t.pumpAndSettle();
    expect(answers(fakes), isEmpty);
    expect(
      find.byKey(const Key('ai.permission')),
      findsOneWidget,
      reason: 'still asking',
    );
    // The key says the same, and asks once however often it is pressed.
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pumpAndSettle();
    expect(find.text('Turn on “Bypass permissions”?'), findsOneWidget);
    expect(answers(fakes), isEmpty);
    await t.tap(find.byKey(const Key('ai.bypass.on')));
    await t.pumpAndSettle();
    expect(answers(fakes), ['bypassPermissions']);
    await runtime.dispose();
  });

  testWidgets('the other answers of that request go through at once', (
    t,
  ) async {
    final (fakes, runtime) = await asking(
      t,
      title: 'Ready to code?',
      options: planOptions,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.bypass.on')), findsNothing);
    expect(answers(fakes), ['acceptEdits']);
    await runtime.dispose();
  });

  testWidgets('the first line is a live region of its own, read once; the '
      'rest of the bar is not read with it', (t) async {
    final semantics = t.ensureSemantics();
    // Inside the pane's own container, as in the window: without a container
    // of its own the flag lands on the whole pane.
    final (_, runtime) = await asking(
      t,
      around: (dock) =>
          Semantics(container: true, label: 'AI pane Claude', child: dock),
    );
    expect(liveRegions(t), ['Claude asks: Edit a.ts']);
    semantics.dispose();
    await runtime.dispose();
  });

  testWidgets('holding Esc after a reject does not also stop the turn (key '
      'repeat); a new press does', (t) async {
    final (fakes, runtime) = await asking(t, after: FakeSteps.waitCancel());
    await t.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(fakes), ['reject']);
    for (var i = 0; i < 3; i++) {
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    }
    await t.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(runtime.state.turn, isNotNull, reason: 'the repeats stopped it');
    expect(runtime.state.turn!.cancelRequested, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(runtime.state.turn?.cancelRequested ?? true, isTrue);
    await runtime.dispose();
  });

  testWidgets('a held digit picks once and never types (key repeat)', (
    t,
  ) async {
    final seen = <KeyEvent>[];
    final (fakes, runtime) = await asking(
      t,
      around: (dock) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          seen.add(event);
          return KeyEventResult.ignored;
        },
        child: dock,
      ),
    );
    await t.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(fakes), ['allow-once']);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(seen.whereType<KeyRepeatEvent>(), isEmpty, reason: 'swallowed');
    await runtime.whenIdle();
    await runtime.dispose();
  });
}
