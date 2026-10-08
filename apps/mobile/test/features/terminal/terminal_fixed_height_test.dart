import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/domain/cursor_shift.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/app_harness.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

/// A11 Task 21 (D31): the keyboard covers the terminal instead of shrinking it.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late AppSettings settings;

  setUp(() async {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerFactoryParam<TerminalPageController, String, void>(
        (agentId, _) => TerminalPageController(agentId, registry, session, settings),
      )
      ..registerFactory<VoiceComposerController>(() => VoiceComposerController(FakeSpeechInput(), settings))
      ..registerSingleton<ExternalLinks>(FakeExternalLinks());
  });

  tearDown(() async {
    registry.dispose();
    await getIt.reset();
  });

  /// A portrait phone (390 × 844 pt).
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      routedApp(
        open: () => TerminalRoute(agentId: agentA, machineName: 'MacBook-Pro'),
        routes: [AutoRoute(page: TerminalRoute.page)],
      ),
    );
    await tester.pumpAndSettle();
    await openPushed(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The keyboard: [logical] points tall.
  Future<void> keyboard(WidgetTester tester, double logical) async {
    tester.view.viewInsets = FakeViewPadding(bottom: logical * 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double areaHeight(WidgetTester tester) => tester.getSize(find.byKey(const Key('terminal.area'))).height;

  double shiftOf(WidgetTester tester) {
    final transform = tester.widget<Transform>(find.byKey(const Key('terminal.shift')));
    return -transform.transform.getTranslation().y;
  }

  /// Fills the screen so the cursor sits on the last row.
  Future<void> cursorAtBottom(WidgetTester tester) async {
    machine.handles.single.emit(TabOutput('\r\n' * 80));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('option off: the keyboard shrinks the terminal and sends a smaller size (today)', (tester) async {
    await open(tester);
    final before = machine.resizes.length;
    final rows = registry.forMachine(agentA).activeTab.value!.terminal.value.viewHeight;
    final height = areaHeight(tester);
    await keyboard(tester, 300);
    expect(areaHeight(tester), lessThan(height));
    expect(machine.resizes.length, greaterThan(before));
    expect(machine.resizes.last.rows, lessThan(rows));
    expect(find.byKey(const Key('terminal.shift')), findsNothing, reason: 'the old layout path is untouched');
  });

  group('option on', () {
    setUp(() => settings.setFixedTerminalHeight(true));

    testWidgets('the keyboard sends no resize and the terminal keeps its height', (tester) async {
      await open(tester);
      final before = machine.resizes.length;
      final height = areaHeight(tester);
      final rows = registry.forMachine(agentA).activeTab.value!.terminal.value.viewHeight;
      await keyboard(tester, 300);
      expect(machine.resizes.length, before, reason: 'the computer is told nothing');
      expect(areaHeight(tester), height);
      expect(registry.forMachine(agentA).activeTab.value!.terminal.value.viewHeight, rows);
    });

    testWidgets('the extra keys sit right above the keyboard, and can still be tapped there', (tester) async {
      await open(tester);
      final resting = tester.getBottomLeft(find.byType(ExtraKeysBar)).dy;
      await keyboard(tester, 300);
      expect(tester.getBottomLeft(find.byType(ExtraKeysBar)).dy, resting - 300);
      await tester.tap(find.byKey(const ValueKey('extra-key-esc')));
      expect(String.fromCharCodes(machine.inputs.last.data), '\x1b');
    });

    testWidgets('a cursor on the last row is shifted into view by cursorShift', (tester) async {
      await open(tester);
      await cursorAtBottom(tester);
      expect(shiftOf(tester), 0, reason: 'no keyboard, no shift');
      await keyboard(tester, 300);
      final terminal = registry.forMachine(agentA).activeTab.value!.terminal.value;
      final cell = terminalCellSize(shellxTerminalStyle(settings.fontSize.value), const TextScaler.linear(1));
      final expected = cursorShift(
        cursorBottom: 8 + (terminal.buffer.cursorY + 1) * cell.height,
        viewportHeight: areaHeight(tester),
        keyboardInset: 300,
      );
      expect(expected, greaterThan(0));
      expect(shiftOf(tester), closeTo(expected, 0.01));
    });

    testWidgets('a cursor already above the keyboard leaves the view alone', (tester) async {
      await open(tester);
      await keyboard(tester, 300);
      expect(shiftOf(tester), 0);
    });

    testWidgets('switching tab: the shift follows the new tab\'s cursor', (tester) async {
      await open(tester);
      await cursorAtBottom(tester);
      await keyboard(tester, 300);
      expect(shiftOf(tester), greaterThan(0));
      await tester.tap(find.byTooltip('Mở phiên mới'));
      await tester.pumpAndSettle();
      expect(shiftOf(tester), 0, reason: 'the new tab\'s cursor is on its first row');
      machine.handles.last.emit(TabOutput('\r\n' * 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shiftOf(tester), greaterThan(0), reason: 'its cursor moves the view');
      await tester.tap(find.byKey(const ValueKey('tab-101')));
      await tester.pumpAndSettle();
      expect(shiftOf(tester), greaterThan(0));
    });

    testWidgets('scrolled up in the history, the view is not shifted', (tester) async {
      await open(tester);
      machine.handles.single.emit(TabOutput('line\r\n' * 200));
      await tester.pump(const Duration(milliseconds: 50));
      await keyboard(tester, 300);
      expect(shiftOf(tester), greaterThan(0));
      final scroll = registry.forMachine(agentA).activeTab.value!.scroll;
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shiftOf(tester), 0, reason: 'the cursor is not on screen');
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shiftOf(tester), greaterThan(0));
    });

    testWidgets('closing the keyboard brings the view back', (tester) async {
      await open(tester);
      await cursorAtBottom(tester);
      await keyboard(tester, 300);
      expect(shiftOf(tester), greaterThan(0));
      await keyboard(tester, 0);
      expect(shiftOf(tester), 0);
      expect(find.byType(ExtraKeysBar), findsOneWidget);
    });

    testWidgets('rotating still resizes', (tester) async {
      await open(tester);
      final before = machine.resizes.length;
      tester.view.physicalSize = const Size(2532, 1170);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(machine.resizes.length, greaterThan(before));
    });

    testWidgets('the home indicator does not change the size when the keyboard opens', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
      addTearDown(tester.view.resetPadding);
      await open(tester);
      final before = machine.resizes.length;
      final height = areaHeight(tester);
      await keyboard(tester, 300);
      expect(areaHeight(tester), height);
      expect(machine.resizes.length, before);
    });

    testWidgets('typing, View as text and the budgeted feed still work with the keyboard up', (tester) async {
      await open(tester);
      await keyboard(tester, 300);
      machine.handles.single.emit(const TabOutput('hello world'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(registry.forMachine(agentA).activeTab.value!.terminal.value.buffer.getText(), contains('hello world'));
      await tester.tap(find.byTooltip('Xem dạng văn bản'));
      await tester.pumpAndSettle();
      expect(find.textContaining('hello world'), findsWidgets);
    });
  });
}
