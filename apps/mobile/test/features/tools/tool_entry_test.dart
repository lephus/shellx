import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
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

const _board = ToolInfo(id: 'k3f9za7q1m', name: 'Bảng việc', ws: 'shop-web', port: 4000, path: '/', group: 'ws:a');
const _api = ToolInfo(id: 'api0000001', name: 'API', ws: 'shop-web', port: 8000, path: '/docs', group: 'ws:a');

/// V2-4 E15, criterion 1: the Tool group of the machine's session picker.
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
          stubRoute(ToolRoute.name, pushed: pushed),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  testWidgets('the Tool group lists the tools on for phone; a tap opens one', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing(tools: [_board, _api]);
    await open(tester);
    expect(find.text('TOOL'), findsOneWidget);
    expect(find.text('Bảng việc'), findsOneWidget);
    expect(find.text('shop-web · localhost:4000'), findsOneWidget);
    expect(find.text('shop-web · localhost:8000'), findsOneWidget);
    expect(machine.tools.watching, isTrue, reason: 'the list follows the computer while the picker is open');
    await tester.tap(find.byKey(const ValueKey('picker-tool-k3f9za7q1m')));
    await tester.pumpAndSettle();
    expect((pushed.single! as ToolRouteArgs).tool, _board);
    expect(machine.tools.watching, isFalse);
  });

  testWidgets('a tool turned on while the picker is open shows at once (criterion 1)', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing();
    await open(tester);
    expect(
      find.text('Chưa có tool nào bật cho điện thoại. Trên máy tính: thanh của tool › 📱 Điện thoại.'),
      findsOneWidget,
    );
    machine.tools.emitListing(const ToolListing(tools: [_board]));
    await tester.pump();
    expect(find.text('Bảng việc'), findsOneWidget);
  });

  testWidgets('no list from the computer yet: open ShellX on it', (tester) async {
    machine.tools
      ..supportedValue = true
      ..listingValue = const ToolListing(available: false);
    await open(tester);
    expect(find.text('Mở ShellX trên máy tính để dùng tool.'), findsOneWidget);
  });

  testWidgets('an older computer: no Tool group, and + opens a session at once', (tester) async {
    machine.tools.supportedValue = false;
    await open(tester);
    expect(find.text('TOOL'), findsNothing);
    expect(machine.opened, hasLength(1));
  });

  group('opening a tool over the machine page', () {
    testWidgets('dismissing the picker lets the list go, and opens nothing', (tester) async {
      machine.tools
        ..supportedValue = true
        ..listingValue = const ToolListing(tools: [_board]);
      await open(tester);
      expect(machine.tools.watching, isTrue);
      await tester.tapAt(const Offset(20, 40)); // beside the sheet
      await tester.pumpAndSettle();
      expect(find.text('TOOL'), findsNothing);
      expect(machine.tools.watching, isFalse);
      expect(pushed, isEmpty);
    });

    testWidgets('the tool is opened for this machine; the terminal under it is not looked at meanwhile', (
      tester,
    ) async {
      machine.tools
        ..supportedValue = true
        ..listingValue = const ToolListing(tools: [_board]);
      machine.sessions = [const SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1, attached: false)];
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-session-7'))); // a tab
      await tester.pumpAndSettle();
      final workspace = registry.forMachine(agentA);
      machine.handle(7).emit(const TabOutput('seen'));
      await tester.pump();
      expect(workspace.unseenCount, 0, reason: 'the terminal is on screen');

      // + again: the Tool group is all there is to pick from. The list of the first visit is old by now:
      // the picker waits for the computer's answer.
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pump();
      machine.tools.emitListing(const ToolListing(tools: [_board]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-tool-k3f9za7q1m')));
      await tester.pumpAndSettle();
      final args = pushed.single! as ToolRouteArgs;
      expect(args.agentId, agentA);
      expect(args.tool, _board);
      machine.handle(7).emit(const TabOutput('while the tool is on top'));
      await tester.pump();
      expect(workspace.unseenCount, 1);

      await tester.tap(find.byType(BackButton)); // the stand-in page's
      await tester.pumpAndSettle();
      expect(workspace.unseenCount, 0, reason: 'looked at again');
      expect(machine.tools.watching, isFalse, reason: 'the picker is gone; the tool page holds what it needs itself');
    });
  });
}
