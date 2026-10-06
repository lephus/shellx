import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    h = TestHarness(settings: {'onboarding_done': true});
    container = ProviderContainer(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await container
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    await tester.pump();
  }

  /// Tears the app down inside the body: bootstrap starts the periodic
  /// update check, and testWidgets fails on pending timers before an
  /// addTearDown callback could dispose the container.
  void testApp(
    String description,
    Future<void> Function(WidgetTester) body, {
    TestVariant<Object?> variant = const DefaultTestVariant(),
  }) => testWidgets(description, variant: variant, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  });

  testApp('the terminal window is the base; a route is a dialog over it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('sidebar.newTab')), findsOneWidget);
    container.read(windowRouterProvider.notifier).open(const LoginRoute());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialog')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('dialog'))).width, 400);
    expect(find.byKey(const Key('sidebar.newTab')), findsOneWidget);
  });

  testApp('Escape closes the dialog, not the window', (tester) async {
    await pump(tester);
    container.read(windowRouterProvider.notifier)
      ..showTerminal()
      ..open(const ChangePasswordRoute());
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(container.read(windowRouterProvider).route, isNull);
    expect(container.read(windowRouterProvider).visible, isTrue);
  });

  testApp('with no dialog, Escape reaches the shell (vim)', (tester) async {
    await pump(tester);
    await h.sessions.open(cols: 80, rows: 24);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(h.ptys.ptys.single.writtenText, '\x1b');
  });

  testApp('a confirm is a dialog; its buttons answer it', (tester) async {
    await pump(tester);
    final answer = container
        .read(windowRouterProvider.notifier)
        .confirm(
          ConfirmRequest(
            title: 'Close “claude”?',
            body: 'b',
            confirmLabel: 'Close tab',
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('Close “claude”?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm.cancel')));
    expect(await answer, isFalse);
  });

  testApp('a scrim click closes the pairing dialog, never a confirm (UI §4)', (
    tester,
  ) async {
    await pump(tester);
    final router = container.read(windowRouterProvider.notifier);
    final answer = router.confirm(
      ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(container.read(windowRouterProvider).confirm, isNotNull);
    router.close();
    expect(await answer, isFalse);

    router.open(const PairingRoute());
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(container.read(windowRouterProvider).route, isNull);
  });

  testApp(
    'confirm actions: macOS [Cancel] [Action], Windows [Action] [Cancel] '
    'with a close button; a destructive confirm starts on Cancel',
    (tester) async {
      await pump(tester);
      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      final answer = container
          .read(windowRouterProvider.notifier)
          .confirm(ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'));
      await tester.pumpAndSettle();
      final cancel = tester.getCenter(find.byKey(const Key('confirm.cancel')));
      final ok = tester.getCenter(find.byKey(const Key('confirm.ok')));
      expect(mac ? cancel.dx < ok.dx : ok.dx < cancel.dx, isTrue);
      expect(
        find.byKey(const Key('dialog.close')),
        mac ? findsNothing : findsOneWidget,
      );
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused?.findAncestorWidgetOfExactType<OutlinedButton>()?.key,
        const Key('confirm.cancel'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(await answer, isFalse);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}
