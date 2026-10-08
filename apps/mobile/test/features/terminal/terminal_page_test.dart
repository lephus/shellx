import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/pages/terminal_page.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/xterm.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

void main() {
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: true);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late List<Object?> results;
  late FakeSpeechInput speech;

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
    speech = FakeSpeechInput();
    getIt
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(speech, settings))
      ..registerSingleton<ExternalLinks>(FakeExternalLinks());
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

  /// Answers `Clipboard.getData` with [text] and records every `Clipboard.setData`.
  List<String?> mockClipboard(WidgetTester tester, {String text = 'echo 1\necho 2'}) {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return <String, Object?>{'text': text};
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map<Object?, Object?>)['text'] as String?);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    return copied;
  }

  /// The platform's hardware copy/paste chord (Task 5): ⌘ on iOS, Ctrl+Shift on Android.
  Future<void> pressShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    final modifiers = defaultTargetPlatform == TargetPlatform.iOS
        ? [LogicalKeyboardKey.metaLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
  }

  /// Every line printed while [body] runs. signals_core 6.3.1 does not throw when a disposed
  /// signal is read: it prints "… has been read after disposed" and returns the stale value (R4).
  Future<List<String>> disposedReadsDuring(Future<void> Function() body) async {
    final lines = <String>[];
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => lines.add(line)),
    );
    return [
      for (final line in lines)
        if (line.contains('read after disposed')) line.split('\n').first,
    ];
  }

  /// Portrait → landscape: every widget that depends on the orientation or the layout builds again.
  Future<void> rotate(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2532, 1170);
    await tester.pump();
  }

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

  testWidgets('design: an exited session keeps its content; "Phiên mới" replaces the tab', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabOutput('Built build/ios/iphoneos/Runner.app'));
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    expect(find.text('Phiên đã kết thúc'), findsOneWidget);
    expect(find.text('Lệnh cuối thoát với mã 0. Nội dung ở trên vẫn đọc và copy được.'), findsOneWidget);
    expect(screen(), contains('Runner.app'));

    await tester.tap(find.text('Phiên mới'));
    await tester.pumpAndSettle();
    expect(machine.opened, hasLength(2));
    expect(machine.closed, [101]);
    expect(find.text('zsh 2'), findsOneWidget);
    expect(find.text('Phiên đã kết thúc'), findsNothing);
  });

  testWidgets('spawn_failed on the first open shows the reason in a tab, not a floating notice (spec §12)', (
    tester,
  ) async {
    machine.openError = const AppErrorException(AppErrorCode.spawnFailed, 'pwsh.exe not found');
    await open(tester);
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);
    expect(find.text('Đóng tab'), findsOneWidget);
    expect(find.text('Phiên mới'), findsOneWidget);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('Chưa có phiên nào đang mở.'), findsNothing);
    await tester.pump(TerminalPageController.noticeDuration);
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);

    // "Phiên mới" replaces the failed tab once the shell starts.
    machine.openError = null;
    await tester.tap(find.text('Phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsNothing);
    expect(find.text('zsh 1'), findsOneWidget);
    expect(machine.closed, isEmpty);
  });

  testWidgets('"+" on an empty machine with a spawn failure shows the card with the reason', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Đóng phiên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đóng phiên'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phiên nào đang mở.'), findsOneWidget);

    machine.openError = const AppErrorException(AppErrorCode.spawnFailed, 'pwsh.exe not found');
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có phiên nào đang mở.'), findsNothing);
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsOneWidget);

    await tester.tap(find.text('Đóng tab'));
    await tester.pumpAndSettle();
    expect(find.text('Không mở được shell: pwsh.exe not found'), findsNothing);
    expect(find.text('Chưa có phiên nào đang mở.'), findsOneWidget);
    expect(machine.closed, [101]);
  });

  testWidgets('a live tab that ever gets TabError(spawn_failed) shows the reason too', (tester) async {
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

  testWidgets('an untrusted machine closes the page with the reason and is not unpaired again (spec §12)', (
    tester,
  ) async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await open(tester);
    await tester.pumpAndSettle();
    // The client already forgot the pin; a DELETE now could remove a pairing made right after.
    expect(backend.unpaired, isEmpty);
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

    // The arrow pad and the mic come first: bring the arrow keys into view.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('extra-key-up')).hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
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
    // The banner and the status line both say it.
    expect(find.text('Một phiên bản khác của app đã kết nối.'), findsNWidgets(2));
    await tester.tap(find.text('Kết nối lại'));
    expect(session.reconnectCalls, 1);
    await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
  });

  testWidgets('tab strip: × is a 44 × 44 pt target; "+" sits on the chips\' centre line', (tester) async {
    await open(tester);
    final close = find.byWidgetPredicate((widget) => '${widget.key}'.contains("'tab-close-"));
    expect(close, findsOneWidget);
    expect(tester.getSize(close), const Size(44, 44));
    expect(
      tester.getCenter(find.byTooltip('Mở phiên mới')).dy,
      moreOrLessEquals(tester.getCenter(find.text('zsh 1')).dy, epsilon: 1),
    );
  });

  testWidgets('the ended card fits "New session" on one line at 320 pt and 1.3× text', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [AutoRoute(page: TerminalRoute.page)],
        locale: en,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final button = tester.getRect(find.byKey(const ValueKey('ended-second-action')));
    final label = find.text('New session');
    expect(tester.getRect(label).top, greaterThanOrEqualTo(button.top));
    expect(tester.getRect(label).bottom, lessThanOrEqualTo(button.bottom));
    expect(tester.widget<Text>(label).maxLines, 1);
    expect(find.byIcon(Icons.add), findsWidgets);
    final close = tester.getRect(find.text('Close tab'));
    expect(close.bottom - close.top, lessThan(button.height));
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale) in [(320.0, 2.0), (390.0, 2.0)]) {
    testWidgets('$scale× text at $width pt: live, voice composer and ended card lay out without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width * 2, 1300);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        routedApp(
          open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
          routes: [AutoRoute(page: TerminalRoute.page)],
          locale: en,
        ),
      );
      await tester.pumpAndSettle();
      await openPushed(tester);
      expect(tester.takeException(), isNull, reason: 'live');
      await tester.tap(find.byKey(const ValueKey('voice-mic')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'voice');
      machine.handles.single.emit(const TabExited(0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'ended');
      await tester.pump(const Duration(milliseconds: 200));
    });
  }

  testWidgets('"Aa": the font size sheet leaves the terminal undimmed, to see each size live', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Cỡ chữ'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color?.a ?? 0, 0); // no dimming
  });

  testWidgets('landscape: name and tabs share the bar, with a keyboard button', (tester) async {
    tester.view.physicalSize = const Size(2532, 1170);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await open(tester, portrait: false);
    expect(find.byTooltip('Bàn phím'), findsOneWidget);
    expect(
      tester.getCenter(find.text('MacBook-Pro')).dy,
      moreOrLessEquals(tester.getCenter(find.text('zsh 1')).dy, epsilon: 4),
    );
    // P2: the status line has no room; its dot stays (text as tooltip and label), and "Aa" too.
    expect(find.text('Đã kết nối · mã hóa đầu cuối'), findsNothing);
    expect(find.byTooltip('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);
    expect(find.bySemanticsLabel('Đã kết nối · mã hóa đầu cuối'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('terminal-status-dot'))).dy,
      moreOrLessEquals(tester.getCenter(find.text('MacBook-Pro')).dy, epsilon: 2),
    );
    expect(find.byTooltip('Cỡ chữ'), findsOneWidget);
  });

  // ---- Controller rulings (task-14-rulings.md) ----

  testWidgets(
    'R1: an untrusted handshake the client ran on its own closes the page once, never as "Phiên đã kết thúc"',
    (
      tester,
    ) async {
      final disposedReads = await disposedReadsDuring(() async {
        await open(tester);
        // What MachineClient does on HS2 `untrusted` after reconnecting by itself (no UI request):
        // forget the pin, end every attached tab with session_not_found, then MachineFailed.
        machine.onUntrusted!();
        machine.handles.single.emit(const TabError(AppErrorCode.sessionNotFound, 'no longer trusted'));
        machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.text('Phiên đã kết thúc'), findsNothing);
        }
        await tester.pumpAndSettle();
      });
      expect(results, [TerminalExit.untrusted]);
      expect(backend.unpaired, isEmpty);
      expect(find.text('open'), findsOneWidget);
      expect(disposedReads, isEmpty);
    },
  );

  testWidgets('R1: proto_unsupported found by the client on its own closes the page asking for an update', (
    tester,
  ) async {
    await open(tester);
    machine.emitState(const MachineFailed(MachineConnectionFailure.protocolUnsupported));
    await tester.pumpAndSettle();
    expect(results, [TerminalExit.updateRequired]);
    expect(backend.unpaired, isEmpty);
  });

  testWidgets('R1: the state event that follows a request that already handled untrusted is handled once', (
    tester,
  ) async {
    await open(tester);
    machine.openError = const MachineConnectionException(MachineConnectionFailure.untrusted);
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pump();
    machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(backend.unpaired, isEmpty);
    expect(results, [TerminalExit.untrusted]);
  });

  testWidgets('R1: untrusted while the session sheet is open closes the sheet, then the page', (tester) async {
    machine.sessions = [running];
    await open(tester);
    expect(find.text('Máy này đang có 1 phiên'), findsOneWidget);
    machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(results, [TerminalExit.untrusted]);
    expect(find.text('open'), findsOneWidget);
    expect(machine.attached, isEmpty);
  });

  testWidgets('R2: "Gắn lại" without a channel shows the ErrorText notice; nothing is left unhandled', (tester) async {
    await open(tester);
    machine.reuseHandles = true;
    machine.handles.single.emit(const TabDetached(DetachReason.takenOver));
    await tester.pump();
    machine.attachErrors[101] = const MachineConnectionException(MachineConnectionFailure.agentOffline);
    await tester.tap(find.text('Gắn lại'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Máy đang offline.'), findsOneWidget);
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsOneWidget);

    machine.attachErrors.remove(101);
    await tester.tap(find.text('Gắn lại'));
    await tester.pumpAndSettle();
    expect(machine.attached.map((a) => a.id), [101, 101]);
    expect(find.text('Phiên đang được mở trên thiết bị khác.'), findsNothing);
    await tester.pump(TerminalPageController.noticeDuration);
  });

  testWidgets(
    'R3: the hardware paste shortcut pastes like "Dán": CR line breaks, bracketed when enabled',
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}),
    (tester) async {
      mockClipboard(tester, text: 'echo 1\r\necho 2\n');
      await open(tester);
      await pressShortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      expect(lastInput(), 'echo 1\recho 2\r');
      // Once: the chord is handled at the terminal, so no default ⌘V/Ctrl+V binding pastes again.
      expect(machine.inputs, hasLength(1));

      machine.handles.single.emit(const TabOutput('\x1b[?2004h'));
      await pressShortcut(tester, LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      expect(lastInput(), '\x1b[200~echo 1\recho 2\r\x1b[201~');
    },
  );

  testWidgets(
    'R3: the hardware copy shortcut copies the selection like "Sao chép"',
    variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}),
    (tester) async {
      final copied = mockClipboard(tester);
      await open(tester);
      machine.handles.single.emit(const TabOutput('hello world'));
      final tab = registry.forMachine(agentA).activeTab.value!;
      final buffer = tab.terminal.value.buffer;
      tab.selection.setSelection(buffer.createAnchor(0, 0), buffer.createAnchor(5, 0));
      await tester.pump();
      expect(find.text('Sao chép'), findsOneWidget);

      await pressShortcut(tester, LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(copied, ['hello']);
      expect((getIt<PopupHandler>() as FakePopupHandler).successes, ['Đã sao chép']);
      expect(tab.selection.selection, isNull);
      expect(find.text('Sao chép'), findsNothing);
      expect(machine.inputs, isEmpty);
    },
  );

  testWidgets('"Sao chép" copies the long-press selection', (tester) async {
    final copied = mockClipboard(tester);
    await open(tester);
    machine.handles.single.emit(const TabOutput('hello world'));
    final tab = registry.forMachine(agentA).activeTab.value!;
    final buffer = tab.terminal.value.buffer;
    tab.selection.setSelection(buffer.createAnchor(6, 0), buffer.createAnchor(11, 0));
    await tester.pump();
    await tester.tap(find.text('Sao chép'));
    await tester.pumpAndSettle();
    expect(copied, ['world']);
    expect(tab.selection.selection, isNull);
  });

  testWidgets('R4: once the page leaves, nothing reads the dropped workspace (rotating while it closes)', (
    tester,
  ) async {
    final disposedReads = await disposedReadsDuring(() async {
      await open(tester);
      // The channel dropped; the next request's handshake gets HS2 `untrusted`.
      machine.emitState(const MachineIdle());
      machine.connectFailure = MachineConnectionFailure.untrusted;
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pump();
      await rotate(tester);
      expect(find.text('Phiên đã kết thúc'), findsNothing);
      await tester.pumpAndSettle();
    });
    expect(tester.takeException(), isNull);
    expect(results, [TerminalExit.untrusted]);
    expect(backend.unpaired, isEmpty);
    expect(disposedReads, isEmpty);
  });

  testWidgets('R4: untrusted on the first visit reads nothing of the dropped workspace', (tester) async {
    // The first frame's Watches subscribe after it (post-frame), when the workspace may be gone.
    machine.connectFailure = MachineConnectionFailure.untrusted;
    final disposedReads = await disposedReadsDuring(() async {
      await open(tester);
      await tester.pumpAndSettle();
    });
    expect(results, [TerminalExit.untrusted]);
    expect(disposedReads, isEmpty);
  });

  testWidgets('R4: a sign-out while the page is open shows nothing of the disposed workspaces', (tester) async {
    final disposedReads = await disposedReadsDuring(() async {
      await open(tester);
      session.signOut();
      await tester.pump();
      await rotate(tester);
      await tester.pumpAndSettle();
    });
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalView), findsNothing);
    expect(disposedReads, isEmpty);
  });

  testWidgets('R6: a machine that is no longer pinned closes the page as untrusted instead of crashing', (
    tester,
  ) async {
    // Forgotten by an `untrusted` handshake while no terminal page was open.
    machine.onUntrusted!();
    await open(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(results, [TerminalExit.untrusted]);
    expect(find.text('open'), findsOneWidget);
    expect(machine.connectCalls, 0);
  });

  testWidgets('R1: a page that another navigation already took off the stack pops nothing on its way out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [
          AutoRoute(page: TerminalRoute.page),
          stubRoute('FirstStub'),
          stubRoute('SecondStub'),
        ],
        results: results,
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
    final router = AutoRouter.of(tester.element(find.byType(TerminalPage))).root;

    // The page's exit is known (it pops after this frame) while a sign-out replaces the whole
    // stack, as `SessionEnforcer` does.
    machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    unawaited(router.replaceAll(const [PageRouteInfo('FirstStub'), PageRouteInfo('SecondStub')]));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect([for (final page in router.stack) page.routeData.name], ['FirstStub', 'SecondStub']);
    expect(find.text('SecondStub stub'), findsOneWidget);
    expect(find.byType(TerminalPage), findsNothing);
  });

  group('the status line says why the machine is not connected', () {
    Color dot(WidgetTester tester) =>
        (tester.widget<Container>(find.byKey(const ValueKey('terminal-status-dot'))).decoration! as BoxDecoration)
            .color!;

    testWidgets('green when connected, amber while connecting', (tester) async {
      await open(tester);
      expect(dot(tester), isNot(TerminalColors.yellow));
      expect(dot(tester), isNot(TerminalColors.red));

      machine.emitState(const MachineConnecting());
      await tester.pump();
      expect(find.text('Đang kết nối…'), findsOneWidget);
      expect(dot(tester), TerminalColors.yellow);
    });

    testWidgets('an offline machine says so, in red', (tester) async {
      await open(tester);
      machine.emitState(const MachineFailed(MachineConnectionFailure.agentOffline));
      await tester.pump();
      expect(find.text('Máy đang offline.'), findsOneWidget);
      expect(find.text('Đang kết nối…'), findsNothing);
      expect(dot(tester), TerminalColors.red);
    });

    testWidgets('another failure shows its ErrorText, in red', (tester) async {
      await open(tester);
      machine.emitState(const MachineFailed(MachineConnectionFailure.timeout));
      await tester.pump();
      expect(find.text('Máy tính không phản hồi. Hãy thử lại.'), findsOneWidget);
      expect(dot(tester), TerminalColors.red);
    });

    testWidgets('a replaced relay says another instance connected, in red', (tester) async {
      await open(tester);
      backend.emitRelay(RelayConnectionState.replaced);
      await tester.pump();
      expect(find.text('Đang kết nối…'), findsNothing);
      expect(find.text('Một phiên bản khác của app đã kết nối.'), findsNWidgets(2));
      expect(dot(tester), TerminalColors.red);
      await tester.pump(const Duration(seconds: 1)); // let the debounced resize fire
    });
  });

  testWidgets('"Phiên mới" still replaces the ended tab when the page was left while it opened', (tester) async {
    await open(tester);
    machine.handles.single.emit(const TabExited(0));
    await tester.pump();
    final gate = machine.openGate = Completer<void>();
    await tester.tap(find.text('Phiên mới'));
    await tester.pump();

    await tester.tap(find.byTooltip('Về danh sách máy'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final workspace = registry.forMachine(agentA);
    expect(workspace.tabs.value, hasLength(1));
    expect(workspace.tabs.value.single.isLive.value, isTrue);
    expect(machine.closed, [101]);
  });

  testWidgets('leaving the page while "+" is still opening writes nothing to the page and keeps the tab', (
    tester,
  ) async {
    await open(tester);
    final gate = machine.openGate = Completer<void>();
    await tester.tap(find.byTooltip('Mở phiên mới'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.byTooltip('Về danh sách máy'));
    await tester.pumpAndSettle();

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(registry.forMachine(agentA).tabs.value, hasLength(2));

    machine.openGate = null;
    await openPushed(tester);
    expect(find.text('zsh 2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a page built after a sign-out closes quietly instead of crashing', (tester) async {
    session.signOut();
    await open(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TerminalView), findsNothing);
    expect(results, isEmpty);
    expect(machine.connectCalls, 0);
  });

  testWidgets('an error while dropping the workspace of an untrusted machine still leaves the page', (tester) async {
    final throwing = _RemoveThrowsRegistry(session.backend);
    addTearDown(throwing.dispose);
    final settings = AppSettings(InMemoryKeyValueStore());
    getIt
      ..unregister<TerminalPageController>()
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, throwing, session, settings),
      );
    await open(tester);
    machine.emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(results, [TerminalExit.untrusted]);
  });

  testWidgets('a clipboard the platform cannot read or write shows the error toast', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('Clipboard.')) throw PlatformException(code: 'clipboard');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester);
    final popups = getIt<PopupHandler>() as FakePopupHandler;

    await tester.scrollUntilVisible(
      find.text('Dán').hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('Dán'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(machine.inputs, isEmpty);
    expect(popups.errors, ['Đã có lỗi xảy ra (PlatformException).']);

    machine.handles.single.emit(const TabOutput('hello world'));
    final tab = registry.forMachine(agentA).activeTab.value!;
    final buffer = tab.terminal.value.buffer;
    tab.selection.setSelection(buffer.createAnchor(0, 0), buffer.createAnchor(5, 0));
    await tester.pump();
    await tester.tap(find.text('Sao chép'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(popups.errors, hasLength(2));
    expect(popups.successes, isEmpty);
  });

  group('terminal sharing (§9, tests §11.5)', () {
    const window = SessionInfo(
      id: 40,
      index: 1,
      shell: 'zsh',
      createdAt: 1790000000000,
      attached: false,
      kind: SessionKind.desktop,
      app: 'Terminal',
      title: '~/projects/api',
    );
    const shellxSession = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: false);
    const stillRunning = 'Terminal vẫn chạy trên máy tính.';
    const hintOff =
        "Bật 'Chia sẻ terminal với điện thoại' trong menu ShellX trên máy tính để xem các terminal đang mở ở đây.";
    const hintUpdate = 'Cập nhật ShellX trên máy tính để xem các terminal đang mở.';
    const hintOn =
        'Chỉ các cửa sổ terminal mở sau khi bật chia sẻ mới hiện ở đây. Mở một cửa sổ terminal mới trên máy tính.';

    FakePopupHandler popups() => getIt<PopupHandler>() as FakePopupHandler;

    /// Opens the page and attaches the desktop terminal from the picker.
    Future<void> openDesktop(WidgetTester tester) async {
      machine
        ..sessions = [window]
        ..desktopSharingValue = true;
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('picker-session-40')));
      await tester.pumpAndSettle();
      expect(machine.attached.single.id, 40);
    }

    testWidgets('the picker shows two groups and "Phiên mới"; a desktop row attaches with its label', (tester) async {
      machine
        ..sessions = [shellxSession, window]
        ..desktopSharingValue = true;
      await open(tester);

      expect(find.text('Máy này đang có 2 phiên'), findsOneWidget);
      expect(find.text('TERMINAL TRÊN MÁY TÍNH'), findsOneWidget);
      expect(find.text('PHIÊN SHELLX'), findsOneWidget);
      expect(find.text('Terminal — ~/projects/api'), findsOneWidget);
      expect(find.text('zsh 1'), findsOneWidget);
      expect(find.text('Phiên mới'), findsOneWidget);
      expect(find.byKey(const ValueKey('picker-desktop-hint')), findsNothing);
      // Both kinds of row lead with an icon, so their labels line up.
      expect(
        find.descendant(of: find.byKey(const ValueKey('picker-session-7')), matching: find.byIcon(Icons.terminal)),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('zsh 1')).dx,
        tester.getTopLeft(find.text('Terminal — ~/projects/api')).dx,
      );

      await tester.tap(find.text('Terminal — ~/projects/api'));
      await tester.pumpAndSettle();
      expect(machine.attached.single.id, 40);
      // The tab is labelled with the window title, with a small computer icon.
      final chip = find.byKey(const ValueKey('tab-40'));
      expect(find.descendant(of: chip, matching: find.text('~/projects/api')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.desktop_windows_outlined)), findsOneWidget);
    });

    for (final (sharing, hint) in [(false, hintOff), (null, hintUpdate), (true, hintOn)]) {
      testWidgets('without a desktop terminal the picker hints by desktop_sharing: $sharing', (tester) async {
        machine
          ..sessions = [shellxSession]
          ..desktopSharingValue = sharing;
        await open(tester);
        expect(find.text('TERMINAL TRÊN MÁY TÍNH'), findsOneWidget);
        expect(find.text(hint), findsOneWidget);
        for (final other in [hintOff, hintUpdate, hintOn].where((h) => h != hint)) {
          expect(find.text(other), findsNothing);
        }
      });
    }

    testWidgets('"Phiên mới" in the picker opens a new session', (tester) async {
      machine.sessions = [window];
      await open(tester);
      await tester.tap(find.text('Phiên mới'));
      await tester.pumpAndSettle();
      expect(machine.opened, hasLength(1));
    });

    testWidgets('+ opens the picker while a session is not a tab yet, else a new session at once', (tester) async {
      await open(tester); // nothing listed: the first tab opens on its own
      expect(machine.opened, hasLength(1));

      machine
        ..sessions = [window]
        ..desktopSharingValue = true;
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pumpAndSettle();
      expect(machine.listCalls, 2);
      expect(find.text('Terminal — ~/projects/api'), findsOneWidget);
      await tester.tap(find.text('Terminal — ~/projects/api'));
      await tester.pumpAndSettle();
      expect(machine.attached.single.id, 40);
      expect(machine.opened, hasLength(1));

      // Everything listed is a tab now: + opens a new session without asking.
      await tester.dragUntilVisible(find.byTooltip('Mở phiên mới'), find.byType(ListView).first, const Offset(-200, 0));
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pumpAndSettle();
      expect(machine.listCalls, 3);
      expect(find.text('Phiên mới'), findsNothing);
      expect(machine.opened, hasLength(2));
    });

    testWidgets('× on a desktop tab detaches without asking and says the terminal keeps running', (tester) async {
      await openDesktop(tester);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('tab-40')), matching: find.byTooltip('Đóng tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đóng phiên này? Mọi chương trình đang chạy trong phiên sẽ bị dừng.'), findsNothing);
      expect(machine.closed, [40]);
      expect(find.byKey(const ValueKey('tab-40')), findsNothing);
      expect(popups().infos, [stillRunning]);
    });

    testWidgets('"Máy tính đang dùng terminal này": tapping the terminal or the banner sends the phone size', (
      tester,
    ) async {
      await openDesktop(tester);
      const banner = 'Máy tính đang dùng terminal này · Chạm để dùng tiếp';
      expect(find.text(banner), findsNothing);
      await tester.pump(const Duration(milliseconds: 200)); // any resize of the first layout is out
      final sent = machine.resizes.length;

      machine.handle(40).emit(const TabDriver(DriverSide.desktop));
      await tester.pump();
      expect(find.text(banner), findsOneWidget);
      // In the chrome under the tabs, not over the cells: no row is cut in half.
      final bannerRect = tester.getRect(find.byKey(const ValueKey('desktop-driver-banner')));
      expect(bannerRect.top, greaterThanOrEqualTo(tester.getRect(find.text('~/projects/api')).bottom));
      expect(bannerRect.bottom, lessThanOrEqualTo(tester.getRect(find.byType(TerminalView)).top));
      // The row it takes from the view is not sent: the computer keeps the size until a tap.
      await tester.pump(const Duration(milliseconds: 200));
      expect(machine.resizes, hasLength(sent));

      await tester.tap(find.byType(TerminalView));
      await tester.pump();
      expect(machine.resizes, hasLength(sent + 1));
      expect(machine.resizes.last.id, 40);
      expect(find.text(banner), findsOneWidget); // until the agent confirms

      await tester.tap(find.text(banner));
      await tester.pump();
      expect(machine.resizes, hasLength(sent + 2));

      machine.handle(40).emit(const TabDriver(DriverSide.phone));
      await tester.pump();
      expect(find.text(banner), findsNothing);
      // The view gets its row back; the phone drives now, so that size goes out.
      await tester.pump(const Duration(milliseconds: 200));
      expect(machine.resizes, hasLength(sent + 3));
      expect(machine.resizes.last.rows, greaterThan(machine.resizes[sent].rows));

      // While the phone drives, a tap sends nothing.
      await tester.tap(find.byType(TerminalView));
      await tester.pump();
      expect(machine.resizes, hasLength(sent + 3));
    });

    testWidgets('scrolling, a long press and a two-finger pinch on the terminal do not take the size back', (
      tester,
    ) async {
      await openDesktop(tester);
      machine.handle(40).emit(const TabDriver(DriverSide.desktop));
      await tester.pump(const Duration(milliseconds: 200));
      final sent = machine.resizes.length;
      final terminal = find.byType(TerminalView);
      final center = tester.getCenter(terminal);

      // Scroll through the history.
      await tester.drag(terminal, const Offset(0, 200));
      await tester.pump();
      expect(machine.resizes, hasLength(sent));

      // Long press (selection) without moving.
      final press = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 800));
      await press.up();
      await tester.pump();
      expect(machine.resizes, hasLength(sent));
      registry.forMachine(agentA).activeTab.value!.selection.clearSelection();

      // Pinch: a second finger joins before the first lifts, neither moving far.
      final first = await tester.startGesture(center - const Offset(30, 0));
      final second = await tester.startGesture(center + const Offset(30, 0), pointer: 7);
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(machine.resizes, hasLength(sent));
      expect(find.text('Máy tính đang dùng terminal này · Chạm để dùng tiếp'), findsOneWidget);

      // A plain tap still does.
      await tester.tap(terminal);
      await tester.pump();
      expect(machine.resizes, hasLength(sent + 1));
    });

    testWidgets('after closing the last desktop tab, "Mở phiên mới" offers the computer\'s terminals again', (
      tester,
    ) async {
      await openDesktop(tester);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('tab-40')), matching: find.byTooltip('Đóng tab')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có phiên nào đang mở.'), findsOneWidget);

      await tester.tap(find.text('Mở phiên mới'));
      await tester.pumpAndSettle();
      expect(machine.listCalls, 2);
      expect(find.text('Terminal — ~/projects/api'), findsOneWidget);
      expect(machine.opened, isEmpty);

      await tester.tap(find.text('Terminal — ~/projects/api'));
      await tester.pumpAndSettle();
      expect(machine.attached.map((a) => a.id), [40, 40]);
    });

    List<({int id, int cols, int rows})> desktopResizes() => [
      for (final r in machine.resizes)
        if (r.id == 40) r,
    ];

    /// The desktop tab with the computer driving, every resize of the banner's own row settled.
    Future<int> computerDrives(WidgetTester tester) async {
      await openDesktop(tester);
      await tester.pump(const Duration(milliseconds: 200));
      machine.handle(40).emit(const TabDriver(DriverSide.desktop));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      return desktopResizes().length;
    }

    testWidgets('switching back to a desktop tab the computer drives sends nothing', (tester) async {
      final sent = await computerDrives(tester);
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pumpAndSettle();
      expect(registry.forMachine(agentA).tabs.value, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('tab-40')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Máy tính đang dùng terminal này · Chạm để dùng tiếp'), findsOneWidget);
      expect(desktopResizes(), hasLength(sent));
    });

    testWidgets('rotating while the computer drives takes the size back', (tester) async {
      final sent = await computerDrives(tester);
      final before = registry.forMachine(agentA).activeTab.value!.terminal.value.viewWidth;
      await rotate(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(desktopResizes(), hasLength(sent + 1));
      expect(desktopResizes().last.cols, greaterThan(before));
      addTearDown(tester.view.reset);
    });

    testWidgets('the keyboard showing while the computer drives takes the size back', (tester) async {
      final sent = await computerDrives(tester);
      final before = registry.forMachine(agentA).activeTab.value!.terminal.value.viewHeight;
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(desktopResizes(), hasLength(sent + 1));
      expect(desktopResizes().last.rows, lessThan(before));
    });

    testWidgets('a font size change while the computer drives takes the size back', (tester) async {
      final sent = await computerDrives(tester);
      await tester.tap(find.byTooltip('Cỡ chữ'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(20);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(desktopResizes(), hasLength(sent + 1));
    });

    testWidgets('typing while the computer drives sends the phone size before the keys', (tester) async {
      await openDesktop(tester);
      machine.handle(40).emit(const TabDriver(DriverSide.desktop));
      await tester.pump();
      final sent = machine.resizes.length;
      registry.forMachine(agentA).activeTab.value!.terminal.value.textInput('ls');
      expect(machine.resizes, hasLength(sent + 1));
      expect(lastInput(), 'ls');
      // The banner took a row: that size is not sent while the computer drives.
      await tester.pump(const Duration(milliseconds: 200));
      expect(machine.resizes, hasLength(sent + 1));
    });

    testWidgets('session.exited: "Cửa sổ terminal trên máy tính đã đóng." with only "Đóng tab"', (tester) async {
      await openDesktop(tester);
      machine.handle(40).emit(const TabOutput('git pull'));
      machine.handle(40).emit(const TabExited(0));
      await tester.pump();
      expect(find.text('Cửa sổ terminal trên máy tính đã đóng.'), findsOneWidget);
      expect(find.text('Mở phiên mới'), findsNothing);
      expect(find.text('Gắn lại'), findsNothing);
      expect(screen(), contains('git pull'));

      await tester.tap(find.text('Đóng tab'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tab-40')), findsNothing);
      // The window is gone: no "still running" toast.
      expect(popups().infos, isEmpty);
    });

    testWidgets('terminal_gone: "Mất kết nối với terminal này trên máy tính." with only "Đóng tab"', (tester) async {
      await openDesktop(tester);
      machine.handle(40).emit(const TabDetached(DetachReason.terminalGone));
      await tester.pump();
      expect(find.text('Mất kết nối với terminal này trên máy tính.'), findsOneWidget);
      expect(find.text('Phiên đã bị đóng trên máy tính.'), findsNothing);
      expect(find.text('Mở phiên mới'), findsNothing);
      expect(find.text('Gắn lại'), findsNothing);
      expect(find.text('Đóng tab'), findsWidgets);
    });

    testWidgets('closed_by_host: "Máy tính đã ngắt điện thoại khỏi terminal này." with "Gắn lại" and "Đóng tab"', (
      tester,
    ) async {
      await openDesktop(tester);
      machine.reuseHandles = true;
      machine.handle(40).emit(const TabDetached(DetachReason.closedByHost));
      await tester.pump();
      expect(find.text('Máy tính đã ngắt điện thoại khỏi terminal này.'), findsOneWidget);
      expect(find.text('Mở phiên mới'), findsNothing);

      await tester.tap(find.text('Gắn lại'));
      await tester.pumpAndSettle();
      expect(machine.attached.map((a) => a.id), [40, 40]);
      expect(find.text('Máy tính đã ngắt điện thoại khỏi terminal này.'), findsNothing);
    });

    testWidgets('"Đóng tab" after closed_by_host says the terminal keeps running', (tester) async {
      await openDesktop(tester);
      machine.handle(40).emit(const TabDetached(DetachReason.closedByHost));
      await tester.pump();
      await tester.tap(find.text('Đóng tab'));
      await tester.pumpAndSettle();
      expect(machine.closed, [40]);
      expect(popups().infos, [stillRunning]);
    });
  });

  group('A10 D12: a tap on a web address', () {
    /// Where the middle of cell ([col], [row]) is on screen.
    Offset cellCentre(WidgetTester tester, int col, int row) {
      final render = tester.state<TerminalViewState>(find.byType(TerminalView)).renderTerminal;
      return tester.getTopLeft(find.byType(TerminalView)) +
          render.getOffset(CellOffset(col, row)) +
          Offset(render.cellSize.width / 2, render.cellSize.height / 2);
    }

    testWidgets('offers the address; Open hands it to the platform', (tester) async {
      await open(tester);
      machine.handles.single.emit(const TabOutput('PR: https://github.com/a/b/pull/7.'));
      await tester.pump();
      await tester.tapAt(cellCentre(tester, 8, 0));
      await tester.pumpAndSettle();
      expect(find.text('Mở liên kết?'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byKey(const ValueKey('link-sheet-url'))).data,
        'https://github.com/a/b/pull/7',
      );
      await tester.tap(find.byKey(const ValueKey('link-sheet-open')));
      await tester.pumpAndSettle();
      expect((getIt<ExternalLinks>() as FakeExternalLinks).opened.map((u) => u.toString()), [
        'https://github.com/a/b/pull/7',
      ]);
    });

    testWidgets('Copy link copies it and opens nothing', (tester) async {
      await open(tester);
      machine.handles.single.emit(const TabOutput('https://example.com/x'));
      await tester.pump();
      final copied = mockClipboard(tester);
      await tester.tapAt(cellCentre(tester, 3, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link-sheet-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['https://example.com/x']);
      expect((getIt<ExternalLinks>() as FakeExternalLinks).opened, isEmpty);
    });

    testWidgets('a tap elsewhere offers nothing', (tester) async {
      await open(tester);
      machine.handles.single.emit(const TabOutput('plain words https://example.com/x'));
      await tester.pump();
      await tester.tapAt(cellCentre(tester, 2, 0));
      await tester.pump(const Duration(milliseconds: 400)); // xterm's double-tap timer
      expect(find.byKey(const ValueKey('link-sheet-url')), findsNothing);
    });

    testWidgets('a file: or javascript: address is never offered', (tester) async {
      await open(tester);
      machine.handles.single.emit(const TabOutput('file:///etc/passwd javascript:alert(1)'));
      await tester.pump();
      await tester.tapAt(cellCentre(tester, 5, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(cellCentre(tester, 25, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('link-sheet-url')), findsNothing);
    });
  });

  group('A10 D28: view as text', () {
    Finder button() => find.byKey(const ValueKey('view-as-text'));

    testWidgets('the sheet shows the recent text, selectable, and Copy all copies it', (tester) async {
      await open(tester);
      machine.handles.single.emit(const TabOutput('git status\r\nXin chào  \r\n\r\n'));
      await tester.pump();
      final copied = mockClipboard(tester);
      await tester.tap(button());
      await tester.pumpAndSettle();
      final body = tester.widget<SelectableText>(find.byKey(const ValueKey('view-as-text-body')));
      expect(body.data, 'git status\nXin chào');
      await tester.tap(find.byKey(const ValueKey('view-as-text-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['git status\nXin chào']);
    });

    testWidgets('Refresh takes a new snapshot; an empty terminal says so', (tester) async {
      await open(tester);
      await tester.tap(button());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('view-as-text-empty')), findsOneWidget);
      expect(tester.widget<TextButton>(find.byKey(const ValueKey('view-as-text-copy'))).onPressed, isNull);
      machine.handles.single.emit(const TabOutput('later output'));
      await tester.tap(find.byKey(const ValueKey('view-as-text-refresh')));
      await tester.pumpAndSettle();
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('view-as-text-body'))).data, 'later output');
    });

    testWidgets('opening and closing the sheet never resizes the terminal on the computer', (tester) async {
      await open(tester);
      final before = machine.resizes.length;
      await tester.tap(button());
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      expect(machine.resizes.length, before);
    });

    testWidgets('the button is in landscape too', (tester) async {
      tester.view.physicalSize = const Size(2532, 1170);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await open(tester, portrait: false);
      expect(button(), findsOneWidget);
    });
  });

  group('voice composer', () {
    Finder mic() => find.byKey(const ValueKey('voice-mic'));

    /// [open] with "reduce motion" on: the listening pulse then stands still.
    Future<void> openQuiet(WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester);
    }

    testWidgets('the mic opens the composer, which shows the target tab and listens in Vietnamese', (tester) async {
      await openQuiet(tester);
      expect(find.byKey(const ValueKey('voice-text')), findsNothing);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-text')), findsOneWidget);
      expect(find.text('Gửi tới: zsh 1 · MacBook-Pro'), findsOneWidget);
      expect(find.textContaining('MacBook-Pro'), findsWidgets);
      expect(speech.starts.single.localeId, 'vi-VN');
    });

    testWidgets('speaking then "gửi" sends the line with Enter to the active session', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechPartial('git'));
      await tester.pump();
      expect(find.text('git'), findsOneWidget);
      speech.emit(const SpeechFinal('git status gửi'));
      await tester.pump();
      expect(lastInput(), '\r');
      expect(utf8.decode(machine.inputs[machine.inputs.length - 2].data), 'git status');
    });

    testWidgets('typed text goes with the Send button; ✕ closes and gives focus back', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechListening(false));
      await tester.enterText(find.byKey(const ValueKey('voice-text')), 'ls -la');
      await tester.tap(find.byKey(const ValueKey('voice-send')));
      await tester.pump();
      expect(lastInput(), '\r');
      await tester.tap(find.byKey(const ValueKey('voice-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('voice-text')), findsNothing);
      expect(tester.widget<TerminalView>(find.byType(TerminalView)).focusNode!.hasFocus, isTrue);
      // The terminal grew back: let its resize debounce run.
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('refused permission shows the issue with Mở Cài đặt', (tester) async {
      speech.permission = SpeechPermission.denied;
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.text('Cần quyền micro và nhận dạng giọng nói để nói lệnh'), findsOneWidget);
      expect(find.text('Mở Cài đặt'), findsOneWidget);
    });

    testWidgets('the EN chip switches the language for the next listen', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('voice-locale-en')));
      await tester.pump();
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(speech.starts.last.localeId, 'en-US');
    });

    testWidgets('the hint names the send word of the voice language, not of the app', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech
        ..emit(const SpeechListening(true))
        ..emit(const SpeechListening(false));
      await tester.pump();
      expect(find.text('Nói hoặc gõ… nói “gửi” để gửi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-locale-en')));
      await tester.pump();
      expect(find.text('Nói hoặc gõ… nói “send” để gửi'), findsOneWidget);
    });

    testWidgets('listening says so in the field and to the screen reader', (tester) async {
      final announced = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
        message,
      ) async {
        final map = message! as Map<Object?, Object?>;
        if (map['type'] == 'announce') announced.add((map['data']! as Map<Object?, Object?>)['message']! as String);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
      );
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      expect(find.text('Đang nghe… nói “gửi” để gửi'), findsOneWidget);
      expect(announced, ['Đang nghe']);
      speech.emit(const SpeechFinal('ls'));
      await tester.pump();
      expect(find.text('Đang nghe… nói “gửi” để gửi'), findsNothing);
      expect(announced, ['Đang nghe']);
    });

    testWidgets('VI/EN is a two-segment control: 44 pt targets, the same width selected or not', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      Size segment(String code) => tester.getSize(
        find.ancestor(of: find.byKey(ValueKey('voice-locale-$code')), matching: find.byType(TextButton)).first,
      );
      expect(find.byType(SegmentedButton<VoiceLocale>), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      final before = (segment('vi'), segment('en'));
      expect(before.$1.height, greaterThanOrEqualTo(44));
      expect(before.$1.width, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const ValueKey('voice-locale-en')));
      await tester.pumpAndSettle();
      expect((segment('vi'), segment('en')), before);
    });

    testWidgets('A10 D30: the composer keeps a command literal: no autocorrect, smart dashes or capitals', (
      tester,
    ) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('voice-text')));
      expect(field.autocorrect, isFalse);
      // Android keeps suggestions (Vietnamese Telex/VNI composing); iOS turns them off.
      expect(field.enableSuggestions, defaultTargetPlatform == TargetPlatform.android);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
      expect(field.textCapitalization, TextCapitalization.none);
      expect(field.keyboardType, TextInputType.multiline);
    });

    testWidgets('the command is in JetBrains Mono, the hint in Raleway; Send says Enter when empty', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('voice-text')));
      expect(field.style!.fontFamily, FontFamily.jetBrainsMono);
      expect(field.decoration!.hintStyle!.fontFamily, FontFamily.raleway);
      expect(find.byTooltip('Gửi phím Enter'), findsOneWidget);
      speech.emit(const SpeechFinal('ls'));
      await tester.pump();
      expect(find.byTooltip('Gửi'), findsOneWidget);
    });

    testWidgets('refused permission: the issue and Mở Cài đặt pass AA on the keyboard grey', (tester) async {
      speech.permission = SpeechPermission.denied;
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      final colors = Brightness.light.appColors;
      final issue = tester.widget<Text>(find.text('Cần quyền micro và nhận dạng giọng nói để nói lệnh'));
      expect(issue.style!.color, colors.keyboardError);
      final link = tester.widget<Text>(find.text('Mở Cài đặt'));
      expect(link.style!.color, colors.keyboardLink);
      await tester.tap(find.text('Mở Cài đặt'));
      await tester.pump();
      expect((getIt<ExternalLinks>() as FakeExternalLinks).settingsOpened, 1);
    });

    testWidgets('an ended session keeps the mic in place, disabled, and says why Send is off', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      final micLeft = tester.getTopLeft(mic());
      final escLeft = tester.getTopLeft(find.byKey(const ValueKey('extra-key-esc')));
      speech.emit(const SpeechFinal('giữ chữ này'));
      machine.handles.single.emit(const TabExited(0));
      await tester.pumpAndSettle();
      expect(mic(), findsOneWidget);
      expect(tester.getTopLeft(mic()), micLeft);
      expect(tester.getTopLeft(find.byKey(const ValueKey('extra-key-esc'))), escLeft);
      expect(
        tester.getSemantics(mic()),
        matchesSemantics(label: 'Nói lệnh', isButton: true, hasEnabledState: true, isEnabled: false),
      );
      final starts = speech.starts.length;
      await tester.tap(mic());
      await tester.pump();
      expect(speech.starts, hasLength(starts));
      expect(find.text('giữ chữ này'), findsOneWidget);
      expect(find.text('Phiên đã kết thúc — mở phiên mới để gửi'), findsOneWidget);
      expect(find.text('Phiên chưa kết nối — gửi được khi kết nối lại'), findsNothing);
      final send = tester.widget<IconButton>(find.byKey(const ValueKey('voice-send')));
      expect(send.onPressed, isNull);
      // The composer grew by the note: let the terminal's resize debounce run.
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('the mic is a button the screen reader can tap while the tab is live', (tester) async {
      await openQuiet(tester);
      expect(
        tester.getSemantics(mic()),
        matchesSemantics(
          label: 'Nói lệnh',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('listening, the mic still stops the listen after the tab stopped being live', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      machine.handles.single.emit(const TabExited(0));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(mic()),
        matchesSemantics(
          label: 'Dừng nghe',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(mic());
      await tester.pump();
      expect(speech.stops, 1);
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('A11 D29: each tab keeps its own draft; closing a tab drops its draft', (tester) async {
      await openQuiet(tester);
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pumpAndSettle();
      await tester.tap(mic());
      await tester.pumpAndSettle();
      speech.emit(const SpeechListening(true));
      speech.emit(const SpeechListening(false));
      await tester.pump();
      String field() => tester.widget<TextField>(find.byKey(const ValueKey('voice-text'))).controller!.text;
      await tester.enterText(find.byKey(const ValueKey('voice-text')), 'ls -la');
      await tester.tap(find.byKey(const ValueKey('tab-101')));
      await tester.pumpAndSettle();
      expect(field(), '', reason: 'the other tab starts empty');
      await tester.enterText(find.byKey(const ValueKey('voice-text')), 'git status');
      await tester.tap(find.byKey(const ValueKey('tab-102')));
      await tester.pumpAndSettle();
      expect(field(), 'ls -la');
      await tester.tap(find.byKey(const ValueKey('tab-101')));
      await tester.pumpAndSettle();
      expect(field(), 'git status');
      final tabs = registry.forMachine(agentA).tabs.value;
      expect([for (final tab in tabs) tab.draft.value], ['git status', 'ls -la']);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('tab-101')), matching: find.byTooltip('Đóng phiên')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đóng phiên'));
      await tester.pumpAndSettle();
      expect(field(), 'ls -la', reason: 'the closed tab took its draft with it');
      await tester.pump(const Duration(milliseconds: 150));
    });

    testWidgets('a session taken by another device says to reattach', (tester) async {
      await openQuiet(tester);
      await tester.tap(mic());
      await tester.pumpAndSettle();
      machine.handles.single.emit(const TabDetached(DetachReason.takenOver));
      await tester.pumpAndSettle();
      expect(find.text('Phiên đã ngắt khỏi điện thoại — gắn lại để gửi'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
    });
  });
}

/// A registry whose [remove] fails, like a workspace whose disposal throws.
class _RemoveThrowsRegistry extends WorkspaceRegistry {
  _RemoveThrowsRegistry(super.backend);

  @override
  void remove(String agentId) => throw StateError('dispose failed');
}
