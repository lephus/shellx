import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// "Face ID", "Touch ID", "vân tay", "sinh trắc học" or "mã máy".
String biometricMethod(S strings, BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => strings.biometricFaceId,
  BiometricKind.touchId => strings.biometricTouchId,
  BiometricKind.fingerprint => strings.biometricFingerprint,
  BiometricKind.biometrics => strings.biometricGeneric,
  BiometricKind.passcode => strings.biometricPasscode,
};

IconData biometricIcon(BiometricKind kind) => switch (kind) {
  BiometricKind.faceId => Icons.face_outlined,
  BiometricKind.touchId || BiometricKind.fingerprint || BiometricKind.biometrics => Icons.fingerprint,
  BiometricKind.passcode => Icons.lock_outline,
};
