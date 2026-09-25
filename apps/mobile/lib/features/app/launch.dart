import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/presentation/app_lock_controller.dart';

/// Everything between dependency injection and the first route.
Future<void> prepareLaunch() async {
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
