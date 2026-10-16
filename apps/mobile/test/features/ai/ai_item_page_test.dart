import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

final _output = [for (var i = 0; i < 3000; i++) 'dòng $i'].join('\n');

AiSessionInfo _info(String sid) => AiSessionInfo(
  sid: sid,
  agentId: 'claude',
  agentName: 'Claude',
  title: 'Nút đăng xuất',
  state: AiRemoteState.idle,
  cwd: '/p',
  acpSessionId: 'sess-1',
);

/// A question whose form is over the 16 KiB a mirror carries: its card on the phone has no form.
ElicitationRequest _bigForm(String message, List<String> options) => ElicitationRequest.fromJson({
  'mode': 'form',
  'message': message,
  'requestedSchema': {
    'type': 'object',
    'properties': {
      'pick': {'type': 'string', 'title': 'Pick', 'description': 'x' * 20000, 'enum': options},
    },
    'required': ['pick'],
  },
});

/// A question that carries [id] as given: what a restarted ShellX does, since its ask ids start again.
void _askWithId(AiSessionState s, int id, ElicitationRequest request) {
  final item = AskItem(s.timeline.turn, id, request);
  s.timeline.add(item);
  s.asks.add(PendingAsk(id, item));
  s.touch();
}

void _say(AiSessionState s, String text, {String kind = 'agent_message_chunk'}) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': kind,
    'content': {'type': 'text', 'text': text},
  }),
  DateTime.now(),
);

