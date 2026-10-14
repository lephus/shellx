import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_ask_card.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/fakes.dart';

const _form = <String, Object?>{
  'mode': 'form',
  'message': 'A few details',
  'requestedSchema': {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'title': 'Name'},
      'age': {'type': 'integer', 'title': 'Age', 'minimum': 0},
      'ok': {'type': 'boolean', 'title': 'Agree'},
      'color': {
        'type': 'string',
        'title': 'Color',
        'enum': ['red', 'blue'],
      },
      'tags': {
        'type': 'array',
        'title': 'Tags',
        'items': {
          'type': 'string',
          'enum': ['a', 'b', 'c'],
        },
      },
    },
    'required': ['name'],
  },
};

/// V2-1 D22: the agent's questions in the conversation.
void main() {
  Future<(FakeAiRuntimes, AiRuntime, TestHarness)> asked(
    WidgetTester t,
    List<Map<String, Object?>> steps,
  ) async {
    final fakes = FakeAiRuntimes(FakeScenario(turns: [steps]));
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await runtime.send([const TextBlock('go')]);
    await t.pump();
    await t.pump();
    return (fakes, runtime, part.harness);
  }

  testWidgets('a form: text, number, yes/no, one and several choices; Send '
      'answers accept with the values, and the card folds', (t) async {
    final (fakes, runtime, _) = await asked(t, [FakeSteps.ask(_form)]);
    expect(find.text('A few details'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.ask.name')), 'Ann');
    await t.enterText(find.byKey(const Key('ai.ask.age')), '30');
    await t.tap(find.byKey(const Key('ai.ask.ok')));
    await t.tap(find.byKey(const Key('ai.ask.color.red')));
    await t.tap(find.byKey(const Key('ai.ask.tags.a')));
    await t.tap(find.byKey(const Key('ai.ask.tags.b')));
    await t.pump();
    await t.tap(find.byKey(const Key('ai.ask.send')));
    await t.pump();
    await t.pump();
    expect(
      fakes.agent().received,
      contains(
        'ask:accept={"name":"Ann","age":30,"ok":true,"color":"red",'
        '"tags":["a","b"]}',
      ),
    );
    expect(find.text('A few details — Answered'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a required field left empty says so and sends nothing; '
      'Decline answers decline', (t) async {
    final (fakes, runtime, _) = await asked(t, [FakeSteps.ask(_form)]);
    await t.tap(find.byKey(const Key('ai.ask.send')));
    await t.pump();
    expect(find.text('Check the marked answers.'), findsOneWidget);
    expect(fakes.agent().received.where((r) => r.startsWith('ask:')), isEmpty);
    await t.tap(find.byKey(const Key('ai.ask.decline')));
    await t.pump();
    await t.pump();
    expect(fakes.agent().received, contains('ask:decline'));
    expect(find.text('A few details — Declined'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a URL: shown whole, opened only on a click, then accept; '
      'elicitation/complete marks it done', (t) async {
    const url = 'https://github.com/login/device';
    final (fakes, runtime, h) = await asked(t, [
      FakeSteps.ask({
        'mode': 'url',
        'message': 'Sign in to GitHub',
        'elicitationId': 'e1',
        'url': url,
      }),
      FakeSteps.completeAsk('e1'),
    ]);
    expect(find.text('Claude asks you to open this page:'), findsOneWidget);
    expect(
      t.widget<SelectableText>(find.byKey(const Key('ai.ask.url'))).data,
      url,
    );
    expect(h.urlOpener.webLinks, isEmpty);
    await t.tap(find.byKey(const Key('ai.ask.open')));
    await t.pump();
    await t.pump();
    expect(h.urlOpener.webLinks, [Uri.parse(url)]);
    expect(fakes.agent().received, contains('ask:accept'));
    expect(find.text('Sign in to GitHub — Done'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a URL that is not http/https cannot be opened', (t) async {
    final (_, runtime, _) = await asked(t, [
      FakeSteps.ask({
        'mode': 'url',
        'message': 'Look',
        'elicitationId': 'e2',
        'url': 'file:///etc/hosts',
      }),
    ]);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('ai.ask.open'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('ai.ask.cancel')));
    await t.pump();
    await runtime.dispose();
  });

  testWidgets('a type ShellX cannot show was declined; the card says so', (
    t,
  ) async {
    final (fakes, runtime, _) = await asked(t, [
      FakeSteps.ask({
        'mode': 'form',
        'message': 'Pick a file',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'file': {'type': 'object'},
          },
        },
      }),
    ]);
    expect(fakes.agent().received, contains('ask:decline'));
    expect(
      find.text(
        'Pick a file — This question uses an answer type ShellX does not '
        'support yet',
      ),
      findsOneWidget,
    );
    await runtime.dispose();
  });

  /// A conversation long enough to scroll, then the question [steps] ends.
  Future<(FakeAiRuntimes, AiRuntime)> askedAfterLongText(WidgetTester t) async {
    final long = List.generate(
      200,
      (i) => 'Paragraph $i of the plan the agent wrote.',
    ).join('\n\n');
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text(long), FakeSteps.ask(_form)],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await runtime.send([const TextBlock('go')]);
    for (var i = 0; i < 10; i++) {
      await t.pump();
    }
    expect(find.text('A few details'), findsOneWidget);
    return (fakes, runtime);
  }

  /// The user scrolls up to re-read the plan, then taps "Jump to latest".
  Future<void> scrollAwayAndBack(WidgetTester t) async {
    // The keyboard goes elsewhere (the composer, a click in another pane).
    FocusManager.instance.primaryFocus?.unfocus();
    // Ink splashes fade (they keep a list item alive while they last).
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    await t.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 20000));
    await t.pump();
    expect(
      find.text('A few details'),
      findsNothing,
      reason: 'the card is out of the list now',
    );
    await t.tap(find.byKey(const Key('ai.jumpToLatest')));
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(find.text('A few details'), findsOneWidget);
  }

  testWidgets('what is typed and picked in a question survives scrolling '
      'away and back, and is what Send answers (a card that waits is kept '
      'alive)', (t) async {
    final (fakes, runtime) = await askedAfterLongText(t);
    await t.enterText(find.byKey(const Key('ai.ask.name')), 'Ann');
    await t.enterText(find.byKey(const Key('ai.ask.age')), '30');
    await t.tap(find.byKey(const Key('ai.ask.ok')));
    await t.tap(find.byKey(const Key('ai.ask.color.blue')));
    await t.tap(find.byKey(const Key('ai.ask.tags.a')));
    await t.tap(find.byKey(const Key('ai.ask.tags.c')));
    await t.pump();
    await scrollAwayAndBack(t);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.ask.name')))
          .controller!
          .text,
      'Ann',
    );
    expect(
      t.widget<TextField>(find.byKey(const Key('ai.ask.age'))).controller!.text,
      '30',
    );
    expect(t.widget<Switch>(find.byKey(const Key('ai.ask.ok'))).value, isTrue);
    expect(
      t.widget<ChoiceChip>(find.byKey(const Key('ai.ask.color.blue'))).selected,
      isTrue,
    );
    expect(
      t.widget<FilterChip>(find.byKey(const Key('ai.ask.tags.a'))).selected,
      isTrue,
    );
    expect(
      t.widget<FilterChip>(find.byKey(const Key('ai.ask.tags.b'))).selected,
      isFalse,
    );
    expect(
      t.widget<FilterChip>(find.byKey(const Key('ai.ask.tags.c'))).selected,
      isTrue,
    );
    await t.tap(find.byKey(const Key('ai.ask.send')));
    await t.pump();
    await t.pump();
    expect(
      fakes.agent().received,
      contains(
        'ask:accept={"name":"Ann","age":30,"ok":true,"color":"blue",'
        '"tags":["a","c"]}',
      ),
    );
    await runtime.dispose();
  });

  testWidgets('a question that was answered is not kept alive: it folds to '
      'one line and goes with the list items that scroll out', (t) async {
    final (fakes, runtime) = await askedAfterLongText(t);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    await t.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 20000));
    await t.pump();
    expect(find.text('A few details'), findsNothing);
    expect(
      find.byType(AiAskCard, skipOffstage: false),
      findsOneWidget,
      reason: 'it waits for an answer: kept alive out of sight',
    );
    // The turn is stopped: the question is answered `cancel`.
    runtime.cancel();
    await runtime.whenIdle();
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(fakes.agent().received, contains('ask:cancel'));
    expect(
      find.byType(AiAskCard, skipOffstage: false),
      findsNothing,
      reason: 'answered: nothing keeps it',
    );
    await runtime.dispose();
  });
}
