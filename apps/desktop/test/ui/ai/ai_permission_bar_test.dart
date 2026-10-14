import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_permission_bar.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  Future<(FakeAiRuntimes, AiRuntime)> asking(
    WidgetTester t, {
    List<Map<String, Object?>> options = FakeSteps.claudeOptions,
  }) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [
            FakeSteps.permission('t1', 'Edit a.ts', options: options),
            FakeSteps.text('done'),
          ],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      AiDock(
        permissionBar: const AiPermissionBar(),
        keyHook: (e, {required hasText}) =>
            aiPermissionKeys(runtime, e, hasText: hasText),
      ),
      runtime: runtime,
    );
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
}
