import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';
import 'package:shellx_mobile/features/lock/presentation/lock_gate.dart';

import '../../support/app_harness.dart';
import '../../support/fake_biometrics.dart';

void main() {
  late FakeBiometricAuthenticator auth;
  late DateTime now;
  late AppLockController lock;
  late int backgrounds;
  late int foregrounds;

  Widget app() => localized(
    const Scaffold(body: Text('secret terminal')),
    builder: (context, child) => LockGate(
      lock: lock,
      onBackground: () => backgrounds++,
      onForeground: () => foregrounds++,
      child: child!,
    ),
  );

  Future<void> goToBackground(WidgetTester tester) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> comeBack(WidgetTester tester) async {
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  setUp(() async {
    auth = FakeBiometricAuthenticator()..result = false;
    now = DateTime(2026, 9, 25, 9);
    lock = AppLockController(authenticator: auth, isEnabled: () => true, now: () => now);
    await lock.detectKind();
    backgrounds = 0;
    foregrounds = 0;
  });

  testWidgets('shows the lock screen on launch and prompts immediately', (tester) async {
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.text('ShellX đang khóa'), findsOneWidget);
    expect(find.text('Mở khóa để xem các máy và phiên terminal của bạn.'), findsOneWidget);
    expect(auth.prompts, 1);
    expect(auth.lastReason, 'Mở khóa ShellX');

    auth.result = true;
    await tester.tap(find.text('Mở khóa bằng Face ID'));
    await tester.pump();
    expect(find.text('ShellX đang khóa'), findsNothing);
    expect(find.text('secret terminal'), findsOneWidget);
  });

  testWidgets('relocks after more than 5 minutes in the background and reports both transitions', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('ShellX đang khóa'), findsNothing);

    await goToBackground(tester);
    now = now.add(const Duration(minutes: 6));
    await comeBack(tester);
    await tester.pump();

    expect(backgrounds, 1);
    expect(foregrounds, 1);
    expect(find.text('ShellX đang khóa'), findsOneWidget);
  });

  testWidgets('the button names the method the device has', (tester) async {
    auth.kindValue = BiometricKind.fingerprint;
    await lock.detectKind();
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('Mở khóa bằng vân tay'), findsOneWidget);
  });

  testWidgets('taps on the content beneath the lock overlay do nothing while locked', (tester) async {
    var taps = 0;
    lock.lockOnLaunch();
    await tester.pumpWidget(
      localized(
        Scaffold(
          body: Center(
            child: TextButton(onPressed: () => taps++, child: const Text('secret button')),
          ),
        ),
        builder: (context, child) => LockGate(lock: lock, child: child!),
      ),
    );
    await tester.pump();

    // The button is still in the tree (painted below the overlay) but must not be hittable.
    await tester.tap(find.text('secret button'), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });

  testWidgets('an error from the system prompt keeps the lock screen up and the button retries', (tester) async {
    auth.authenticateError = StateError('no activity');
    lock.lockOnLaunch();
    await tester.pumpWidget(app());
    await tester.pump();
    expect(auth.prompts, 1);
    expect(find.text('ShellX đang khóa'), findsOneWidget);

    auth.authenticateError = null;
    auth.result = true;
    await tester.tap(find.text('Mở khóa bằng Face ID'));
    await tester.pump();
    expect(auth.prompts, 2);
    expect(find.text('ShellX đang khóa'), findsNothing);
  });

  group('privacy cover in the app switcher', () {
    testWidgets('shown while inactive or hidden, gone again on resume', (tester) async {
      await tester.pumpWidget(app());
      expect(find.byType(PrivacyCover), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsNothing);
      expect(find.text('ShellX đang khóa'), findsNothing);
    });

    testWidgets('after a long background the lock screen replaces the cover', (tester) async {
      await tester.pumpWidget(app());
      await goToBackground(tester);
      expect(find.byType(PrivacyCover), findsOneWidget);

      now = now.add(const Duration(minutes: 6));
      await comeBack(tester);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsNothing);
      expect(find.text('ShellX đang khóa'), findsOneWidget);
    });

    testWidgets('not shown when the biometric lock is off', (tester) async {
      lock = AppLockController(authenticator: auth, isEnabled: () => false, now: () => now);
      await tester.pumpWidget(app());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });
  });

  group('system back while locked', () {
    Widget routed() => routedApp(
      open: () => const PageRouteInfo('HiddenRoute'),
      routes: [stubRoute('HiddenRoute')],
      builder: (context, child) => LockGate(lock: lock, child: child!),
    );

    testWidgets('is consumed, so the routes hidden under the lock never pop', (tester) async {
      await tester.pumpWidget(routed());
      await tester.pumpAndSettle();
      await openPushed(tester);
      expect(find.text('HiddenRoute stub'), findsOneWidget);

      lock.lockOnLaunch();
      await tester.pump();
      await tester.pump();
      expect(find.text('ShellX đang khóa'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('HiddenRoute stub'), findsOneWidget);
      expect(find.text('ShellX đang khóa'), findsOneWidget);
    });

    testWidgets('pops normally while unlocked', (tester) async {
      await tester.pumpWidget(routed());
      await tester.pumpAndSettle();
      await openPushed(tester);
      expect(find.text('HiddenRoute stub'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('HiddenRoute stub'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}
