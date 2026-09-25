import 'dart:async';

import 'package:shellx_mobile/features/lock/domain/biometric_authenticator.dart';

class FakeBiometricAuthenticator implements BiometricAuthenticator {
  bool available = true;
  bool result = true;
  BiometricKind kindValue = BiometricKind.faceId;
  int prompts = 0;
  String? lastReason;

  /// Set to make [kind] throw instead of returning [kindValue] (fix round 1: a detection
  /// failure must never freeze launch).
  Object? kindError;

  /// Set to make [authenticate] wait on this instead of resolving immediately, so a test can
  /// observe state while an authentication is still in progress.
  Completer<bool>? authenticateGate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<BiometricKind> kind() async {
    final error = kindError;
    if (error != null) throw error;
    return kindValue;
  }

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    lastReason = reason;
    final gate = authenticateGate;
    if (gate != null) return gate.future;
    return result;
  }
}
