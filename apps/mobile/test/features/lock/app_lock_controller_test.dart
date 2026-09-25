import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

import '../../support/fake_biometrics.dart';

void main() {
  late FakeBiometricAuthenticator auth;
  late DateTime now;
  late bool enabled;

  AppLockController controller() => AppLockController(
    authenticator: auth,
    isEnabled: () => enabled,
    now: () => now,
  );

  setUp(() {
    auth = FakeBiometricAuthenticator();
    now = DateTime(2026, 9, 25, 9);
    enabled = true;
  });

  test('locks on launch when enabled, not when disabled', () {
    final lock = controller()..lockOnLaunch();
    expect(lock.isLocked.value, isTrue);
    enabled = false;
    expect((controller()..lockOnLaunch()).isLocked.value, isFalse);
  });

  test('exactly 5 minutes in the background does not lock; more than 5 does', () {
    final lock = controller();
    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);

    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 5, seconds: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isTrue);
  });

  test('a resume without a preceding pause never locks', () {
    final lock = controller();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);
  });

  test('does not lock after a long background when the setting is off', () {
    enabled = false;
    final lock = controller()..onBackgrounded();
    now = now.add(const Duration(hours: 1));
    lock.onForegrounded();
    expect(lock.isLocked.value, isFalse);
  });

  test('unlock succeeds only when authentication succeeds', () async {
    final lock = controller()..lockOnLaunch();
    auth.result = false;
    expect(await lock.unlock('Unlock ShellX'), isFalse);
    expect(lock.isLocked.value, isTrue);
    auth.result = true;
    expect(await lock.unlock('Unlock ShellX'), isTrue);
    expect(lock.isLocked.value, isFalse);
    expect(auth.lastReason, 'Unlock ShellX');
  });

  test('a device without passcode or biometrics unlocks without prompting', () async {
    auth.available = false;
    final lock = controller()..lockOnLaunch();
    expect(await lock.unlock('reason'), isTrue);
    expect(auth.prompts, 0);
  });

  test('turning the setting off unlocks', () {
    final lock = controller()..lockOnLaunch();
    enabled = false;
    lock.settingChanged();
    expect(lock.isLocked.value, isFalse);
  });
}
