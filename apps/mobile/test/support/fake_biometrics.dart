import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  bool available = true;
  bool result = true;
  BiometricKind kindValue = BiometricKind.faceId;
  int prompts = 0;
  String? lastReason;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind> kind() async => kindValue;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    return result;
  }
}
