import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

/// Everything between dependency injection and the first route. Never throws, and waits on
/// nothing unbounded: the version check takes 5 s at most, the rest is local.
Future<void> prepareLaunch() async {
  // Spec §14: the version gate runs on every launch; an outdated app never starts the relay.
  final versionGate = getIt<VersionGate>();
  await versionGate.check();
  if (versionGate.requiredVersion.peek() == null) {
    try {
      await getIt<SessionHolder>().restore();
    } catch (error) {
      // A Keychain/Keystore read that fails: the app opens signed out, on the login page, and
      // still locks below.
      if (kDebugMode) debugPrint('restore error: ${error.runtimeType}');
    }
  }
  // Spec §5.6: locked when the app opens (if enabled).
  final lock = getIt<AppLockController>();
  try {
    // Detecting which method the device has must never block launch: the lock still engages
    // below with the signal's conservative default kind (BiometricKind.passcode).
    await lock.detectKind();
  } catch (error) {
    if (kDebugMode) debugPrint('detectKind error: ${error.runtimeType}');
  }
  lock.lockOnLaunch();
}
