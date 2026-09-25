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
  PairingOffer? _offer;

  /// Creates a new code, replacing any previous one.
  PairingOffer create({Duration ttl = const Duration(minutes: 5)}) {
    final secret = Uint8List(secretLength);
    for (var i = 0; i < secret.length; i++) {
      secret[i] = _random.nextInt(256);
    }
    return _offer = PairingOffer(secret: secret, expiresAt: _now().add(ttl));
  }

  /// The current code, or null when there is none or it has expired.
  Uint8List? get activeSecret {
    final offer = _offer;
    if (offer == null) return null;
    if (!_now().isBefore(offer.expiresAt)) {
      _offer = null;
      return null;
    }
    return offer.secret;
  }

  void invalidate() => _offer = null;
}
