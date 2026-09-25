import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:xterm/xterm.dart';

import '../../support/app_harness.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

void main() {
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: true);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late List<Object?> results;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    final settings = AppSettings(InMemoryKeyValueStore());
    results = [];
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      );
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// A portrait phone (390 × 844 pt) unless the test set another size first.
  Future<void> open(WidgetTester tester, {bool portrait = true}) async {
    if (portrait) {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [AutoRoute(page: TerminalRoute.page)],
        results: results,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
  }

  String lastInput() => utf8.decode(machine.inputs.last.data);
  String screen() => registry.forMachine(agentA).activeTab.value!.terminal.value.buffer.getText();

  testWidgets('first open without sessions opens a tab automatically; the chrome shows the machine', (tester) async {
    await open(tester);
    expect(find.text('MacBook-Pro'), findsOneWidget);
    expect(find.text('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);
    expect(machine.listCalls, 1);
    expect(machine.opened, hasLength(1));
    expect(machine.opened.single.cols, greaterThanOrEqualTo(1));
    expect(machine.opened.single.rows, greaterThanOrEqualTo(1));
    expect(find.text('zsh 1'), findsOneWidget);

    machine.handles.single.emit(const TabOutput('hello'));
    expect(screen(), contains('hello'));
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).theme.background, TerminalColors.background);
  });

  testWidgets('first open offers the running sessions in a sheet; later visits do not list', (tester) async {
    machine.sessions = [running];
    await open(tester);
    expect(find.text('Máy này đang có 1 phiên'), findsOneWidget);
    expect(find.textContaining('đang mở trên thiết bị khác'), findsOneWidget);

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(machine.attached.single.id, 7);
    expect(find.text('zsh 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Về danh sách máy'));
    await tester.pumpAndSettle();
    await openPushed(tester);
    expect(machine.listCalls, 1);
    expect(find.text('Máy này đang có 1 phiên'), findsNothing);
    expect(find.text('zsh 1'), findsOneWidget);
  });

  testWidgets('+ opens another tab; × asks before closing a live session', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('zsh 2'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('tab-102')), matching: find.byTooltip('Đóng phiên')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.'), findsOneWidget);
    await tester.tap(find.text('Đóng phiên'));
    await tester.pumpAndSettle();
    expect(machine.closed, [102]);
    expect(find.text('zsh 2'), findsNothing);
  });

  testWidgets('Review Focus 3: a session that vanished shows "Phiên đã kết thúc" and can be closed', (tester) async {
    machine.sessions = [running];
    machine.attachErrors[7] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    await open(tester);
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();

    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    expect(find.text('Máy tính không còn phiên này. Nội dung ở trên vẫn đọc và copy được.'), findsOneWidget);
    await tester.tap(find.text('Đóng tab'));
    await tester.pumpAndSettle();
    expect(find.text('Phiên đã kết thúc'), findsNothing);
    expect(find.text('zsh 1'), findsNothing);
    expect(machine.closed, [7]);
  });

  testWidgets('a reattached tab that the agent no longer knows ends the same way', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
  });

  testWidgets('design: an exited session keeps its content; "Mở phiên mới" replaces the tab', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabOutput('Built build/ios/iphoneos/Runner.app'));
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    expect(find.text('Lệnh cuối thoát với mã 0. Nội dung ở trên vẫn đọc và copy được.'), findsOneWidget);
    expect(screen(), contains('Runner.app'));

    await tester.tap(find.text('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(machine.opened, hasLength(2));
    expect(machine.closed, [101]);
    expect(find.text('zsh 2'), findsOneWidget);
    expect(find.text('Phiên đã kết thúc'), findsNothing);
  });

  testWidgets('spawn_failed shows the reason in the tab', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    await tester.pump();
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);
  });

  testWidgets('taken over: "Gắn lại" attaches this phone again', (tester) async {
    await open(tester);
    machine.reuseHandles = true;
    machine.handles.single.emit(const TabDetached(DetachReason.takenOver));
    await tester.pump();
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsOneWidget);
    await tester.tap(find.text('Gắn lại'));
    await tester.pumpAndSettle();
    expect(machine.attached.single.id, 101);
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsNothing);
  });

  testWidgets('session_limit is a floating notice that goes away', (tester) async {
    await open(tester);
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.'), findsOneWidget);
    await tester.pump(TerminalPageController.noticeDuration);
    expect(find.text('Máy đã mở tối đa 10 phiên. Hãy đóng bớt phiên.'), findsNothing);
  });

  testWidgets('an untrusted machine is unpaired and the page closes with the reason (spec §12)', (tester) async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await open(tester);
    await tester.pumpAndSettle();
    expect(backend.unpaired, [agentA]);
    expect(results, [TerminalExit.untrusted]);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('proto_unsupported closes the page asking for an update', (tester) async {
    machine.connectFailure = MachineConnectionFailure.protocolUnsupported;
    await open(tester);
    await tester.pumpAndSettle();
    expect(results, [TerminalExit.updateRequired]);
    expect(backend.unpaired, isEmpty);
  });

  testWidgets('extra keys and paste reach the active session', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return <String, Object?>{'text': 'echo 1\necho 2'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('extra-key-up')));
    expect(lastInput(), '\x1b[A');

    machine.handles.single.emit(const TabOutput('\x1b[?1h'));
    await tester.tap(find.byKey(const ValueKey('extra-key-up')));
    expect(lastInput(), '\x1bOA');

    await tester.scrollUntilVisible(
      find.text('Dán').hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('Dán'));
    await tester.pumpAndSettle();
    expect(lastInput(), 'echo 1\recho 2');
  });

  testWidgets('"Aa" opens the font size slider', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Cỡ chữ'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
    await tester.pumpAndSettle();
    expect(tester.widget<TerminalView>(find.byType(TerminalView)).textStyle.fontSize, 20);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });

  testWidgets('the status line follows the relay; 4001 offers "Kết nối lại"', (tester) async {
    await open(tester);
    backend.emitRelay(RelayConnectionState.disconnected);
    await tester.pump();
    expect(find.text('Mất kết nối, đang thử lại…'), findsOneWidget);
    backend.emitRelay(RelayConnectionState.connected);
    await tester.pump();
    expect(find.text('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);

    backend.emitRelay(RelayConnectionState.replaced);
    await tester.pump();
    expect(find.text('Một phiên bản khác của app đã kết nối.'), findsOneWidget);
    await tester.tap(find.text('Kết nối lại'));
    expect(session.reconnectCalls, 1);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });

  testWidgets('landscape: name and tabs share the bar, with a keyboard button', (tester) async {
    tester.view.physicalSize = const Size(2532, 1170);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester, portrait: false);
    expect(find.byTooltip('Bàn phím'), findsOneWidget);
    expect(find.byTooltip('Cỡ chữ'), findsNothing);
    expect(
      tester.getCenter(find.text('MacBook-Pro')).dy,
      moreOrLessEquals(tester.getCenter(find.text('zsh 1')).dy, epsilon: 4),
    );
  });
}
