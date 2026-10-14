import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';

import '../../support/app_harness.dart';

/// V2-2 §5.2–5.4: the dock under the conversation, widget by widget.
void main() {
  /// [settle]: false for a dock that shows a spinner, which never settles.
  Future<void> pumpDock(WidgetTester tester, Widget child, {double height = 900, bool settle = true}) async {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localized(Scaffold(body: SingleChildScrollView(child: child))));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('the question form (V2-1 D22, V2-2 §5.4)', () {
    MirrorAsk ask(Map<String, Object?> properties, {List<String> required = const [], String message = 'Hỏi'}) =>
        MirrorAsk(
          0,
          1,
          1,
          id: 4,
          status: 'open',
          request: ElicitationRequest.fromJson({
            'mode': 'form',
            'message': message,
            'requestedSchema': {'type': 'object', 'properties': properties, 'required': required},
          }),
        );

    late List<ElicitationResponse> answers;

    Future<void> pumpAsk(WidgetTester tester, MirrorAsk item, {bool busy = false, double height = 900}) async {
      answers = [];
      await pumpDock(
        tester,
        AiAskPanel(ask: item, agentName: 'Claude', busy: busy, onAnswer: answers.add),
        height: height,
      );
    }

    Map<String, Object?>? accepted() => answers.isEmpty ? null : (answers.single as ElicitAccept).content;

    testWidgets('every kind of field, and the answer is what was filled in', (tester) async {
      await pumpAsk(
        tester,
        ask(
          {
            'name': {'type': 'string', 'title': 'Tên'},
            'count': {'type': 'integer', 'title': 'Số lượng'},
            'ratio': {'type': 'number', 'title': 'Tỉ lệ'},
            'yes': {'type': 'boolean', 'title': 'Đồng ý'},
            'color': {
              'type': 'string',
              'title': 'Màu',
              'oneOf': [
                {'const': 'r', 'title': 'Đỏ'},
                {'const': 'g', 'title': 'Xanh'},
              ],
            },
            'tags': {
              'type': 'array',
              'title': 'Nhãn',
              'items': {
                'anyOf': [
                  {'const': 'a', 'title': 'Một'},
                  {'const': 'b', 'title': 'Hai'},
                  {'const': 'c', 'title': 'Ba'},
                ],
              },
            },
          },
          required: ['name', 'color'],
        ),
        height: 2400, // the panel keeps to half of the screen: every field is in view
      );
      expect(find.text('Claude hỏi bạn'), findsOneWidget);
      final submit = find.byKey(const Key('ai.ask.submit'));
      await tester.tap(submit);
      await tester.pump();
      expect(answers, isEmpty); // the required fields are empty

      await tester.enterText(find.widgetWithText(TextFormField, 'Tên'), 'Linh');
      await tester.enterText(find.widgetWithText(TextFormField, 'Số lượng'), '3');
      await tester.enterText(find.widgetWithText(TextFormField, 'Tỉ lệ'), '0.5');
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Xanh'));
      await tester.tap(find.text('Một'));
      await tester.tap(find.text('Ba'));
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(accepted(), {
        'name': 'Linh',
        'count': 3,
        'ratio': 0.5,
        'yes': true,
        'color': 'g',
        'tags': ['a', 'c'],
      });
    });

    testWidgets('a value the form does not accept keeps "Gửi câu trả lời" shut', (tester) async {
      await pumpAsk(
        tester,
        ask(
          {
            'age': {'type': 'integer', 'title': 'Tuổi', 'minimum': 18},
          },
          required: ['age'],
        ),
      );
      final submit = find.byKey(const Key('ai.ask.submit'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Tuổi'), '12');
      await tester.pump();
      await tester.tap(submit);
      expect(answers, isEmpty);
      await tester.enterText(find.widgetWithText(TextFormField, 'Tuổi'), '1.5'); // not a whole number
      await tester.pump();
      await tester.tap(submit);
      expect(answers, isEmpty);
      await tester.enterText(find.widgetWithText(TextFormField, 'Tuổi'), '21');
      await tester.pump();
      await tester.tap(submit);
      expect(accepted(), {'age': 21});
    });

    testWidgets('defaults are filled in', (tester) async {
      await pumpAsk(
        tester,
        ask(
          {
            'name': {'type': 'string', 'title': 'Tên', 'default': 'Linh'},
            'yes': {'type': 'boolean', 'title': 'Đồng ý', 'default': true},
          },
          required: ['name'],
        ),
      );
      await tester.tap(find.byKey(const Key('ai.ask.submit')));
      expect(accepted(), {'name': 'Linh', 'yes': true});
    });

    testWidgets('"Từ chối" is always there, and answers decline', (tester) async {
      await pumpAsk(
        tester,
        ask(
          {
            'name': {'type': 'string', 'title': 'Tên'},
          },
          required: ['name'],
        ),
      );
      await tester.tap(find.byKey(const Key('ai.ask.decline')));
      expect(answers.single, isA<ElicitDecline>());
    });

    testWidgets('while an answer is on its way nothing can be sent', (tester) async {
      await pumpAsk(
        tester,
        ask({
          'yes': {'type': 'boolean', 'title': 'Đồng ý'},
        }),
        busy: true,
      );
      await tester.tap(find.byKey(const Key('ai.ask.submit')));
      await tester.tap(find.byKey(const Key('ai.ask.decline')));
      expect(answers, isEmpty);
    });

    testWidgets('a field type ShellX does not know: answered on the computer, declined here', (tester) async {
      await pumpAsk(
        tester,
        ask({
          'when': {'type': 'object', 'title': 'Lúc'},
        }),
      );
      expect(find.text('Câu hỏi này dùng kiểu trả lời ShellX chưa hỗ trợ.'), findsOneWidget);
      expect(find.byKey(const Key('ai.ask.submit')), findsNothing);
      await tester.tap(find.byKey(const Key('ai.ask.decline')));
      expect(answers.single, isA<ElicitDecline>());
    });

    testWidgets('a question that came without its form (too big), or by link: answered on the computer', (
      tester,
    ) async {
      await pumpAsk(tester, const MirrorAsk(0, 1, 1, id: 4, status: 'open'));
      expect(find.text('Trả lời câu hỏi này trên máy tính.'), findsOneWidget);
      expect(find.byKey(const Key('ai.ask.submit')), findsNothing);
      await tester.tap(find.byKey(const Key('ai.ask.decline')));
      expect(answers.single, isA<ElicitDecline>());
    });

    testWidgets('a long form scrolls within half of the screen', (tester) async {
      await pumpAsk(
        tester,
        ask({
          for (var i = 0; i < 30; i++) 'f$i': {'type': 'string', 'title': 'Trường $i'},
        }),
      );
      expect(tester.getSize(find.byKey(const Key('ai.ask'))).height, lessThanOrEqualTo(450 + 8)); // + its margin
      expect(tester.takeException(), isNull);
    });
  });

  group('the queue', () {
    testWidgets('each waiting message has its ×, which removes that one', (tester) async {
      final removed = <int>[];
      await pumpDock(
        tester,
        AiQueueRow(queue: const [MirrorQueued(7, 'tin một'), MirrorQueued(9, 'tin hai')], onRemove: removed.add),
      );
      expect(find.text('Đang xếp hàng'), findsNWidgets(2));
      expect(find.text('tin một'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai.unqueue.9')));
      expect(removed, [9]);
      expect(find.byTooltip('Bỏ khỏi hàng đợi'), findsNWidgets(2));
    });
  });

  group('the plan', () {
    testWidgets('one line "Kế hoạch · 2/3", opened by a tap', (tester) async {
      await pumpDock(
        tester,
        const AiPlanStrip(
          plan: [
            PlanEntry(content: 'Đọc mã', status: PlanStatus.completed),
            PlanEntry(content: 'Sửa mã', status: PlanStatus.completed),
            PlanEntry(content: 'Chạy thử', status: PlanStatus.pending),
          ],
        ),
      );
      expect(find.text('Kế hoạch · 2/3'), findsOneWidget);
      expect(find.text('Sửa mã'), findsNothing);
      await tester.tap(find.byKey(const Key('ai.plan')));
      await tester.pumpAndSettle();
      expect(find.text('Sửa mã'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsNWidgets(2));
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai.plan')));
      await tester.pumpAndSettle();
      expect(find.text('Sửa mã'), findsNothing);
    });
  });

  group('the text field and its buttons (V2-1 D16)', () {
    late TextEditingController text;
    late List<String> taps;

    setUp(() {
      text = TextEditingController();
      taps = [];
    });

    tearDown(() => text.dispose());

    Future<void> pumpComposer(
      WidgetTester tester, {
      bool enabled = true,
      bool running = false,
      bool stopping = false,
      bool canForceStop = false,
      bool sending = false,
      bool settle = true,
    }) => pumpDock(
      settle: settle,
      tester,
      AiComposer(
        controller: text,
        agentName: 'Claude',
        enabled: enabled,
        running: running,
        stopping: stopping,
        canForceStop: canForceStop,
        sending: sending,
        onSend: () => taps.add('send'),
        onStop: () => taps.add('stop'),
        onForceStop: () => taps.add('force'),
      ),
    );

    IconButton button(WidgetTester tester, String key) => tester.widget<IconButton>(find.byKey(Key(key)));

    testWidgets('Send waits for text, and says what the field asks', (tester) async {
      await pumpComposer(tester);
      expect(find.text('Nhắn cho Claude…'), findsOneWidget);
      expect(button(tester, 'ai.send').onPressed, isNull);
      await tester.enterText(find.byKey(const Key('ai.composer')), '   ');
      await tester.pump();
      expect(button(tester, 'ai.send').onPressed, isNull); // spaces are not a message
      await tester.enterText(find.byKey(const Key('ai.composer')), 'Thêm nút');
      await tester.pump();
      expect(button(tester, 'ai.send').tooltip, 'Gửi');
      await tester.tap(find.byKey(const Key('ai.send')));
      expect(taps, ['send']);
    });

    testWidgets('while a turn runs a message is queued, and an empty field offers Stop', (tester) async {
      await pumpComposer(tester, running: true);
      expect(find.byKey(const Key('ai.send')), findsNothing);
      await tester.tap(find.byKey(const Key('ai.stop')));
      expect(taps, ['stop']);
      await tester.enterText(find.byKey(const Key('ai.composer')), 'thêm nữa');
      await tester.pump();
      expect(find.byKey(const Key('ai.stop')), findsNothing);
      expect(button(tester, 'ai.send').tooltip, 'Xếp hàng');
    });

    testWidgets('Stop waits while it is being asked, and shows a spinner (the only one here)', (tester) async {
      await pumpComposer(tester, running: true, stopping: true, settle: false);
      expect(button(tester, 'ai.stop').onPressed, isNull);
      expect(button(tester, 'ai.stop').tooltip, 'Đang dừng…');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100)); // a spinner is the only thing moving
    });

    testWidgets('"Dừng hẳn" once the computer offers it', (tester) async {
      await pumpComposer(tester, running: true, canForceStop: true);
      await tester.tap(find.byKey(const Key('ai.forceStop')));
      expect(taps, ['force']);
      await pumpComposer(tester, running: true);
      expect(find.byKey(const Key('ai.forceStop')), findsNothing);
    });

    testWidgets('a message on its way cannot be sent again', (tester) async {
      text.text = 'Thêm nút';
      await pumpComposer(tester, sending: true, settle: false);
      expect(button(tester, 'ai.send').onPressed, isNull);
    });

    testWidgets('locked while the link is away or the computer takes no prompt: the draft is kept', (tester) async {
      text.text = 'bản nháp';
      await pumpComposer(tester, enabled: false);
      final field = tester.widget<TextField>(find.byKey(const Key('ai.composer')));
      expect((field.enabled, field.controller!.text), (false, 'bản nháp'));
      expect(button(tester, 'ai.send').onPressed, isNull);
    });

    testWidgets('a long message grows the field up to six lines', (tester) async {
      await pumpComposer(tester);
      await tester.enterText(find.byKey(const Key('ai.composer')), List.generate(20, (i) => 'dòng $i').join('\n'));
      await tester.pump();
      final field = tester.widget<TextField>(find.byKey(const Key('ai.composer')));
      expect((field.minLines, field.maxLines), (1, 6));
      expect(tester.getSize(find.byKey(const Key('ai.composer'))).height, lessThan(200));
    });
  });
}