/// V2-2b B16: "Xem đủ" on the phone.
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
    final drafts = AiDrafts();
    final registry = WorkspaceRegistry(session.backend);
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, drafts, registry),
      );
  });

  tearDown(() async => getIt.reset());

  /// The page of [sid] on a computer that speaks ai 2 and offers [features], listing [sessions]; [desktop]
  /// fills the session as the computer holds it.
  Future<FakeAiSession> open(
    WidgetTester tester, {
    Set<String> features = const {AiFeature.item},
    List<AiSessionInfo> sessions = const [],
    void Function(AiSessionState desktop)? desktop,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(features: features, sessions: sessions));
    final ai = machine.ai.session(sid);
    desktop?.call(ai.desktop);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [
          AutoRoute(page: AiSessionRoute.page),
          AutoRoute(page: AiItemRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400)); // panels that appeared have settled
    return ai;
  }

  void longOutput(AiSessionState s) => s.applyUpdate(
    SessionUpdate.fromJson({
      'sessionUpdate': 'tool_call',
      'toolCallId': 'c1',
      'title': 'npm test',
      'kind': 'execute',
      'status': 'completed',
      'content': [
        {
          'type': 'content',
          'content': {'type': 'text', 'text': _output},
        },
      ],
    }),
    DateTime.now(),
  );

  /// Opens the card of the call (its header is the whole closed card).
  Future<void> openCard(WidgetTester tester) async {
    await tester.tap(find.byType(AiToolCard));
    await tester.pumpAndSettle();
  }

  /// Taps "Xem đủ" of item [index]; the page is pushed (its spinner turns: no settling).
  Future<void> viewAll(WidgetTester tester, int index) async {
    await tester.ensureVisible(find.byKey(Key('ai.viewAll.$index')));
    await tester.tap(find.byKey(Key('ai.viewAll.$index')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a cut output: Xem đủ loads the whole call slice by slice, then shows its lines, built only '
      'near the screen', (tester) async {
    await open(tester, desktop: longOutput);
    final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
    machine.ai
      ..fullParts = 3
      ..partGates = gates
      ..fullItems[0] = AiFullView(kind: 'tool', title: 'npm test', output: _output);
    await openCard(tester);
    await viewAll(tester, 0);
    expect(find.byKey(const Key('ai.item.title')), findsOneWidget);
    expect(find.byKey(const Key('ai.item.loading')), findsNothing, reason: 'no slice yet');
    gates[0].complete();
    await tester.pump();
    expect(find.text('Đang tải 1/3'), findsOneWidget);
    gates[1].complete();
    await tester.pump();
    expect(find.text('Đang tải 2/3'), findsOneWidget);
    gates[2].complete();
    await tester.pumpAndSettle();
    expect(machine.ai.fullAsked, [(sid, 0)]);
    expect(find.text('dòng 0'), findsOneWidget);
    expect(find.text('dòng 2999'), findsNothing, reason: 'built only near the screen');
    await tester.drag(find.byKey(const Key('ai.item.lines')), const Offset(0, -200000));
    await tester.pumpAndSettle();
    expect(find.text('dòng 2999'), findsOneWidget);
  });

  testWidgets('a diff in full, in the conversation\'s diff rows', (tester) async {
    await open(tester, desktop: longOutput);
    machine.ai.fullItems[0] = const AiFullView(
      kind: 'tool',
      diffs: [MirrorDiff(path: 'src/a.ts', oldText: 'one\ntwo\n', newText: 'one\nthree\n')],
      bigDiffs: ['big.bin'],
    );
    await openCard(tester);
    await viewAll(tester, 0);
    await tester.pumpAndSettle();
    expect(find.text('src/a.ts'), findsOneWidget);
    expect(find.text('- two'), findsOneWidget);
    expect(find.text('+ three'), findsOneWidget);
    expect(find.byType(AiDiffLineRow), findsNWidgets(3));
    expect(find.text('big.bin'), findsOneWidget);
    expect(find.text('Quá lớn để xem trên điện thoại. Xem trên máy tính.'), findsOneWidget);
  });

  testWidgets('too big for the phone too: read on the computer', (tester) async {
    await open(tester, desktop: longOutput);
    await openCard(tester);
    machine.ai.failWith = 'too_big';
    await viewAll(tester, 0);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.item.error')), findsOneWidget);
    expect(find.text('Quá lớn để xem trên điện thoại. Xem trên máy tính.'), findsOneWidget);
  });

  testWidgets('leaving the page ends the loading: no slice is asked after it', (tester) async {
    await open(tester, desktop: longOutput);
    final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
    machine.ai
      ..fullParts = 3
      ..partGates = gates
      ..fullItems[0] = AiFullView(kind: 'tool', output: _output);
    await openCard(tester);
    await viewAll(tester, 0);
    gates[0].complete();
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.item.back')));
    await tester.pumpAndSettle();
    gates[1].complete();
    gates[2].complete();
    await tester.pumpAndSettle();
    expect(machine.ai.partsServed, 2, reason: 'the second came back to a page that was gone; no third');
    expect(popups.errors, isEmpty);
  });

  testWidgets('without the feature there is no Xem đủ', (tester) async {
    await open(tester, features: const {}, desktop: longOutput);
    await openCard(tester);
    expect(find.byKey(const Key('ai.viewAll.0')), findsNothing);
  });

  testWidgets('a question too big for the phone: its whole form is loaded and answered with one tap', (
    tester,
  ) async {
    final request = ElicitationRequest.fromJson({
      'mode': 'form',
      'message': 'Which one?',
      'requestedSchema': {
        'type': 'object',
        'properties': {
          'pick': {
            'type': 'string',
            'title': 'Pick',
            'description': 'x' * 20000, // the form is over the 16 KiB a mirror carries
            'enum': ['a', 'b'],
          },
        },
        'required': ['pick'],
      },
    });
    late int askId;
    await open(tester, desktop: (s) => askId = s.addAsk(request)!.id);
    machine.ai.fullItems[0] = AiFullView(kind: 'ask', request: request);
    expect(find.text('Trả lời câu hỏi này trên máy tính.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.ask.viewAll')));
    await tester.pumpAndSettle();
    expect(machine.ai.fullAsked, [(sid, 0)]);
    await tester.tap(find.text('a').last);
    await tester.pump(const Duration(milliseconds: 400)); // the panel that appeared has settled
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.ask.submit')));
    await tester.pumpAndSettle();
    expect(machine.ai.askAnswers.single.$2, askId);
    expect((machine.ai.askAnswers.single.$3 as ElicitAccept).content, {'pick': 'a'});
  });

  /// The page follows its session to [next] (B22): ShellX restarted on the computer, the session is back there
  /// under another sid, and [asks] is the question it asks (the ids start again, so it may carry an old id).
  Future<FakeAiSession> follow(WidgetTester tester, String next, void Function(AiSessionState desktop) asks) async {
    machine.ai.session(sid).close('desktop_closed');
    await tester.pump();
    final ai = machine.ai.session(next);
    asks(ai.desktop);
    machine.ai.emitListing(AiListing(features: const {AiFeature.item}, sessions: [_info(next)]));
    ai.sync();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400)); // the panel that appeared has settled
    return ai;
  }

  testWidgets('a form loaded in full is its question\'s alone: followed to a new sid, a new question of the same '
      'id has no form, and is answered there only with its own', (tester) async {
    final old = _bigForm('Which one?', ['a', 'b']);
    final fresh = _bigForm('Another?', ['x', 'y']);
    late int askId;
    await open(tester, sessions: [_info(sid)], desktop: (s) => askId = s.addAsk(old)!.id);
    machine.ai.fullItems[0] = AiFullView(kind: 'ask', request: old);
    await tester.tap(find.byKey(const Key('ai.ask.viewAll')));
    await tester.pumpAndSettle();
    expect(find.text('Which one?'), findsOneWidget, reason: 'the form of the old session is loaded');
    await follow(tester, 'k.-3', (s) => _askWithId(s, askId, fresh));
    expect(find.text('Đã nối lại sau khi ShellX khởi động lại.'), findsOneWidget);
    expect(find.text('Which one?'), findsNothing, reason: 'not the old question\'s form');
    expect(find.text('Trả lời câu hỏi này trên máy tính.'), findsOneWidget);
    expect(find.byKey(const Key('ai.ask.submit')), findsNothing);
    expect(find.byKey(const Key('ai.ask.viewAll')), findsOneWidget, reason: 'loaded in full like any other');
    machine.ai.fullItems[0] = AiFullView(kind: 'ask', request: fresh);
    await tester.tap(find.byKey(const Key('ai.ask.viewAll')));
    await tester.pumpAndSettle();
    expect(machine.ai.fullAsked, [(sid, 0), ('k.-3', 0)]);
    await tester.tap(find.text('y').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.ask.submit')));
    await tester.pumpAndSettle();
    expect(machine.ai.askAnswers.single.$1, 'k.-3');
    expect(machine.ai.askAnswers.single.$2, askId);
    expect((machine.ai.askAnswers.single.$3 as ElicitAccept).content, {'pick': 'y'});
  });

  testWidgets('a form still loading when the page follows the session to a new sid is dropped when it comes, '
      'not kept for a question of that id there', (tester) async {
    final old = _bigForm('Which one?', ['a', 'b']);
    late int askId;
    await open(tester, sessions: [_info(sid)], desktop: (s) => askId = s.addAsk(old)!.id);
    final gate = Completer<void>();
    machine.ai
      ..partGates = [gate]
      ..fullItems[0] = AiFullView(kind: 'ask', request: old);
    await tester.tap(find.byKey(const Key('ai.ask.viewAll')));
    await tester.pump();
    expect(machine.ai.fullAsked, [(sid, 0)]);
    await follow(tester, 'k.-3', (s) => _askWithId(s, askId, _bigForm('Another?', ['x', 'y'])));
    gate.complete(); // the form of the old session comes at last
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Which one?'), findsNothing, reason: 'not the old session\'s form');
    expect(find.text('Trả lời câu hỏi này trên máy tính.'), findsOneWidget);
    expect(find.byKey(const Key('ai.ask.viewAll')), findsOneWidget, reason: 'the new question can load its own');
    expect(popups.errors, isEmpty);
  });

  testWidgets('a line cut at 4 000 characters never splits a surrogate pair: it ends with … and lays out', (
    tester,
  ) async {
    await open(tester, desktop: longOutput);
    machine.ai.fullItems[0] = AiFullView(kind: 'tool', output: '${'a' * 3999}😀 and more');
    await openCard(tester);
    await viewAll(tester, 0);
    await tester.pumpAndSettle();
    expect(find.text('${'a' * 3999}…'), findsOneWidget);
  });

  testWidgets('a diff line cut at 4 000 characters never splits a surrogate pair either', (tester) async {
    await open(tester, desktop: longOutput);
    machine.ai.fullItems[0] = AiFullView(
      kind: 'tool',
      diffs: [MirrorDiff(path: 'a.txt', oldText: null, newText: '${'a' * 3999}😀 and more')],
    );
    await openCard(tester);
    await viewAll(tester, 0);
    await tester.pumpAndSettle();
    expect(find.text('+ ${'a' * 3999}…'), findsOneWidget);
  });

  testWidgets('an answer the phone cuts at 200 blocks, far under 20 000 characters, has Xem đủ too', (tester) async {
    final ai = await open(tester, desktop: (s) => _say(s, 'Xong rồi.'));
    expect(find.byKey(const Key('ai.viewAll.0')), findsNothing, reason: 'whole: nothing to view');
    _say(ai.desktop, '\n\n${[for (var i = 0; i < 250; i++) 'b$i'].join('\n\n')}');
    ai.sync();
    await tester.pumpAndSettle();
    expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsOneWidget, reason: 'the phone cut it');
    expect(find.byKey(const Key('ai.viewAll.0')), findsOneWidget);
  });

  testWidgets('an unfolded thought the phone cuts at 200 blocks has Xem đủ too', (tester) async {
    await open(
      tester,
      desktop: (s) => _say(s, [for (var i = 0; i < 250; i++) 'c$i'].join('\n\n'), kind: 'agent_thought_chunk'),
    );
    expect(find.byKey(const Key('ai.viewAll.0')), findsNothing, reason: 'folded');
    await tester.tap(find.text('Suy nghĩ'));
    await tester.pumpAndSettle();
    expect(find.text('Phần còn lại của tin này xem trên máy tính.'), findsOneWidget, reason: 'the phone cut it');
    expect(find.byKey(const Key('ai.viewAll.0')), findsOneWidget);
  });
}
