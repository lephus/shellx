import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

const _listing = AiListing(
  sessions: [
    AiSessionInfo(
      sid: 'e.-1',
      agentId: 'claude',
      agentName: 'Claude',
      title: 'Nút đăng xuất',
      state: AiRemoteState.needsInput,
      waiting: 'Sửa src/main.ts',
    ),
    AiSessionInfo(sid: 'e.-2', agentId: 'claude', agentName: 'Claude', title: '', state: AiRemoteState.running),
  ],
  agents: [
    AiAgentChoice(id: 'claude', name: 'Claude'),
    AiAgentChoice(id: 'codex', name: 'Codex', ready: false),
  ],
  folders: [AiFolderChoice(key: 'ws:a', name: 'shop-web', path: '/Users/me/shop-web')],
  defaultAgent: 'claude',
);

/// V2-2 §5.1: AI sessions in the machine's session list, the chrome button, "Phiên AI mới".
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late List<Object?> pushed;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    pushed = [];
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings));
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
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [
          AutoRoute(page: TerminalRoute.page),
          stubRoute(AiSessionRoute.name, pushed: pushed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  testWidgets('the picker lists AI sessions first, with what they wait for; a tap opens one', (tester) async {
    machine.ai
      ..supportedValue = true
      ..listingValue = _listing;
    await open(tester);
    expect(find.text('PHIÊN AI'), findsOneWidget);
    expect(find.text('Nút đăng xuất'), findsOneWidget);
    expect(find.text('Claude · Cần bạn trả lời'), findsOneWidget);
    expect(find.text('Sửa src/main.ts'), findsOneWidget);
    expect(find.text('Phiên AI mới'), findsNWidgets(2)); // the untitled session and the action
    await tester.tap(find.byKey(const ValueKey('picker-ai-e.-1')));
    await tester.pumpAndSettle();
    expect((pushed.single! as AiSessionRouteArgs).sid, 'e.-1');
  });

  testWidgets('a computer without AI for phones: the update hint; the chrome has no AI button', (tester) async {
    machine.ai.supportedValue = false;
    machine.sessions = [const SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1, attached: false)];
    await open(tester);
    expect(find.text('Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại.'), findsOneWidget);
    expect(find.byKey(const ValueKey('picker-ai-hint')), findsOneWidget);
    expect(find.text('PHIÊN AI'), findsNothing, reason: 'the hint stands alone: there is no group for it to head');
    expect(find.byKey(const ValueKey('terminal-ai')), findsNothing);
  });

  testWidgets('Phiên AI mới: a ready agent and a folder the computer offers, then the new session', (tester) async {
    machine.ai
      ..supportedValue = true
      ..listingValue = _listing
      ..openedSid = 'e.-7';
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('picker-ai-new')));
    await tester.pumpAndSettle();
    expect(find.text('cài trên máy tính'), findsOneWidget); // Codex is not ready
    await tester.tap(find.byKey(const ValueKey('ai-new-start')));
    await tester.pumpAndSettle();
    expect(machine.ai.opened, [('claude', 'ws:a')]);
    expect((pushed.single! as AiSessionRouteArgs).sid, 'e.-7');
  });

  testWidgets('the chrome AI button counts the sessions that wait and opens the list', (tester) async {
    machine.ai
      ..supportedValue = true
      ..listingValue = _listing;
    machine.sessions = [const SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1, attached: false)];
    await open(tester);
    // The picker opened on entry: dismiss it, then use the button.
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    machine.ai.emitListing(_listing);
    await tester.pump();
    final button = find.byKey(const ValueKey('terminal-ai'));
    expect(button, findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('1')), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('PHIÊN AI'), findsOneWidget);
  });
}
