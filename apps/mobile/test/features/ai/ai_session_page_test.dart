import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_timeline.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';
import '../../support/widget_probes.dart';

const sid = 'e.-1';

void say(AiSessionState s, String text) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  }),
  DateTime.now(),
);

void tool(AiSessionState s, String id, Map<String, Object?> fields) =>
    s.applyUpdate(SessionUpdate.fromJson({'sessionUpdate': 'tool_call', 'toolCallId': id, ...fields}), DateTime.now());

PermissionRequest perm() => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': 'c1', 'title': 'Edit src/main.ts', 'kind': 'edit'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'always', 'name': 'Yes, allow all edits during this session', 'kind': 'allow_always'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

/// V2-2 §5.2–5.3: the AI session page.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late FakePopupHandler popups;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    popups = FakePopupHandler();
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session),
      );
  });

  tearDown(() async => getIt.reset());

  /// Opens the page of [sid]; the desktop state is `machine.ai.session(sid).desktop`.
  Future<FakeAiSession> open(WidgetTester tester, {List<Object?>? results}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ai = machine.ai.session(sid);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
        results: results,
      ),
    );
    await tester.pumpAndSettle();
    // Not openPushed: the page shows a spinner until the snapshot arrives.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    return ai;
  }

  testWidgets('the conversation as the desktop holds it; the status in the header', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('Thêm nút đăng xuất')], DateTime.now());
    say(ai.desktop, 'Mình sẽ thêm **nút** và ![ảnh](https://example.com/x.png) xong.');
    tool(ai.desktop, 'c1', {
      'title': 'Read main.ts',
      'kind': 'read',
      'status': 'completed',
      'locations': [
        {'path': '/p/src/main.ts'},
      ],
    });
    await open(tester);
    final timeline = find.byKey(const Key('ai.timeline'));
    expect(find.descendant(of: timeline, matching: find.text('Thêm nút đăng xuất')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ai.title'))).data, 'Thêm nút đăng xuất');
    expect(find.textContaining('Mình sẽ thêm'), findsOneWidget);
    expect(find.byType(Image), findsNothing); // markdown never loads images
    expect(find.text('Đọc main.ts'), findsOneWidget);
    final status = tester.widget<Text>(find.byKey(const Key('ai.status'))).data!;
    expect(status, startsWith('Claude · Đang chạy · 0:0'));
  });

  testWidgets('a permission: big buttons in the agent\'s order, one tap answers once, '
      'nothing is ever answered without a tap', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
    final p = ai.desktop.addPermission(perm(), DateTime.now());
    await open(tester);
    expect(find.byKey(const Key('ai.permission')), findsOneWidget);
    expect(find.text('Edit src/main.ts'), findsWidgets);
    expect(find.text('Cho phép'), findsOneWidget);
    expect(find.text('Luôn cho phép'), findsOneWidget);
    expect(find.text('Yes, allow all edits during this session'), findsOneWidget);
    expect(find.text('Từ chối'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(machine.ai.permissionAnswers, isEmpty);

    machine.ai.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('ai.option.allow')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.option.reject')));
    await tester.pump();
    expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow')]);
    machine.ai.gate!.complete();
    ai.desktop.resolvePermission(p.id, const PermissionSelected('allow'));
    ai.sync();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.permission')), findsNothing);
    expect(find.text('Bạn chọn: Cho phép (Yes)'), findsOneWidget);
  });

  testWidgets('answered on another device: says so', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
    ai.desktop.addPermission(perm(), DateTime.now());
    await open(tester);
    machine.ai.failWith = 'stale';
    await tester.tap(find.byKey(const Key('ai.option.allow')));
    await tester.pumpAndSettle();
    expect(popups.errors, ['Đã được trả lời ở thiết bị khác.']);
  });

  testWidgets('send, queue while running, stop; a refused send keeps the text', (tester) async {
    final ai = await open(tester);
    expect(find.text('Chưa có tin nhắn. Viết tin đầu tiên ở ô dưới.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ai.composer')), 'Thêm nút đăng xuất');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts, [(sid, 'Thêm nút đăng xuất')]);
    expect(find.text('Thêm nút đăng xuất'), findsNothing); // cleared (the desktop has not echoed it yet)

    ai.desktop.beginTurn(const [TextBlock('Thêm nút đăng xuất')], DateTime.now());
    ai.sync();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.stop')));
    await tester.pumpAndSettle();
    expect(machine.ai.cancels, [sid]);

    machine.ai.failWith = 'queue_full';
    await tester.enterText(find.byKey(const Key('ai.composer')), 'thêm nữa');
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(const Key('ai.send'))).tooltip, 'Xếp hàng');
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pumpAndSettle();
    expect(popups.errors, ['Đã có 5 tin đang chờ.']);
    expect(find.text('thêm nữa'), findsOneWidget);
  });

  testWidgets('a question: Gửi only once the form accepts the values', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
    final ask = ai.desktop.addAsk(
      ElicitationRequest.fromJson({
        'mode': 'form',
        'message': 'Màu nào?',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'pick': {
              'type': 'string',
              'oneOf': [
                {'const': 'a', 'title': 'Xanh'},
                {'const': 'b', 'title': 'Đỏ'},
              ],
            },
          },
          'required': ['pick'],
        },
      }),
    )!;
    await open(tester);
    expect(find.byKey(const Key('ai.ask')), findsOneWidget);
    final submit = find.byKey(const Key('ai.ask.submit'));
    await tester.tap(submit);
    await tester.pump();
    expect(machine.ai.askAnswers, isEmpty);
    await tester.tap(find.text('Đỏ'));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final (_, id, response) = machine.ai.askAnswers.single;
    expect(id, ask.id);
    expect((response as ElicitAccept).content, {'pick': 'b'});
  });

  testWidgets('closed on the computer, or reconnecting: says so', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
    await open(tester);
    ai.lose();
    await tester.pump();
    expect(find.text('Đang kết nối lại… nội dung có thể chưa mới nhất.'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.text('go')),
      findsOneWidget,
    ); // the mirror stays
    ai.close('desktop_closed');
    await tester.pump();
    expect(find.text('ShellX trên máy tính đã thoát. Mở lại để tiếp tục.'), findsOneWidget);
    expect(find.byKey(const Key('ai.composer')), findsNothing);
  });

  testWidgets('the computer cannot be reached: says so instead of a spinner', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    machine.emitState(const MachineFailed(MachineConnectionFailure.agentOffline));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('ai.offline')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a session that cannot run says why, without a text field (D14)', (tester) async {
    final ai = await open(tester);
    ai.mirror.apply({
      'g': 0,
      'from': 0,
      'n': 0,
      'reset': true,
      'head': {'phase': 'stopped', 'agent': 'claude', 'name': 'Claude', 'unavailable': 'no_folder'},
      'items': <Object?>[],
    }, snapshot: true);
    ai.sync(); // nothing new from the desktop state; the link stays live
    await tester.pumpAndSettle();
    expect(find.text('Chọn thư mục trên máy tính'), findsWidgets);
    expect(find.byKey(const Key('ai.unavailable')), findsOneWidget);
    expect(find.byKey(const Key('ai.composer')), findsNothing);
  });

  testWidgets('older items come with Tải thêm; leaving detaches', (tester) async {
    final ai = machine.ai.session(sid);
    ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
    for (var i = 0; i < 100; i++) {
      tool(ai.desktop, 'c$i', {'title': 'Read f$i.ts', 'kind': 'read'});
    }
    await open(tester);
    expect(ai.mirror.hasEarlier, isTrue);
    await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.loadEarlier')));
    await tester.pumpAndSettle();
    expect((ai.earlierCalls, ai.mirror.from), (1, 0));
    await tester.tap(find.byKey(const Key('ai.back')));
    await tester.pumpAndSettle();
    expect(ai.detached, isTrue);
  });

  // ----------------------------------------------------------------------------------------------
  // Beyond the brief: what Tasks 6–8 and their reviews left to this page, and the phone's smoothness.
  // ----------------------------------------------------------------------------------------------

  /// A body put straight into the phone's mirror, as a computer could send it (a newer one, or one
  /// whose header was cut to fit): the page has to cope with what the real subscription seldom makes.
  void feed(FakeAiSession ai, {required Map<String, Object?> head, List<Map<String, Object?>> items = const []}) {
    ai.mirror.apply({
      'v': 1,
      'g': 0,
      'from': 0,
      'n': items.length,
      'reset': true,
      'head': head,
      'items': items,
    }, snapshot: true);
    ai.sync(); // nothing new from the desktop state: it only tells the page
  }

  Map<String, Object?> runningHead({Map<String, Object?>? perm, Map<String, Object?>? ask, String? unavailable}) => {
    'phase': 'running',
    'agent': 'claude',
    'name': 'Claude',
    'turn': {'n': 1, 't0': DateTime.now().millisecondsSinceEpoch},
    'perm': ?perm,
    'ask': ?ask,
    'unavailable': ?unavailable,
  };

  Map<String, Object?> toolRecord(
    int i, {
    String kind = 'execute',
    String title = 'npm test',
    Map<String, Object?>? extra,
  }) => {
    'i': i,
    'r': 1,
    'turn': 1,
    'k': 'tool',
    'id': 'c$i',
    'tk': kind,
    'title': title,
    'st': 'completed',
    'end': 'completed',
    ...?extra,
  };

  Map<String, Object?> textRecord(int i, String kind, String text) => {
    'i': i,
    'r': 1,
    'turn': 1,
    'k': kind,
    'at': 0,
    'add': text,
  };

  /// A page whose session has not answered yet (no snapshot).
  Future<void> openUnanswered(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  Rect timelineRect(WidgetTester tester) => tester.getRect(find.byKey(const Key('ai.timeline')));

  ScrollPosition timelinePosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.byType(Scrollable)).first,
      )
      .position;

  group('a session that closes or cannot run has its own words (V2-2 §5.5, D14)', () {
    for (final (reason, text) in [
      ('gone', 'Phiên AI này đã đóng trên máy tính.'),
      ('desktop_closed', 'ShellX trên máy tính đã thoát. Mở lại để tiếp tục.'),
      ('unavailable', 'Mở ShellX trên máy tính để dùng phiên AI.'),
      ('unreadable', 'Điện thoại không đọc được phiên AI này. Xem trên máy tính.'),
      ('a_reason_from_the_future', 'Phiên AI này đã đóng trên máy tính.'),
    ]) {
      testWidgets('the computer closed it: "$reason"', (tester) async {
        final ai = machine.ai.session(sid);
        ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
        await open(tester);
        ai.close(reason);
        await tester.pump();
        expect(find.descendant(of: find.byKey(const Key('ai.closed')), matching: find.text(text)), findsOneWidget);
        expect(find.byKey(const Key('ai.composer')), findsNothing);
        expect(find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.text('go')), findsOneWidget);
        expect(popups.errors, isEmpty);
      });
    }

    testWidgets('leaving a session the computer closed detaches it too: its mirror is let go', (tester) async {
      final ai = await open(tester);
      ai.close('desktop_closed');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.back')));
      await tester.pumpAndSettle();
      expect(ai.detached, isTrue);
    });

    testWidgets('no window serves AI on the computer: said calmly, no spinner, no error, nowhere to write', (
      tester,
    ) async {
      await openUnanswered(tester);
      machine.ai.session(sid).close('unavailable'); // the answer to ai.attach when no window serves AI
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: find.byKey(const Key('ai.closed')),
          matching: find.text('Mở ShellX trên máy tính để dùng phiên AI.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Chưa có tin nhắn. Viết tin đầu tiên ở ô dưới.'), findsNothing);
      expect(find.byKey(const Key('ai.composer')), findsNothing);
      expect(popups.errors, isEmpty);
    });

    testWidgets('a session that cannot run keeps its past on show, with the reason beside it and no text field', (
      tester,
    ) async {
      final ai = await open(tester);
      feed(
        ai,
        head: {'phase': 'stopped', 'agent': 'claude', 'name': 'Claude', 'unavailable': 'agent_off'},
        items: [textRecord(0, 'user', 'Thêm nút đăng xuất')],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.unavailable')), findsOneWidget);
      expect(find.text('Agent đang tắt trên máy tính'), findsWidgets);
      expect(
        find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.text('Thêm nút đăng xuất')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai.composer')), findsNothing);
    });
  });

  group('the computer is not reached: the machine says it, never an endless spinner', () {
    for (final (failure, text) in [
      (MachineConnectionFailure.agentOffline, 'Máy tính đang offline. Hãy mở ShellX trên máy tính rồi thử lại.'),
      (MachineConnectionFailure.timeout, 'Máy tính không phản hồi. Hãy thử lại.'),
      (MachineConnectionFailure.untrusted, 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'),
      (MachineConnectionFailure.protocolUnsupported, 'Cần cập nhật app'),
    ]) {
      testWidgets('${failure.name}, the link still attaching', (tester) async {
        await openUnanswered(tester);
        machine.emitState(MachineFailed(failure));
        await tester.pump(const Duration(milliseconds: 500));
        expect(machine.ai.session(sid).state, AiLinkState.attaching);
        expect(find.descendant(of: find.byKey(const Key('ai.offline')), matching: find.text(text)), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const Key('ai.composer')), findsNothing);
      });
    }

    testWidgets('a kept conversation stays, with the machine\'s words instead of "reconnecting"', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      await open(tester);
      await tester.enterText(find.byKey(const Key('ai.composer')), 'bản nháp');
      machine.emitState(const MachineFailed(MachineConnectionFailure.agentOffline));
      ai.lose();
      await tester.pump();
      expect(find.byKey(const Key('ai.offline')), findsOneWidget);
      expect(find.text('Đang kết nối lại… nội dung có thể chưa mới nhất.'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.text('go')), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('ai.composer')));
      expect((field.enabled, field.controller!.text), (false, 'bản nháp')); // locked, the draft kept
    });

    testWidgets('the machine is not pinned any more: its words, not "closed on the computer"', (tester) async {
      backend.pinnedList = [];
      backend.machines.clear();
      await openUnanswered(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: find.byKey(const Key('ai.offline')),
          matching: find.text('Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'),
        ),
        findsOneWidget,
      );
      expect(find.text('Phiên AI này đã đóng trên máy tính.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('a request that may have landed is never sent again (D13)', () {
    const unknown = 'Có thể chưa gửi được — kết nối bị gián đoạn. Hãy xem lại phiên trước khi thử lại.';
    for (final (failure, text) in [
      (MachineConnectionFailure.agentOffline, unknown),
      (MachineConnectionFailure.timeout, unknown),
      (MachineConnectionFailure.untrusted, 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'),
      (MachineConnectionFailure.protocolUnsupported, 'Cần cập nhật app'),
    ]) {
      testWidgets('a message that fails with ${failure.name}: said, the text stays, nothing is sent by itself', (
        tester,
      ) async {
        final ai = await open(tester);
        machine.ai.connectFailure = failure;
        await tester.enterText(find.byKey(const Key('ai.composer')), 'Thêm nút đăng xuất');
        await tester.pump();
        await tester.tap(find.byKey(const Key('ai.send')));
        await tester.pumpAndSettle();
        expect(popups.errors, [text]);
        final field = tester.widget<TextField>(find.byKey(const Key('ai.composer')));
        expect(field.controller!.text, 'Thêm nút đăng xuất');
        expect(machine.ai.prompts, [(sid, 'Thêm nút đăng xuất')]);

        // The computer comes back and the link resumes: the message is not sent again by itself.
        machine.ai.connectFailure = null;
        ai
          ..lose()
          ..sync();
        await tester.pump(const Duration(minutes: 5));
        expect(machine.ai.prompts, hasLength(1));
        expect(field.controller!.text, 'Thêm nút đăng xuất');

        // The user looks at the session and decides: only their tap sends it.
        await tester.tap(find.byKey(const Key('ai.send')));
        await tester.pumpAndSettle();
        expect(machine.ai.prompts, hasLength(2));
        expect(field.controller!.text, isEmpty);
      });
    }

    for (final failure in [MachineConnectionFailure.agentOffline, MachineConnectionFailure.timeout]) {
      testWidgets('an answer that fails with ${failure.name}: said, the user answers again if they want', (
        tester,
      ) async {
        final ai = machine.ai.session(sid);
        ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
        final p = ai.desktop.addPermission(perm(), DateTime.now());
        await open(tester);
        machine.ai.connectFailure = failure;
        await tester.tap(find.byKey(const Key('ai.option.allow')));
        await tester.pumpAndSettle();
        expect(popups.errors, [unknown]);
        await tester.pump(const Duration(minutes: 5));
        expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow')]); // nothing by itself

        machine.ai.connectFailure = null;
        await tester.tap(find.byKey(const Key('ai.option.reject'))); // the buttons work again
        await tester.pumpAndSettle();
        expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow'), (sid, p.id, 'reject')]);
      });
    }

    testWidgets('a stop that fails with agentOffline says it too', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      await open(tester);
      machine.ai.connectFailure = MachineConnectionFailure.agentOffline;
      await tester.tap(find.byKey(const Key('ai.stop')));
      await tester.pumpAndSettle();
      expect(popups.errors, [unknown]);
      expect(machine.ai.cancels, [sid]);
    });

    testWidgets('an option the computer keeps for itself (on_computer): its words, and the panel stays', (
      tester,
    ) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      final p = ai.desktop.addPermission(perm(), DateTime.now());
      await open(tester);
      machine.ai.failWith = 'on_computer'; // e.g. an option that would turn on a mode without approval
      await tester.tap(find.byKey(const Key('ai.option.always')));
      await tester.pumpAndSettle();
      expect(popups.errors, ['Trả lời yêu cầu này trên máy tính.']);
      expect(find.byKey(const Key('ai.permission')), findsOneWidget); // still open, for the computer
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'always')]);

      // The user may take another option; nothing was answered for them.
      machine.ai.failWith = null;
      await tester.tap(find.byKey(const Key('ai.option.reject')));
      await tester.pumpAndSettle();
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'always'), (sid, p.id, 'reject')]);
    });

    for (final (code, text) in [
      ('not_found', 'Phiên AI này đã đóng trên máy tính.'),
      ('unavailable', 'Mở ShellX trên máy tính để dùng phiên AI.'),
    ]) {
      testWidgets('the computer answers "$code": its words, the text stays', (tester) async {
        await open(tester);
        machine.ai.failWith = code;
        await tester.enterText(find.byKey(const Key('ai.composer')), 'Thêm nút');
        await tester.pump();
        await tester.tap(find.byKey(const Key('ai.send')));
        await tester.pumpAndSettle();
        expect(popups.errors, [text]);
        expect(find.text('Thêm nút'), findsOneWidget);
      });
    }

    testWidgets('a request in flight when the session closes ends with the closed words, once', (tester) async {
      final ai = await open(tester);
      machine.ai.gate = Completer<void>();
      await tester.enterText(find.byKey(const Key('ai.composer')), 'Thêm nút');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.send')));
      await tester.pump();
      ai.close('gone');
      machine.ai.failWith = 'not_found';
      machine.ai.gate!.complete();
      await tester.pumpAndSettle();
      expect(popups.errors, ['Phiên AI này đã đóng trên máy tính.']);
      expect(find.byKey(const Key('ai.closed')), findsOneWidget);
    });
  });

  group('the dock', () {
    testWidgets('a permission without options is answered on the computer, with no empty row of buttons', (
      tester,
    ) async {
      final ai = await open(tester);
      feed(
        ai,
        head: runningHead(perm: {'id': 7, 'item': 0, 'title': 'Edit src/main.ts', 'options': <Object?>[]}),
        items: [
          toolRecord(0, kind: 'edit', title: 'Edit src/main.ts', extra: {'perm': 'waiting', 'end': null}),
        ],
      );
      await tester.pumpAndSettle();
      final panel = find.byKey(const Key('ai.permission'));
      expect(panel, findsOneWidget);
      expect(find.descendant(of: panel, matching: find.text('Trả lời yêu cầu này trên máy tính.')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ai.option.'),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(minutes: 1));
      expect(machine.ai.permissionAnswers, isEmpty);
    });

    testWidgets('"Xem chi tiết" is offered only for a card the phone holds', (tester) async {
      final ai = await open(tester);
      final options = [
        {'id': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
      ];
      feed(
        ai,
        head: runningHead(perm: {'id': 7, 'item': 99, 'title': 'Edit a.ts', 'options': options}),
        items: [textRecord(0, 'user', 'Sửa')],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.permission')), findsOneWidget);
      expect(find.byKey(const Key('ai.permission.details')), findsNothing); // item 99 is not here
      feed(
        ai,
        head: runningHead(perm: {'id': 7, 'item': 1, 'title': 'Edit a.ts', 'options': options}),
        items: [
          textRecord(0, 'user', 'Sửa'),
          toolRecord(1, kind: 'edit', title: 'Edit a.ts', extra: {'perm': 'waiting'}),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.permission.details')), findsOneWidget);
    });

    testWidgets('a question whose card the phone does not hold is answered on the computer, and can be declined', (
      tester,
    ) async {
      final ai = await open(tester);
      feed(
        ai,
        head: runningHead(ask: {'id': 5, 'item': 99}),
        items: [textRecord(0, 'user', 'Hỏi')],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.ask')), findsOneWidget);
      expect(find.text('Trả lời câu hỏi này trên máy tính.'), findsOneWidget);
      expect(find.byKey(const Key('ai.ask.submit')), findsNothing);
      await tester.tap(find.byKey(const Key('ai.ask.decline')));
      await tester.pumpAndSettle();
      final (_, id, response) = machine.ai.askAnswers.single;
      expect(id, 5);
      expect(response, isA<ElicitDecline>());
    });

    testWidgets('cards the phone cannot draw are read on the computer, each with its own words', (tester) async {
      final ai = await open(tester);
      feed(
        ai,
        head: {'phase': 'ready', 'agent': 'claude', 'name': 'Claude'},
        items: [
          {'i': 0, 'r': 1, 'turn': 1, 'k': 'big'},
          {'i': 1, 'r': 1, 'turn': 1, 'k': 'hologram'},
          {'i': 2, 'r': 1, 'turn': 1},
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Quá lớn để xem trên điện thoại. Xem trên máy tính.'), findsOneWidget);
      expect(find.text('Điện thoại chưa hỗ trợ loại mục này. Xem trên máy tính.'), findsNWidgets(2));
    });

    testWidgets('an answer waits for the computer to move on: a second tap cannot answer again', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      final p = ai.desktop.addPermission(perm(), DateTime.now());
      await open(tester);
      await tester.tap(find.byKey(const Key('ai.option.allow')));
      await tester.pumpAndSettle(); // the computer took it; its header still shows the request
      expect(find.byKey(const Key('ai.permission')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai.option.reject')));
      await tester.pumpAndSettle();
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow')]);
      expect(popups.errors, isEmpty);

      ai.desktop.resolvePermission(p.id, const PermissionSelected('allow'));
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.permission')), findsNothing);
    });

    testWidgets('leaving while an answer is on its way is harmless: nothing is shown, nothing is sent again', (
      tester,
    ) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      final p = ai.desktop.addPermission(perm(), DateTime.now());
      await open(tester);
      machine.ai.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('ai.option.allow')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.back')));
      await tester.pumpAndSettle();
      expect(ai.detached, isTrue);
      machine.ai.failWith = 'stale';
      machine.ai.gate!.complete(); // the answer comes back to a page that is gone
      await tester.pumpAndSettle();
      expect(popups.errors, isEmpty);
      expect(tester.takeException(), isNull);
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'allow')]);
    });

    testWidgets('a lost connection answers nothing; the buttons wait for the link and come back with it', (
      tester,
    ) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      ai.desktop.addPermission(perm(), DateTime.now());
      await open(tester);
      ai.lose();
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.option.allow')), warnIfMissed: false);
      await tester.pump(const Duration(minutes: 5));
      expect(machine.ai.permissionAnswers, isEmpty);
      ai.sync(); // the link is back with what the computer holds: the request is still waiting
      await tester.pumpAndSettle();
      expect(machine.ai.permissionAnswers, isEmpty); // not by itself
      await tester.tap(find.byKey(const Key('ai.option.allow')));
      await tester.pumpAndSettle();
      expect(machine.ai.permissionAnswers, hasLength(1));
    });

    testWidgets('"Xem chi tiết" brings the card in, however far, and every time', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      for (var i = 0; i < 150; i++) {
        tool(ai.desktop, 'c$i', {
          'title': 'Read f$i.ts',
          'kind': 'read',
          'status': 'completed',
          'locations': [
            {'path': '/p/f$i.ts'},
          ],
        });
      }
      ai.desktop.addPermission(
        PermissionRequest.fromJson({
          'sessionId': 's',
          'toolCall': {'toolCallId': 'edit', 'title': 'Edit src/main.ts', 'kind': 'edit'},
          'options': [
            {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
            {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
          ],
        }),
        DateTime.now(),
      );
      await open(tester);
      final card = find.byWidgetPredicate((w) => w is AiToolCard && w.tool.permission == MirrorPermissionState.waiting);
      bool inView() {
        final rect = tester.getRect(card);
        final view = timelineRect(tester);
        return rect.top >= view.top && rect.bottom <= view.bottom;
      }

      for (var round = 0; round < 2; round++) {
        await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000)); // far away, to the top
        await tester.pumpAndSettle();
        expect(card, findsNothing);
        await tester.tap(find.byKey(const Key('ai.permission.details')));
        await tester.pumpAndSettle();
        expect(card, findsOneWidget, reason: 'round $round');
        expect(inView(), isTrue, reason: 'round $round');
      }
      // A little away: the card is still built, and the same request brings it back.
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai.permission.details')));
      await tester.pumpAndSettle();
      expect(inView(), isTrue);
    });

    testWidgets('a small screen with the keyboard open: every option can still be reached', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('Sửa')], DateTime.now());
      final p = ai.desktop.addPermission(
        PermissionRequest.fromJson({
          'sessionId': 's',
          'toolCall': {'toolCallId': 'c1', 'title': 'Edit src/main.ts', 'kind': 'edit'},
          'options': [
            for (var i = 0; i < 5; i++)
              {
                'optionId': 'o$i',
                'name': 'Option $i of the agent',
                'kind': ['allow_once', 'allow_always', 'reject_once', 'reject_always', 'other'][i],
              },
          ],
        }),
        DateTime.now(),
      );
      await open(tester);
      tester.view.physicalSize = const Size(1080, 1920); // 360 × 640
      tester.view.viewInsets = const FakeViewPadding(bottom: 840); // a 280-point keyboard
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('ai.option.o4')));
      await tester.tap(find.byKey(const Key('ai.option.o4')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(machine.ai.permissionAnswers, [(sid, p.id, 'o4')]);
    });
  });

  group('older items (V2-2 D5)', () {
    testWidgets('"Tải thêm" goes on, a short page at a time, until the first item', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 200; i++) {
        tool(ai.desktop, 'c$i', {
          'title': 'cat f$i.log',
          'kind': 'execute',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': List.filled(60, 'x' * 150).join('\n')}, // ≈ 9 KB, cut to 8 KB
            },
          ],
        });
      }
      await open(tester);
      expect(ai.mirror.hasEarlier, isTrue);
      var taps = 0;
      while (ai.mirror.hasEarlier && taps < 30) {
        await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai.loadEarlier')));
        await tester.pumpAndSettle();
        taps++;
      }
      expect(ai.mirror.from, 0);
      expect(taps, greaterThan(2), reason: 'a page is bounded by the computer\'s window, not by 60 items');
      expect(ai.earlierCalls, taps);
      await tester.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 30000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.loadEarlier')), findsNothing);
      expect(
        find.descendant(of: find.byKey(const Key('ai.timeline')), matching: find.text('go')),
        findsOneWidget,
      ); // the very first item
    });

    testWidgets('the link back after a loss goes on from the old numbers and the page follows', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      say(ai.desktop, 'một');
      await open(tester);
      await tester.enterText(find.byKey(const Key('ai.composer')), 'bản nháp');
      ai.lose();
      await tester.pump();
      expect(find.text('Đang kết nối lại… nội dung có thể chưa mới nhất.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('ai.composer'))).enabled, isFalse);
      say(ai.desktop, ' hai'); // while the phone was away
      ai.sync(); // the new snapshot: its numbers are not 1
      await tester.pumpAndSettle();
      expect(find.text('Đang kết nối lại… nội dung có thể chưa mới nhất.'), findsNothing);
      expect(find.textContaining('một hai'), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(const Key('ai.composer')));
      expect((field.enabled, field.controller!.text), (true, 'bản nháp'));
      say(ai.desktop, ' ba');
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.textContaining('một hai ba'), findsOneWidget);
    });
  });

  group('smooth on a phone', () {
    testWidgets('a running session animates nothing: only the clock and the data move', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      tool(ai.desktop, 'c1', {'title': 'npm test', 'kind': 'execute', 'status': 'in_progress'});
      await open(tester); // settles: nothing loops
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 3)); // the clock beats; that is a timer, not an animation
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('changes that come within one frame rebuild the conversation once', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      say(ai.desktop, 'bắt đầu');
      await open(tester);
      final rebuilds = trackRebuilds();
      for (var i = 0; i < 5; i++) {
        say(ai.desktop, ' từ$i');
        ai.sync();
      }
      await tester.pump();
      expect(rebuilds[AiTimeline], 1);
      expect(find.textContaining('từ4'), findsOneWidget);
    });

    testWidgets('a keyboard that opens leaves the last message in view', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      for (var i = 0; i < 80; i++) {
        tool(ai.desktop, 'c$i', {
          'title': 'Read f$i.ts',
          'kind': 'read',
          'status': 'completed',
          'locations': [
            {'path': '/p/f$i.ts'},
          ],
        });
      }
      await open(tester);
      final last = find.text('Đọc f79.ts');
      expect(last, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 900); // a 300-point keyboard
      await tester.pumpAndSettle();
      expect(last, findsOneWidget);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(timelineRect(tester).bottom));
      expect(timelinePosition(tester).extentAfter, lessThan(1));
    });

    testWidgets('a tool card the user opened stays open when the computer updates it', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [TextBlock('go')], DateTime.now());
      tool(ai.desktop, 'c1', {
        'title': 'ls -la',
        'kind': 'execute',
        'status': 'in_progress',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'total 8'},
          },
        ],
      });
      await open(tester);
      expect(find.textContaining('total 8'), findsNothing);
      await tester.tap(find.text('Chạy ls -la'));
      await tester.pumpAndSettle();
      expect(find.textContaining('total 8'), findsOneWidget);
      ai.desktop.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c1',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'total 8\nfile.txt'},
            },
          ],
        }),
        DateTime.now(),
      );
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.textContaining('file.txt'), findsOneWidget); // still open, with the new output
    });

    testWidgets(
      'a megabyte in one line does not stop the page: tool output, diff, input and text are capped',
      (tester) async {
        final ai = await open(tester);
        final big = 'x' * 1000000;
        feed(
          ai,
          head: {'phase': 'ready', 'agent': 'claude', 'name': 'Claude'},
          items: [
            textRecord(0, 'user', big),
            textRecord(1, 'agent', big),
            toolRecord(
              2,
              extra: {
                'out': {'head': big, 'tail': big, 'lines': 2, 'cut': true},
              },
            ),
            toolRecord(
              3,
              kind: 'edit',
              title: 'Edit a.ts',
              extra: {
                'diffs': [
                  {'path': '/p/a.ts', 'old': big, 'new': '${big}y', 'plus': 1, 'minus': 1},
                ],
              },
            ),
            toolRecord(4, kind: 'other', title: 'mcp__s__t', extra: {'input': big}),
          ],
        );
        await tester.pumpAndSettle();
        for (final title in ['Chạy npm test', 'Sửa a.ts', 's · t']) {
          await tester.ensureVisible(find.text(title));
          await tester.tap(find.text(title));
          await tester.pumpAndSettle();
        }
        expect(longestText(tester), lessThan(50000));
        expect(find.text('Quá lớn để xem trên điện thoại. Xem trên máy tính.'), findsWidgets);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    testWidgets('a hundred thousand short lines are capped by lines too', (tester) async {
      final ai = await open(tester);
      final lines = List.filled(100000, 'l').join('\n');
      feed(
        ai,
        head: {'phase': 'ready', 'agent': 'claude', 'name': 'Claude'},
        items: [
          toolRecord(
            0,
            extra: {
              'out': {'head': lines, 'lines': 100000},
            },
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chạy npm test'));
      await tester.pumpAndSettle();
      final most = mostLines(tester);
      expect(most, inInclusiveRange(2, 1500));
      expect(find.text('Quá lớn để xem trên điện thoại. Xem trên máy tính.'), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
