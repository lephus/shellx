import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart' show JsonMap;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1b final review M-2: keys 1–9 and Esc answer the waiting question from
/// anywhere in the conversation, with the mouse on macOS and Windows too: a
/// click on the agent's words, on the user's message or on the blank space
/// of the conversation must not leave them deaf.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  late FakeAiRuntimes fakes;
  late ProviderContainer c;

  /// A pane whose agent wrote a line and now asks to edit a.ts.
  Future<void> asking(WidgetTester t, {List<List<JsonMap>>? turns}) async {
    fakes = FakeAiRuntimes(
      FakeScenario(
        turns:
            turns ??
            [
              [
                FakeSteps.text('I will edit a.ts now, here is why: long text.'),
                FakeSteps.permission('t1', 'Edit a.ts'),
                FakeSteps.text('done'),
              ],
            ],
      ),
    );
    final workspace = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiFolderExistsProvider.overrideWithValue(
          (path) async => path == testAiCwd,
        ),
      ],
    );
    c = workspace.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'edit it');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.permission')), findsOneWidget);
  }

  FocusNode composer(WidgetTester t) =>
      t.widget<TextField>(find.byKey(const Key('ai.composer'))).focusNode!;

  List<String> answers() => [
    for (final r in fakes.agent().received)
      if (r.startsWith('permission:')) r,
  ];

  Finder inTimeline(Finder f) =>
      find.descendant(of: find.byKey(const Key('ai.timeline')), matching: f);

  Future<void> clickAgentText(WidgetTester t) async {
    await t.tap(
      find.textContaining('here is why'),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
    expect(
      composer(t).hasPrimaryFocus,
      isFalse,
      reason: 'the click took the keyboard (the case under test)',
    );
  }

  Future<void> clickUserMessage(WidgetTester t) async {
    await t.tap(
      inTimeline(find.byType(SelectableText)).first,
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
    expect(composer(t).hasPrimaryFocus, isFalse);
  }

  Future<void> clickBlankSpace(WidgetTester t) async {
    final timeline = t.getRect(find.byKey(const Key('ai.timeline')));
    // The margin beside the 760 px column, at the top.
    await t.tapAt(
      timeline.topLeft + const Offset(4, 4),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
  }

  testWidgets('a click on the agent\'s words, then 1, answers the question', (
    t,
  ) async {
    await asking(t);
    await clickAgentText(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), ['permission:allow-once']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a click on the user\'s message, then 1, answers it', (t) async {
    await asking(t);
    await clickUserMessage(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), ['permission:allow-once']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a click on the blank space of the conversation, then 1, '
      'answers it — and the composer keeps the keyboard', (t) async {
    await asking(t);
    expect(composer(t).hasPrimaryFocus, isTrue);
    await clickBlankSpace(t);
    expect(composer(t).hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), ['permission:allow-once']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Esc after a click on text rejects, as it does from the '
      'composer', (t) async {
    await asking(t);
    await clickAgentText(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(), ['permission:reject']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('every other digit picks its option; one past the last picks '
      'nothing', (t) async {
    await asking(t);
    await clickAgentText(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit9);
    await t.pump();
    expect(answers(), isEmpty, reason: 'three options only');
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.pump();
    expect(answers(), ['permission:reject']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a key is handled once: a held key, or its repeats, answer '
      'only the first question', (t) async {
    await asking(
      t,
      turns: [
        [
          FakeSteps.text('I will edit a.ts now, here is why: long text.'),
          FakeSteps.permission('t1', 'Edit a.ts'),
          FakeSteps.permission('t2', 'Edit b.ts'),
          FakeSteps.text('done'),
        ],
      ],
    );
    await clickAgentText(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), ['permission:allow-once']);
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('ai.permission')),
      findsOneWidget,
      reason: 'the second question is up',
    );
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), [
      'permission:allow-once',
    ], reason: 'repeats are not keys');
    await t.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    // A new press answers the second.
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.pump();
    expect(answers(), ['permission:allow-once', 'permission:reject']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('typing in the composer is never taken: 1 with text in it is '
      'a character, not an answer', (t) async {
    await asking(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'a');
    await t.pump();
    expect(composer(t).hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a dialog over the pane keeps its keys', (t) async {
    await asking(t);
    await t.tap(find.byKey(const Key('ai.more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more.log')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.log.text')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the terminal pane under the AI pane keeps its keys', (t) async {
    await asking(t);
    await t.tap(find.byKey(const Key('ai.terminal')));
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.panes, hasLength(1), reason: 'the terminal pane is there');
    expect(tab.focusedPaneId, tab.panes.keys.single);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
