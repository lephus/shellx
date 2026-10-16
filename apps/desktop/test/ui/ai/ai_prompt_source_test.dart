import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// V2-2b B24: on the computer, a prompt written on a paired phone says so,
/// in the conversation and in the queue.
void main() {
  final at = DateTime(2026, 10, 15, 9);

  List<String> labels(WidgetTester t) => [
    for (final e in find.byKey(const Key('ai.user.label')).evaluate())
      (e.widget as Text).data!,
  ];

  testWidgets('the phone\'s prompt reads "You · from your phone", the '
      'computer\'s "You"', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn(const [TextBlock('Sửa lỗi')], at, source: PromptSource.phone)
      ..endTurn(outcome: TurnOutcome.finished, at: at)
      ..beginTurn(const [TextBlock('Thêm test')], at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(labels(t), ['You · from your phone', 'You']);
  });

  testWidgets('in Vietnamese: "Bạn · từ điện thoại"', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state.beginTurn(
      const [TextBlock('Sửa lỗi')],
      at,
      source: PromptSource.phone,
    );
    await pumpAiPart(
      t,
      const AiTimeline(),
      runtime: runtime,
      locale: const Locale('vi'),
    );
    await t.pump();
    expect(labels(t), ['Bạn · từ điện thoại']);
  });

  Future<void> row(WidgetTester t, {required bool fromPhone}) => t.pumpWidget(
    MaterialApp(
      theme: buildDesktopTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: AiQueuedRow(
          text: 'then this',
          fromPhone: fromPhone,
          onRemove: () {},
        ),
      ),
    ),
  );

  String queued(WidgetTester t) => t
      .widget<Text>(find.byKey(const Key('ai.queued.text')))
      .textSpan!
      .toPlainText();

  testWidgets('a queued prompt from the phone is led by "You · from your '
      'phone"; one from the computer is not', (t) async {
    await row(t, fromPhone: true);
    expect(
      queued(t),
      'You · from your phone · Queued: “then this” — sent when this turn ends',
    );
    await row(t, fromPhone: false);
    expect(queued(t), 'Queued: “then this” — sent when this turn ends');
  });

  testWidgets('in the dock, a prompt queued from the phone says so while it '
      'waits; one queued on the computer does not (spec criterion 12)', (
    t,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn(const [TextBlock('Sửa lỗi')], at)
      ..enqueue(const [TextBlock('rồi chạy test')], source: PromptSource.phone)
      ..enqueue(const [TextBlock('rồi commit')]);
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.pump();
    final rows = t.widgetList<AiQueuedRow>(find.byType(AiQueuedRow));
    expect(
      [for (final r in rows) (r.text, r.fromPhone)],
      [('rồi chạy test', true), ('rồi commit', false)],
    );
    expect(
      [
        for (final e in find.byKey(const Key('ai.queued.text')).evaluate())
          (e.widget as Text).textSpan!.toPlainText(),
      ],
      [
        'You · from your phone · Queued: “rồi chạy test” — sent when this '
            'turn ends',
        'Queued: “rồi commit” — sent when this turn ends',
      ],
    );
  });
}
