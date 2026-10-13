import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

/// A11 Task 20 (D28): last used, "new output", retry and empty states of the machine list.
void main() {
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late WorkspaceRegistry registry;
  late AppSettings settings;

  setUp(() async {
    backend = FakeBackend(
      devices: [agentDevice(agentA, 'alpha'), agentDevice(agentB, 'beta')],
      pinnedList: [pinned(agentA), pinned(agentB)],
    )..onlineIds.addAll([agentA, agentB]);
    backend.addMachine(agentA);
    backend.addMachine(agentB);
    registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactory<MachineListController>(
        () => MachineListController(backend: backend, registry: registry, settings: settings, now: () => now),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  Future<void> openList(WidgetTester tester, {Locale locale = vi}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => const MachineListRoute(),
        routes: [
          AutoRoute(page: MachineListRoute.page),
          stubRoute(QrScannerRoute.name),
        ],
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  Finder card(String id) => find.byKey(ValueKey('machine-$id'));

  testWidgets('the machine opened last comes first among the online ones, with a chip', (tester) async {
    await settings.setLastMachine(agentB);
    await openList(tester);
    expect(tester.getTopLeft(card(agentB)).dy, lessThan(tester.getTopLeft(card(agentA)).dy));
    expect(find.descendant(of: card(agentB), matching: find.text('Dùng gần nhất')), findsOneWidget);
    expect(find.descendant(of: card(agentA), matching: find.text('Dùng gần nhất')), findsNothing);
  });

  testWidgets('without a last machine the order is by name and there is no chip', (tester) async {
    await openList(tester);
    expect(tester.getTopLeft(card(agentA)).dy, lessThan(tester.getTopLeft(card(agentB)).dy));
    expect(find.text('Dùng gần nhất'), findsNothing);
  });

  testWidgets('an offline last machine keeps its place and gets no chip', (tester) async {
    backend.onlineIds.remove(agentB);
    await settings.setLastMachine(agentB);
    await openList(tester);
    expect(tester.getTopLeft(card(agentA)).dy, lessThan(tester.getTopLeft(card(agentB)).dy));
    expect(find.text('Dùng gần nhất'), findsNothing);
  });

  Future<void> twoTabsOneUnseen() async {
    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    await workspace.openNew((cols: 80, rows: 24));
    workspace
      ..setViewing(true)
      ..select(1);
    backend.machines[agentA]!.handles.first.emit(const TabOutput('building'));
  }

  testWidgets('the card counts tabs with new output (VI)', (tester) async {
    await twoTabsOneUnseen();
    await openList(tester);
    expect(find.descendant(of: card(agentA), matching: find.text('2 tab · 1 có chữ mới')), findsOneWidget);
    expect(find.descendant(of: card(agentB), matching: find.textContaining('tab')), findsNothing);
  });

  testWidgets('the card counts tabs with new output (EN) and the dot has a label', (tester) async {
    await twoTabsOneUnseen();
    await openList(tester, locale: en);
    expect(
      find.descendant(of: card(agentA), matching: find.text('2 tabs · 1 with new output')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card(agentA),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'New output'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no new output: the plain "N tab" pill', (tester) async {
    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    await workspace.openNew((cols: 80, rows: 24));
    await openList(tester);
    expect(find.descendant(of: card(agentA), matching: find.text('2 tab')), findsOneWidget);
  });

  testWidgets('the count follows the output and clears when the tab is viewed', (tester) async {
    await twoTabsOneUnseen();
    await openList(tester);
    expect(find.text('2 tab · 1 có chữ mới'), findsOneWidget);
    registry.forMachine(agentA).select(0);
    await tester.pump();
    expect(find.text('2 tab'), findsOneWidget);
  });

  testWidgets('agent quick reply: the card shows a dot while an agent waits or runs on one of its tabs', (
    tester,
  ) async {
    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    await openList(tester);
    final dot = find.descendant(of: card(agentA), matching: find.byKey(const ValueKey('dot-agent')));
    expect(dot, findsNothing);

    final handle = backend.machines[agentA]!.handles.single;
    handle.emit(const TabAgent(agent: 'codex', state: AgentWireState.running));
    await tester.pump();
    expect(
      tester.widget<Container>(dot).decoration,
      isA<BoxDecoration>().having((d) => d.color, 'color', tester.element(dot).colors.secondaryText),
    );
    expect(
      find.descendant(
        of: card(agentA),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Agent đang chạy'),
      ),
      findsOneWidget,
    );

    handle.emit(const TabAgent(agent: 'codex', state: AgentWireState.needsInput));
    await tester.pump();
    expect(
      tester.widget<Container>(dot).decoration,
      isA<BoxDecoration>().having((d) => d.color, 'color', tester.element(dot).colors.warn),
    );
    expect(
      find.descendant(
        of: card(agentA),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Agent cần bạn trả lời'),
      ),
      findsOneWidget,
    );

    handle.emit(const TabAgent());
    await tester.pump();
    expect(dot, findsNothing);
  });

  testWidgets('a failed load with nothing listed shows the error with a retry that reloads once', (tester) async {
    backend.devicesError = const ApiException(status: 500, code: 'x', message: 'boom');
    await openList(tester);
    expect(find.byKey(const Key('machines.error')), findsOneWidget);
    expect(find.text('Không tải được danh sách máy'), findsOneWidget);
    expect(find.text('Hãy kiểm tra kết nối mạng.'), findsOneWidget);
    backend.devicesError = null;
    await tester.tap(find.byKey(const Key('machines.retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('machines.error')), findsNothing);
    expect(card(agentA), findsOneWidget);
  });

  testWidgets('an error with machines already listed keeps the list and offers the same button', (tester) async {
    await openList(tester);
    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(card(agentA), findsOneWidget);
    expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    expect(find.byKey(const Key('machines.error')), findsNothing);
    backend.devicesError = null;
    await tester.tap(find.byKey(const Key('machines.retry')));
    await tester.pumpAndSettle();
    expect(find.text('Thử lại sau ít phút.'), findsNothing);
  });

  testWidgets('an empty list keeps the pairing guide and adds a reload button', (tester) async {
    backend
      ..deviceList = []
      ..pinnedList = [];
    await openList(tester);
    expect(find.text('Chưa có máy nào'), findsOneWidget);
    backend.deviceList = [agentDevice(agentA, 'alpha')];
    await tester.ensureVisible(find.byKey(const Key('machines.reload')));
    await tester.tap(find.byKey(const Key('machines.reload')));
    await tester.pumpAndSettle();
    expect(card(agentA), findsOneWidget);
  });

  testWidgets('the texts exist in both languages', (tester) async {
    backend.devicesError = const ApiException(status: 500, code: 'x', message: 'boom');
    await openList(tester, locale: en);
    expect(find.text('Couldn’t load your computers'), findsOneWidget);
    expect(find.text('Check your internet connection.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('privacy: building the list prints no machine name', (tester) async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    await twoTabsOneUnseen();
    backend.devicesError = const ApiException(status: 500, code: 'x', message: 'boom');
    await openList(tester);
    debugPrint = previous;
    expect(lines.where((line) => line.contains('alpha') || line.contains('beta')), isEmpty);
  });
}
