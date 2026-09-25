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
}
