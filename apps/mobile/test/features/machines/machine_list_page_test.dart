import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  const ketoan = '33333333-3333-4333-8333-333333333333';
  const vanphong = '44444444-4444-4444-8444-444444444444';
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late WorkspaceRegistry registry;
  late FakeExternalLinks links;
  late List<Object?> terminals;
  late List<Object?> scans;
  late List<Object?> settingsVisits;
  late List<Object?> updates;
  TerminalExit? terminalExit;

  setUp(() {
    backend = FakeBackend(
      devices: [
        agentDevice(
          vanphong,
          'PC-VANPHONG',
          online: false,
          platform: DevicePlatform.windows,
          lastSeenAt: DateTime(2026, 9, 24, 18, 5),
        ),
        agentDevice(ketoan, 'PC-KETOAN', platform: DevicePlatform.windows),
        agentDevice(agentB, 'MINI-HOME'),
        agentDevice(agentA, 'MacBook Pro của Phú'),
      ],
      pinnedList: [pinned(agentA), pinned(agentB), pinned(vanphong)],
    )..onlineIds.addAll([agentA, agentB, ketoan]);
    backend.addMachine(agentA);
    registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
    links = FakeExternalLinks();
    terminals = [];
    scans = [];
    settingsVisits = [];
    updates = [];
    terminalExit = null;
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(links)
      ..registerFactory<MachineListController>(
        () => MachineListController(backend: backend, registry: registry, now: () => now),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// The terminal stand-in closes with [terminalExit] when its "leave" button is tapped.
  AutoRoute terminalStub() => AutoRoute(
    page: PageInfo(
      TerminalRoute.name,
      builder: (data) {
        terminals.add(data.args);
        return Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('terminal stub')),
            body: TextButton(onPressed: () => context.router.maybePop(terminalExit), child: const Text('leave')),
          ),
        );
      },
    ),
  );

  Future<void> openList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const MachineListRoute(),
        routes: [
          AutoRoute(page: MachineListRoute.page),
          terminalStub(),
          stubRoute(QrScannerRoute.name, pushed: scans),
          stubRoute(SettingsRoute.name, pushed: settingsVisits),
          stubRoute(UpdateRequiredRoute.name, pushed: updates),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('machine-$id'));

  testWidgets('design: online first, then an "Offline" group; dots, badges and last online', (tester) async {
    await openList(tester);
    expect(find.text('Máy của bạn'), findsOneWidget);
    final y = {
      for (final id in [agentA, agentB, ketoan, vanphong]) id: tester.getTopLeft(card(id)).dy,
    };
    expect(y[agentA]! < y[agentB]! && y[agentB]! < y[ketoan]!, isTrue);
    expect(tester.getTopLeft(find.text('OFFLINE')).dy, inExclusiveRange(y[ketoan]!, y[vanphong]!));

    expect(find.descendant(of: card(agentA), matching: find.byKey(const ValueKey('dot-online'))), findsOneWidget);
    expect(find.descendant(of: card(agentA), matching: find.text('Online · macOS')), findsOneWidget);
    expect(find.descendant(of: card(ketoan), matching: find.text('Chưa ghép nối')), findsOneWidget);
    expect(find.descendant(of: card(vanphong), matching: find.byKey(const ValueKey('dot-offline'))), findsOneWidget);
    expect(find.text('Lần cuối online: hôm qua, 18:05'), findsOneWidget);
    expect(find.text('Ghép nối máy mới'), findsOneWidget);
  });

  testWidgets('online paired opens the terminal; unpaired opens the scanner; offline is not tappable', (tester) async {
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    final args = terminals.single as TerminalRouteArgs;
    expect((args.agentId, args.machineName), (agentA, 'MacBook Pro của Phú'));
    await back(tester);

    await tester.tap(card(vanphong));
    await tester.pumpAndSettle();
    expect(terminals, hasLength(1));
    expect(scans, isEmpty);
    expect(find.text('Máy của bạn'), findsOneWidget);

    await tester.tap(card(ketoan));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('"N tab" counts the tabs open on this phone', (tester) async {
    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    await workspace.openNew((cols: 80, rows: 24));
    await openList(tester);
    expect(find.descendant(of: card(agentA), matching: find.text('2 tab')), findsOneWidget);
    expect(find.descendant(of: card(agentB), matching: find.textContaining('tab')), findsNothing);
  });

  testWidgets('while the relay reconnects: banner, dimmed "Đang chờ kết nối" cards, no taps', (tester) async {
    await openList(tester);
    backend.emitRelay(RelayConnectionState.disconnected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsOneWidget);
    expect(find.text('Đang chờ kết nối'), findsNWidgets(4));
    await tester.tap(card(agentA));
    await tester.pump();
    expect(terminals, isEmpty);

    backend.emitRelay(RelayConnectionState.connected);
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối, đang thử lại…'), findsNothing);
    expect(find.text('Online · macOS'), findsNWidgets(2));
  });

  testWidgets('an untrusted machine: "Cần ghép nối lại" offers "Quét mã"', (tester) async {
    terminalExit = TerminalExit.untrusted;
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(find.text('Cần ghép nối lại'), findsOneWidget);
    expect(find.text('Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'), findsOneWidget);
    await tester.tap(find.text('Quét mã'));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('proto_unsupported opens "Cần cập nhật app"', (tester) async {
    terminalExit = TerminalExit.updateRequired;
    await openList(tester);
    await tester.tap(card(agentA));
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(updates, hasLength(1));
  });

  testWidgets('first run: three steps, a link to shellx.pro and "Quét mã QR"', (tester) async {
    backend.deviceList = [];
    await openList(tester);
    expect(find.text('Chưa có máy nào'), findsOneWidget);
    expect(find.text('Đăng nhập cùng tài khoản này.'), findsOneWidget);
    expect(find.textContaining('Ghép nối điện thoại…'), findsOneWidget);
    await tester.tap(find.text('shellx.pro'));
    expect(links.opened, [Uri.parse('https://shellx.pro/')]);
    await tester.tap(find.text('Quét mã QR'));
    await tester.pumpAndSettle();
    expect(scans, hasLength(1));
  });

  testWidgets('settings; the list refreshes afterwards; refresh errors show the spec text', (tester) async {
    await openList(tester);
    backend.deviceList = [agentDevice(agentA, 'Renamed-Mac')];
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();
    expect(settingsVisits, hasLength(1));
    await back(tester);
    expect(find.text('Renamed-Mac'), findsOneWidget);

    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
  });
}
