import 'dart:math';
import 'dart:typed_data';

/// A pairing code shown in the QR window.
final class PairingOffer {
  const PairingOffer({required this.secret, required this.expiresAt});
  final Uint8List secret;
  final DateTime expiresAt;
}

/// Holds at most one single-use pairing code (spec §5.3 step 1):
/// 32 random bytes, valid for 5 minutes or until invalidated.
final class PairingCodeManager {
  PairingCodeManager({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  static const int secretLength = 32;

  final DateTime Function() _now;
  final Random _random;
  Uint8List? _secret;
  DateTime? _expiresAt;

  /// Creates a new code, replacing any previous one.
  PairingOffer create({Duration ttl = const Duration(minutes: 5)}) {
    final secret = Uint8List(secretLength);
    for (var i = 0; i < secret.length; i++) {
      secret[i] = _random.nextInt(256);
    }
    final expiresAt = _now().add(ttl);
    // Store a copy internally to prevent caller mutations from corrupting the live code.
    _secret = Uint8List.fromList(secret);
    _expiresAt = expiresAt;
    // Return a PairingOffer with a copy of the secret.
    return PairingOffer(
      secret: Uint8List.fromList(secret),
      expiresAt: expiresAt,
    );
  }

  /// The current code, or null when there is none or it has expired.
  Uint8List? get activeSecret {
    final secret = _secret;
    final expiresAt = _expiresAt;
    if (secret == null || expiresAt == null) return null;
    if (!_now().isBefore(expiresAt)) {
      _secret = null;
      _expiresAt = null;
      return null;
    }
    // Return a fresh copy each time to prevent caller mutations.
    return Uint8List.fromList(secret);
  }

  void invalidate() {
    _secret = null;
    _expiresAt = null;
  }
}
