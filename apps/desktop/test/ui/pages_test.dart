import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_coordinator.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';

late TestHarness h;
late ProviderContainer container;
DateTime now = DateTime(2026, 9, 25, 12);

WindowRouter router() => container.read(windowRouterProvider.notifier);
AgentController agent() => container.read(agentControllerProvider.notifier);
AgentViewState agentState() => container.read(agentControllerProvider);

Future<void> pumpApp(
  WidgetTester tester,
  TestHarness harness, {
  Locale locale = const Locale('en'),
}) async {
  h = harness;
  now = DateTime(2026, 9, 25, 12);
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      clockProvider.overrideWithValue(() => now),
    ],
  );
  addTearDown(container.dispose);
  container.listen(
    agentControllerProvider,
    (prev, next) => coordinateWindows(prev, next, router()),
  );
  tester.view.physicalSize = const Size(520, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShellxDesktopApp(locale: locale),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('LoginPage', () {
    testWidgets('rejects an invalid email without calling the relay', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('login.email')),
        'not-an-email',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(h.relay.requests, isEmpty);
    });

    testWidgets('rejects a 7-character password', (tester) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '1234567',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Password must be 8–128 characters.'), findsOneWidget);
    });

    testWidgets('signs in and hands over to onboarding', (tester) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('login.email')),
        'Phu@Example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        'correct horse',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(h.relay.routes, contains('POST /v1/auth/login'));
      expect(agentState().phase, AuthPhase.signedIn);
      expect(
        container.read(windowRouterProvider).route,
        isA<OnboardingRoute>(),
      );
    });

    testWidgets('shows relay errors in Vietnamese', (tester) async {
      await pumpApp(
        tester,
        TestHarness(locale: const Locale('vi')),
        locale: const Locale('vi'),
      );
      h.relay.failures['POST /v1/auth/login'] = (401, 'invalid_credentials');
      router().open(const LoginRoute());
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);

      h.relay.failures['POST /v1/auth/login'] = (429, 'rate_limited');
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Thử lại sau ít phút.'), findsOneWidget);
    });

    testWidgets('register mode checks the confirmation and calls register', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const LoginRoute());
      await settle(tester);
      await tester.tap(find.byKey(const Key('login.toggle')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('login.email')), 'new@b.co');
      await tester.enterText(
        find.byKey(const Key('login.password')),
        '12345678',
      );
      await tester.enterText(
        find.byKey(const Key('login.confirm')),
        '12345679',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login.confirm')),
        '12345678',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await settle(tester);
      expect(h.relay.routes, contains('POST /v1/auth/register'));
    });

    testWidgets('after a 4002 the login window explains the sign-out', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      await settle(tester);
      h.runtime.emitRelay(RelayConnectionState.revoked);
      await settle(tester);
      expect(find.byKey(const Key('login.notice')), findsOneWidget);
      expect(find.text('You were signed out. Sign in again.'), findsOneWidget);
    });
  });

  group('OnboardingPage', () {
    testWidgets('macOS: Full Disk Access button opens the privacy pane', (
      tester,
    ) async {
      await pumpApp(tester, TestHarness());
      router().open(const OnboardingRoute());
      await settle(tester);
      await tester.tap(find.byKey(const Key('onboarding.fda')));
      await settle(tester);
      expect(h.urlOpener.opened.single, SystemUrlOpener.fullDiskAccessPane);
      expect(
        h.urlOpener.opened.single.toString(),
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      );
    });

    testWidgets('Windows: no Full Disk Access section', (tester) async {
      await pumpApp(tester, TestHarness(platform: DevicePlatform.windows));
      router().open(const OnboardingRoute());
      await settle(tester);
      expect(find.byKey(const Key('onboarding.fda')), findsNothing);
      expect(find.textContaining('system tray'), findsOneWidget);
    });

    testWidgets(
      'launch at startup is on by default; Finish applies it and hides',
      (tester) async {
        await pumpApp(tester, TestHarness());
        router().open(const OnboardingRoute());
        await settle(tester);
        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const Key('onboarding.launch')),
        );
        expect(toggle.value, isTrue);
        await tester.tap(find.byKey(const Key('onboarding.finish')));
        await settle(tester);
        expect(h.launchAtLogin.enabled, isTrue);
        expect(agentState().onboardingDone, isTrue);
        expect(container.read(windowRouterProvider).visible, isFalse);
      },
    );
  });

  group('PairingPage', () {
    Future<void> openPairing(WidgetTester tester) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      agent().startPairing();
      router().open(const PairingRoute());
      await settle(tester);
    }

    testWidgets('shows the QR and counts down to expiry', (tester) async {
      await openPairing(tester);
      expect(find.byKey(const Key('pairing.qr')), findsOneWidget);
      expect(find.text('Code expires in 5:00'), findsOneWidget);

      now = now.add(const Duration(minutes: 4, seconds: 59));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Code expires in 0:01'), findsOneWidget);
    });

    testWidgets('an expired code hides the QR and offers a new one', (
      tester,
    ) async {
      await openPairing(tester);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pairing.qr')), findsNothing);
      expect(find.byKey(const Key('pairing.expired')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pairing.new')));
      await tester.pump(const Duration(seconds: 1));
      expect(h.runtime.pairingStarts, 2);
      expect(find.byKey(const Key('pairing.qr')), findsOneWidget);
      expect(find.text('Code expires in 1:00'), findsOneWidget);
    });

    testWidgets('warns while the relay is not connected', (tester) async {
      await openPairing(tester);
      expect(find.byKey(const Key('pairing.offline')), findsOneWidget);
      h.runtime.emitRelay(RelayConnectionState.connected);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('pairing.offline')), findsNothing);
    });

    testWidgets('closes itself once the phone is paired', (tester) async {
      await openPairing(tester);
      h.runtime.eventController.add(MobilePaired(phone('m1', 'Pixel')));
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(windowRouterProvider).visible, isFalse);
      expect(find.byKey(const Key('pairing.qr')), findsNothing);
    });
  });

  group('ChangePasswordPage', () {
    Future<void> openChange(WidgetTester tester) async {
      await pumpApp(tester, TestHarness(settings: {'onboarding_done': true}));
      await agent().signIn(
        email: 'a@b.co',
        password: '12345678',
        register: false,
      );
      router().open(const ChangePasswordRoute());
      await settle(tester);
    }

    testWidgets('both fields must match and be 8–128 characters', (
      tester,
    ) async {
      await openChange(tester);
      await tester.enterText(find.byKey(const Key('password.new')), 'short');
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'short',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.text('Password must be 8–128 characters.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('password.new')),
        'long enough 1',
      );
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'long enough 2',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(h.relay.routes, isNot(contains('POST /v1/auth/password')));
    });

    testWidgets('success posts the new password and confirms', (tester) async {
      await openChange(tester);
      await tester.enterText(
        find.byKey(const Key('password.new')),
        'long enough 1',
      );
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'long enough 1',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(jsonDecode(h.relay.last('POST /v1/auth/password').body), {
        'new_password': 'long enough 1',
      });
      expect(find.byKey(const Key('password.done')), findsOneWidget);
      await tester.tap(find.byKey(const Key('password.close')));
      await settle(tester);
      expect(container.read(windowRouterProvider).visible, isFalse);
    });

    testWidgets('server-side weak_password is shown', (tester) async {
      await openChange(tester);
      h.relay.failures['POST /v1/auth/password'] = (400, 'weak_password');
      await tester.enterText(find.byKey(const Key('password.new')), 'aaaaaaaa');
      await tester.enterText(
        find.byKey(const Key('password.confirm')),
        'aaaaaaaa',
      );
      await tester.tap(find.byKey(const Key('password.submit')));
      await settle(tester);
      expect(find.byKey(const Key('password.error')), findsOneWidget);
    });
  });

  testWidgets('ConfirmPage answers the pending request', (tester) async {
    await pumpApp(tester, TestHarness());
    final answer = router().confirm(
      ConfirmRequest(title: 'Quit ShellX?', body: 'body', confirmLabel: 'Quit'),
    );
    await settle(tester);
    expect(find.text('Quit ShellX?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm.ok')));
    await settle(tester);
    expect(await answer, isTrue);
    expect(container.read(windowRouterProvider).visible, isFalse);
  });
}
