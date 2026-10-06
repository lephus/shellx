import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1100, 720),
  }) async {
    h = TestHarness(settings: {'onboarding_done': true});
    container = ProviderContainer(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await container
        .read(agentControllerProvider.notifier)
        .bootstrap(watchForWake: false);
    tester.view.physicalSize = size;
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

  group('the smallest window (640×400): every dialog fits or scrolls', () {
    final cases = <String, (WindowRoute, String)>{
      'login': (const LoginRoute(), 'login.submit'),
      'onboarding': (const OnboardingRoute(), 'onboarding.finish'),
      'pairing': (const PairingRoute(), 'pairing.new'),
      'change password': (const ChangePasswordRoute(), 'password.submit'),
    };
    for (final MapEntry(key: name, value: (route, action)) in cases.entries) {
      testApp('$name: no overflow, the primary action is reachable', (
        tester,
      ) async {
        await pump(tester, size: ShellxSizes.minWindow);
        container.read(windowRouterProvider.notifier).open(route);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.byKey(Key(action));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
      });
    }

    testApp('a long confirm: no overflow, the action is reachable', (
      tester,
    ) async {
      await pump(tester, size: ShellxSizes.minWindow);
      final answer = container
          .read(windowRouterProvider.notifier)
          .confirm(
            ConfirmRequest(
              title: 't',
              body: List.filled(80, 'a line of the file list').join('\n'),
              confirmLabel: 'ok',
              long: true,
              destructive: false,
            ),
          );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('confirm.ok')));
      expect(await answer, isTrue);
    });
  });

  testApp('the login dialog is a named route and starts on the email field '
      '(UI §3.7)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    container.read(windowRouterProvider.notifier).open(const LoginRoute());
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<TextField>()?.key,
      const Key('login.email'),
    );
    final node = tester.getSemantics(find.byKey(const Key('dialog')));
    expect(node.label, 'Sign in to ShellX');
    expect(node.flagsCollection.scopesRoute, isTrue);
    expect(node.flagsCollection.namesRoute, isTrue);
    semantics.dispose();
  });

  testApp('the change-password dialog starts on the new password field', (
    tester,
  ) async {
    await pump(tester);
    container
        .read(windowRouterProvider.notifier)
        .open(const ChangePasswordRoute());
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<TextField>()?.key,
      const Key('password.new'),
    );
  });

  testApp('a scrim click closes change-password only once it says "done"', (
    tester,
  ) async {
    await pump(tester);
    await container
        .read(agentControllerProvider.notifier)
        .signIn(email: 'a@b.co', password: '12345678', register: false);
    final router = container.read(windowRouterProvider.notifier)
      ..open(const ChangePasswordRoute());
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(router.current, isA<ChangePasswordRoute>());
    await tester.enterText(
      find.byKey(const Key('password.new')),
      'long enough 1',
    );
    await tester.enterText(
      find.byKey(const Key('password.confirm')),
      'long enough 1',
    );
    await tester.tap(find.byKey(const Key('password.submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('password.done')), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(router.current, isNull);
  });

  testApp('a closed dialog leaves with the 120 ms exit fade (UI §1.5)', (
    tester,
  ) async {
    await pump(tester);
    final router = container.read(windowRouterProvider.notifier)
      ..open(const LoginRoute());
    await tester.pumpAndSettle();
    router.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const Key('dialog')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(const Key('dialog')), findsNothing);
  });

  testApp('with reduced motion the dialog goes at once', (tester) async {
    await pump(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final router = container.read(windowRouterProvider.notifier)
      ..open(const LoginRoute());
    await tester.pumpAndSettle();
    router.close();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('dialog')), findsNothing);
  });

  testApp('a dialog reopened during the exit fade (sign out → login) is a new, '
      'working dialog', (tester) async {
    await pump(tester);
    final router = container.read(windowRouterProvider.notifier);
    final answer = router.confirm(
      ConfirmRequest(title: 'Sign out?', body: 'b', confirmLabel: 'ok'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm.ok')));
    expect(await answer, isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    router.open(const LoginRoute());
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The confirm still fades out beside the new login dialog: two separate
    // dialogs, not one element shared between them.
    expect(find.byKey(const Key('dialog')), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
    expect(find.text('a@b.co'), findsOneWidget);
  });

  testApp('a confirm over a finished change-password keeps it finished', (
    tester,
  ) async {
    await pump(tester);
    await container
        .read(agentControllerProvider.notifier)
        .signIn(email: 'a@b.co', password: '12345678', register: false);
    final router = container.read(windowRouterProvider.notifier)
      ..open(const ChangePasswordRoute());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('password.new')),
      'long enough 1',
    );
    await tester.enterText(
      find.byKey(const Key('password.confirm')),
      'long enough 1',
    );
    await tester.tap(find.byKey(const Key('password.submit')));
    await tester.pumpAndSettle();
    final answer = router.confirm(
      ConfirmRequest(title: 't', body: 'b', confirmLabel: 'ok'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm.cancel')));
    expect(await answer, isFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('password.done')), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(router.current, isNull);
  });
}
