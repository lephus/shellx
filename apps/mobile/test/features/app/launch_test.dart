import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/app/launch.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

import '../../support/fake_biometrics.dart';
import '../../support/fake_relay_http.dart';
import '../../support/fakes.dart';

void main() {
  late FakeRelayHttp relay;
  late FakeBiometricAuthenticator auth;
  late FakeSessionHolder session;
  late AppLockController lock;

  setUp(() {
    relay = FakeRelayHttp();
    auth = FakeBiometricAuthenticator();
    session = FakeSessionHolder();
    lock = AppLockController(authenticator: auth, isEnabled: () => true);
    final api = ShellxApi(baseUri: Uri.parse('http://127.0.0.1:8787'), httpClient: relay.client);
    final packageInfo = PackageInfo(
      appName: 'ShellX',
      packageName: 'com.shellx.prod',
      version: '1.0.0',
      buildNumber: '1',
    );
    getIt
      ..registerSingleton<VersionGate>(VersionGate(api, packageInfo))
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<AppLockController>(lock);
  });

  tearDown(() => getIt.reset());

  test('a fake authenticator whose kind() throws never blocks launch', () async {
    auth.kindError = const LocalAuthException(code: LocalAuthExceptionCode.uiUnavailable);

    // Must complete instead of propagating the authenticator's error.
    await prepareLaunch();

    expect(lock.isLocked.value, isTrue);
  });

  test('a current app restores the saved session, then locks', () async {
    await prepareLaunch();

    expect(session.restoreCalls, 1);
    expect(lock.isLocked.value, isTrue);
  });

  test('an outdated app never restores the session (the relay is not started)', () async {
    relay.minMobile = '2.0.0';

    await prepareLaunch();

    expect(getIt<VersionGate>().requiredVersion.value, '2.0.0');
    expect(session.restoreCalls, 0);
    expect(lock.isLocked.value, isTrue);
  });

  test('R4: a keychain error while restoring still locks the app and lands signed out', () async {
    session.restoreError = PlatformException(code: 'keychain');

    // Must complete instead of propagating the storage error.
    await prepareLaunch();

    expect(session.restoreCalls, 1);
    expect(session.isAuthenticated.value, isFalse);
    expect(lock.isLocked.value, isTrue);
  });
}
