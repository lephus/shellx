import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/launch.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

import '../../support/fake_biometrics.dart';

void main() {
  tearDown(() => getIt.reset());

  test('a fake authenticator whose kind() throws never blocks launch', () async {
    final auth = FakeBiometricAuthenticator()
      ..kindError = const LocalAuthException(code: LocalAuthExceptionCode.uiUnavailable);
    final lock = AppLockController(authenticator: auth, isEnabled: () => true);
    getIt.registerSingleton<AppLockController>(lock);

    // Must complete instead of propagating the authenticator's error.
    await prepareLaunch();

    expect(lock.isLocked.value, isTrue);
  });
}
