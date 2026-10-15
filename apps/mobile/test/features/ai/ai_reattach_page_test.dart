import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const _sid = 'e.-1';

AiSessionInfo _info(String sid, {String? acp = 'sess-1', String title = 'Nút đăng xuất'}) => AiSessionInfo(
  sid: sid,
  agentId: 'claude',
  agentName: 'Claude',
  title: title,
  state: AiRemoteState.idle,
  cwd: '/p',
  acpSessionId: acp,
);

/// V2-2b B22 on the session page: "Đã nối lại sau khi ShellX khởi động lại." once the session is followed
/// to its new sid; "Mở danh sách phiên" on a session closed for good; the header's V2-2b parts stay off.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, AiDrafts(), registry),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: _sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    machine.ai.session(_sid).sync();
    await tester.pumpAndSettle();
  }

  testWidgets('without V2-2b features the header has no menu and its line is plain text', (tester) async {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(sessions: [_info(_sid)]));
    await open(tester);
    expect(find.byKey(const Key('ai.menu')), findsNothing);
    expect(find.byKey(const Key('ai.status.tap')), findsNothing);
  });

  testWidgets('a listing that arrives after the page opened rebuilds it: "Mở danh sách phiên" shows once the '
      'computer\'s sessions are known', (tester) async {
    machine.ai.protocolValue = 2;
    await open(tester);
    machine.ai.session(_sid).close('gone');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.closed')), findsOneWidget);
    expect(find.byKey(const Key('ai.openList')), findsNothing, reason: 'no listing yet');
    machine.ai.emitListing(AiListing(sessions: [_info('k.-3', acp: 'sess-7')]));
    await tester.pump();
    expect(find.byKey(const Key('ai.openList')), findsOneWidget);
  });

  testWidgets('followed to its new sid after a restart: "Đã nối lại…" until the user sends', (tester) async {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(sessions: [_info(_sid)]));
    await open(tester);
    machine.ai.session(_sid).close('desktop_closed');
    await tester.pump();
    expect(find.byKey(const Key('ai.closed')), findsOneWidget);
    machine.ai.emitListing(AiListing(sessions: [_info('k.-3')]));
    machine.ai.session('k.-3').sync();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.closed')), findsNothing);
    expect(find.text('Đã nối lại sau khi ShellX khởi động lại.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('ai.composer')), 'tiếp nhé');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts, [('k.-3', 'tiếp nhé')]);
    expect(find.byKey(const Key('ai.reattached')), findsNothing);
  });

  testWidgets('closed for good: "Mở danh sách phiên" offers the computer\'s AI sessions only, and the one '
      'picked takes this page\'s place', (tester) async {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(sessions: [_info(_sid)]));
    await open(tester);
    machine.ai.session(_sid).close('gone');
    machine.ai.emitListing(
      AiListing(
        sessions: [_info('k.-3', acp: 'sess-7', title: 'Sửa giỏ hàng')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phiên AI này đã đóng trên máy tính.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.openList')));
    await tester.pumpAndSettle();
    expect(find.text('Sửa giỏ hàng'), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-desktop-hint')), findsNothing, reason: 'AI sessions only');
    await tester.tap(find.byKey(const ValueKey('picker-ai-k.-3')));
    // Not pumpAndSettle: the new page shows a spinner until its snapshot arrives.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(machine.ai.sessions.containsKey('k.-3'), isTrue, reason: 'the page of k.-3 attached it');
    machine.ai.session('k.-3').sync();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.openList')), findsNothing);
    await tester.tap(find.byKey(const Key('ai.back')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: 'it took the closed page\'s place');
  });
}
