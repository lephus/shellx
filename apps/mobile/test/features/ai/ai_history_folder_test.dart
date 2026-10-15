import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/pages/ai_session_page.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

/// The agent's `initialize`: it offers `session/list` (the header's `hist`).
final _lists = InitializeResult.fromJson({
  'protocolVersion': 1,
  'agentCapabilities': {
    'sessionCapabilities': {'list': <String, Object?>{}},
  },
});

/// What the computer sends for a tab without a folder (the hub's "cannot run" snapshot).
const _noFolder = <String, Object?>{
  'g': 0,
  'from': 0,
  'n': 0,
  'reset': true,
  'head': {'phase': 'stopped', 'agent': 'claude', 'name': 'Claude', 'unavailable': 'no_folder'},
  'items': <Object?>[],
};

const _shop = AiFolderChoice(key: 'ws:a', name: 'shop', path: '/p');
const _api = AiFolderChoice(key: 'path:/w/api', name: 'api', path: '/w/api');

/// V2-2b B17, B18 on the AI session page.
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

  /// The computer has V2-2b (`ai: 2`) and its listing offers [features] and [folders].
  void offers(Set<String> features, {List<AiFolderChoice> folders = const [_shop]}) {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(features: features, folders: folders));
  }

  /// The page of [sid], its snapshot taken; panels that wait 400 ms have settled.
  Future<FakeAiSession> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ai = machine.ai.session(sid);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return ai;
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.menu.history')));
    await tester.pumpAndSettle();
  }

  group('Lịch sử phiên (B17)', () {
    testWidgets("the agent's earlier sessions; one opens in place of this page", (tester) async {
      offers({AiFeature.history});
      machine.ai.historyPages[null] = const AiHistoryPage(
        sessions: [
          AiPastSession(acp: 'old-1', title: 'Nút đăng xuất', at: '2026-10-13T09:30:00'),
          AiPastSession(acp: 'sess-1', title: 'Đang mở ở đây'),
        ],
        current: 'sess-1',
      );
      machine.ai.session(sid).desktop
        ..setAgent(_lists)
        ..setSession('sess-1');
      await open(tester);
      await openHistory(tester);
      expect(find.byKey(const ValueKey('ai.history.old-1')), findsOneWidget);
      expect(find.text('Nút đăng xuất'), findsOneWidget);
      expect(find.text('2026-10-13 09:30'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.history.sess-1')), findsNothing, reason: 'the session open here');
      await tester.tap(find.byKey(const ValueKey('ai.history.old-1')));
      // Not pumpAndSettle: the new page shows a spinner until its snapshot arrives.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      machine.ai.session(machine.ai.resumedSid).sync();
      await tester.pumpAndSettle();
      expect(machine.ai.resumed, [('claude', 'ws:a', 'old-1')]);
      expect(tester.widget<AiSessionPage>(find.byType(AiSessionPage)).sid, machine.ai.resumedSid);
      expect(machine.ai.session(sid).detached, isTrue, reason: 'the page it replaced let its session go');
    });

    testWidgets('a page at a time: "Tải thêm" asks for the next one', (tester) async {
      offers({AiFeature.history});
      machine.ai.historyPages
        ..[null] = const AiHistoryPage(
          sessions: [AiPastSession(acp: 'a', title: 'A')],
          next: 'c2',
        )
        ..['c2'] = const AiHistoryPage(
          sessions: [AiPastSession(acp: 'b', title: 'B')],
        );
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      await openHistory(tester);
      expect(find.byKey(const ValueKey('ai.history.b')), findsNothing);
      await tester.tap(find.byKey(const Key('ai.history.more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai.history.a')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.history.b')), findsOneWidget);
      expect(find.byKey(const Key('ai.history.more')), findsNothing);
      expect(machine.ai.historyAsks, [(sid, null), (sid, 'c2')]);
    });

    testWidgets('asked while the agent does not run, the history comes once it runs (not_ready)', (tester) async {
      offers({AiFeature.history});
      machine.ai
        ..historyFailWith = 'not_ready'
        ..historyPages[null] = const AiHistoryPage(
          sessions: [AiPastSession(acp: 'old-1', title: 'Cũ')],
        );
      final ai = machine.ai.session(sid);
      ai.desktop
        ..setAgent(_lists)
        ..setPhase(AgentPhase.stopped);
      await open(tester);
      await openHistory(tester);
      expect(find.byKey(const Key('ai.history.notReady')), findsOneWidget);
      expect(find.text('Lịch sử hiện khi agent đang chạy.'), findsOneWidget);
      machine.ai.historyFailWith = null;
      ai.desktop.setPhase(AgentPhase.ready);
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai.history.old-1')), findsOneWidget);
      expect(machine.ai.historyAsks, hasLength(2));
    });

    testWidgets('no entry without the feature, or for an agent without session/list', (tester) async {
      machine.ai
        ..protocolValue = 1
        ..emitListing(const AiListing(features: {AiFeature.history}));
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      expect(find.byKey(const Key('ai.menu.history')), findsNothing);
      expect(find.byKey(const Key('ai.menu')), findsNothing, reason: 'nothing else in it');
    });

    testWidgets('a resume that may have gone says so and asks nothing again', (tester) async {
      offers({AiFeature.history});
      machine.ai.historyPages[null] = const AiHistoryPage(sessions: [AiPastSession(acp: 'old-1')]);
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      await openHistory(tester);
      machine.ai.connectFailure = MachineConnectionFailure.agentOffline;
      await tester.tap(find.byKey(const ValueKey('ai.history.old-1')));
      await tester.pumpAndSettle();
      expect(machine.ai.resumed, hasLength(1));
      expect(
        popups.errors.single,
        AiWords.failure(S.of(tester.element(find.byType(AiSessionPage))), AiWords.openUnknown),
      );
      expect(tester.widget<AiSessionPage>(find.byType(AiSessionPage)).sid, sid, reason: 'this page stays');
    });

    testWidgets('a folder the computer does not list: nothing is sent, never a path, and it is said', (tester) async {
      offers({AiFeature.history}, folders: const [_api]); // the session runs in /p
      machine.ai.historyPages[null] = const AiHistoryPage(
        sessions: [AiPastSession(acp: 'old-1', title: 'Cũ')],
      );
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      await openHistory(tester);
      await tester.tap(find.byKey(const ValueKey('ai.history.old-1')));
      await tester.pumpAndSettle();
      expect(machine.ai.resumed, isEmpty);
      expect(popups.errors, ['Máy tính không nhận yêu cầu này.']);
      expect(tester.widget<AiSessionPage>(find.byType(AiSessionPage)).sid, sid, reason: 'this page stays');
    });

    testWidgets('no earlier session in the folder: it says so', (tester) async {
      offers({AiFeature.history});
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      await openHistory(tester);
      expect(find.byKey(const Key('ai.history.empty')), findsOneWidget);
      expect(find.text('Chưa có phiên nào trước đây trong thư mục này.'), findsOneWidget);
    });

    testWidgets('a history that fails says why and is not asked again by itself', (tester) async {
      offers({AiFeature.history});
      machine.ai
        ..historyFailWith = 'refused'
        ..historyPages[null] = const AiHistoryPage(
          sessions: [AiPastSession(acp: 'old-1', title: 'Cũ')],
        );
      machine.ai.session(sid).desktop.setAgent(_lists);
      await open(tester);
      await openHistory(tester);
      expect(find.byKey(const Key('ai.history.error')), findsOneWidget);
      expect(find.text('Máy tính không nhận yêu cầu này.'), findsOneWidget);
      expect(find.byKey(const Key('ai.history.notReady')), findsNothing);
      machine.ai.historyFailWith = null;
      machine.ai.session(sid).desktop.setPhase(AgentPhase.running);
      machine.ai.session(sid).sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai.history.old-1')), findsNothing);
      expect(machine.ai.historyAsks, [(sid, null)], reason: 'only not_ready is asked again, once the agent runs');
    });

    testWidgets('a session closed on the computer has no history entry', (tester) async {
      offers({AiFeature.history});
      machine.ai.session(sid).desktop.setAgent(_lists);
      final ai = await open(tester);
      expect(find.byKey(const Key('ai.menu')), findsOneWidget);
      ai.close('gone');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.menu')), findsNothing);
    });
  });

  group('Dùng thư mục này (B18)', () {
    testWidgets("a tab without a folder: the computer's folders and the button", (tester) async {
      offers({AiFeature.folder}, folders: const [_shop, _api]);
      final ai = await open(tester);
      ai.mirror.apply(Map.of(_noFolder), snapshot: true);
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.folders')), findsOneWidget);
      expect(find.byKey(const Key('ai.unavailable')), findsNothing);
      expect(find.byKey(const Key('ai.composer')), findsNothing);
      expect(find.text('/w/api'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai.folder.path:/w/api')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.useFolder')));
      await tester.pumpAndSettle();
      expect(machine.ai.foldersChosen, [(sid, 'path:/w/api')]);
    });

    testWidgets('the listing may come after the session: the folders show when it does', (tester) async {
      // The computer has AI (its list said so), V2-2b; its listing has not come yet.
      machine.ai
        ..protocolValue = 2
        ..supportedValue = true;
      final ai = await open(tester);
      ai.mirror.apply(Map.of(_noFolder), snapshot: true);
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.unavailable')), findsOneWidget);
      machine.ai.emitListing(const AiListing(features: {AiFeature.folder}, folders: [_shop]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.folders')), findsOneWidget);
    });

    testWidgets('a computer that refuses: said, and the choice stays', (tester) async {
      offers({AiFeature.folder});
      final ai = await open(tester);
      ai.mirror.apply(Map.of(_noFolder), snapshot: true);
      ai.sync();
      await tester.pumpAndSettle();
      machine.ai.failWith = 'refused';
      await tester.tap(find.byKey(const Key('ai.useFolder')));
      await tester.pumpAndSettle();
      expect(popups.errors, ['Máy tính không nhận yêu cầu này.']);
      expect(find.byKey(const Key('ai.folders')), findsOneWidget);
    });

    testWidgets('an older computer: the V2-2a text, no folders', (tester) async {
      machine.ai
        ..protocolValue = 1
        ..emitListing(const AiListing(features: {AiFeature.folder}, folders: [_shop]));
      final ai = await open(tester);
      ai.mirror.apply(Map.of(_noFolder), snapshot: true);
      ai.sync();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.unavailable')), findsOneWidget);
      expect(find.byKey(const Key('ai.folders')), findsNothing);
    });
  });

  test('words: a history time, and not_ready', () async {
    final vi = await S.load(const Locale('vi'));
    expect(AiWords.historyWhen('2026-10-13T09:30:00'), '2026-10-13 09:30');
    expect(AiWords.historyWhen('yesterday'), 'yesterday');
    expect(AiWords.historyWhen(null), '');
    expect(AiWords.failure(vi, 'not_ready'), 'Lịch sử hiện khi agent đang chạy.');
    expect(vi.aiHistory, 'Lịch sử phiên');
    expect(vi.aiUseFolder, 'Dùng thư mục này');
    final en = await S.load(const Locale('en'));
    expect(en.aiHistory, 'Session history');
    expect(en.aiUseFolder, 'Use this folder');
  });
}
