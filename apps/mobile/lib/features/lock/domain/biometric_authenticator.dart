import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';

/// What the lock asks for; names the unlock button ("Mở khóa bằng Face ID") and the setting.
enum BiometricKind { faceId, touchId, fingerprint, biometrics, passcode }

/// Face ID / fingerprint / device passcode (spec §5.6).
abstract interface class BiometricAuthenticator {
  /// False when the device has no passcode and no biometrics enrolled.
  Future<bool> isAvailable();

  Future<BiometricKind> kind();

  /// True when the user proved their identity.
  Future<bool> authenticate(String reason);
}

@LazySingleton(as: BiometricAuthenticator)
final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      // A detection failure (PlatformException, LocalAuthException, …) must never lock the
      // user out of their own app: treat it as "cannot authenticate", which unlock() bypasses.
      return false;
    }
  }

  @override
  Future<BiometricKind> kind() async {
    final List<BiometricType> types;
    try {
      types = await _auth.getAvailableBiometrics();
    } catch (_) {
      // local_auth_android throws LocalAuthException(uiUnavailable) instead of returning an
      // empty list when no Activity is available yet; any detection failure falls back the
      // same way an empty list would, and must never freeze the launch sequence.
      return BiometricKind.passcode;
    }
    if (Platform.isIOS) {
      if (types.contains(BiometricType.face)) return BiometricKind.faceId;
      if (types.contains(BiometricType.fingerprint)) return BiometricKind.touchId;
      return BiometricKind.passcode;
    }
    // Android usually reports only strong/weak classes.
    if (types.contains(BiometricType.fingerprint)) return BiometricKind.fingerprint;
    return types.isEmpty ? BiometricKind.passcode : BiometricKind.biometrics;
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly: false → the device passcode is accepted ("mã máy").
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException catch (error) {
      // The passcode was removed after the lock was enabled: nothing can be
      // verified any more, so do not lock the user out of their own app.
      return error.code == LocalAuthExceptionCode.noCredentialsSet;
    } catch (_) {
      // Any other failure (PlatformException, no Activity yet, …) fails closed:
      // the app stays locked and the lock screen's button retries.
      return false;
    }
  }
}
