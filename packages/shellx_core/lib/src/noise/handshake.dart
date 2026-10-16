// HandshakeState (Noise rev 34, §5.3) for exactly two patterns:
//
//   IK:                        IKpsk2:
//     <- s                       <- s
//     ...                        ...
//     -> e, es, s, ss            -> e, es, s, ss
//     <- e, ee, se               <- e, ee, se, psk
//
// In psk mode every `e` token also calls MixKey(e.public_key) (§9.2).
import 'dart:typed_data';

import 'noise_key_pair.dart';
import 'primitives.dart';
import 'symmetric_state.dart';

enum NoisePattern {
  ik('Noise_IK_25519_ChaChaPoly_BLAKE2s'),
  ikPsk2('Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s');

  const NoisePattern(this.protocolName);
  final String protocolName;
}

final class NoiseHandshake {
  NoiseHandshake.initiator({
    required NoisePattern pattern,
    required NoiseKeyPair localStatic,
    required Uint8List remoteStatic,
    required Uint8List prologue,
    Uint8List? psk,
    NoiseKeyPair? ephemeral,
  }) : _pattern = pattern,
       _initiator = true,
       _s = localStatic,
       _rs = _checkedKey(remoteStatic, 'remoteStatic'),
       _psk = _checkedPsk(pattern, psk),
       _presetEphemeral = ephemeral,
       _symmetric = NoiseSymmetricState(pattern.protocolName) {
    _symmetric!.mixHash(prologue);
    _symmetric!.mixHash(remoteStatic); // pre-message "<- s"
  }

  NoiseHandshake.responder({
    required NoisePattern pattern,
    required NoiseKeyPair localStatic,
    required Uint8List prologue,
    Uint8List? psk,
    NoiseKeyPair? ephemeral,
  }) : _pattern = pattern,
       _initiator = false,
       _s = localStatic,
       _psk = _checkedPsk(pattern, psk),
       _presetEphemeral = ephemeral,
       _symmetric = NoiseSymmetricState(pattern.protocolName) {
    _symmetric!.mixHash(prologue);
    _symmetric!.mixHash(localStatic.publicKey); // pre-message "<- s"
  }

  final NoisePattern _pattern;
  final bool _initiator;
  final NoiseKeyPair _s;
  Uint8List? _psk;
  NoiseKeyPair? _presetEphemeral;

  /// Null once [split] has run (Noise rev 34 §5.3: the HandshakeState,
  /// including its chaining key/hash, is discarded after Split so it cannot
  /// be reused to derive transport keys a second time).
  NoiseSymmetricState? _symmetric;
  Uint8List? _rs;
  NoiseKeyPair? _e;
  Uint8List? _re;
  Uint8List? _cachedHandshakeHash;

  /// 0 = before message 1, 1 = before message 2, 2 = complete.
  int _messageIndex = 0;
  bool _busy = false;
  bool _failed = false;
  bool _split = false;

  bool get _pskMode => _pattern == NoisePattern.ikPsk2;

  bool get isComplete => _messageIndex == 2;

  /// Initiator: the key given to the constructor. Responder: set after
  /// reading message 1 once `ss` and the payload tag have authenticated it.
  /// Null when the handshake has failed, even if a peer claimed a static key
  /// before authentication was checked.
  Uint8List? get remoteStatic =>
      _failed || _rs == null ? null : Uint8List.fromList(_rs!);

  Uint8List get handshakeHash =>
      _cachedHandshakeHash ?? _symmetric!.handshakeHash;

  /// Writes the next handshake message. Fails with [StateError] when it is
  /// not this side's turn or the handshake already failed.
  Future<Uint8List> writeMessage([Uint8List? payload]) async {
    _checkUsable();
    final ourTurn = _initiator ? _messageIndex == 0 : _messageIndex == 1;
    if (!ourTurn) {
      throw StateError('Not our turn to write');
    }
    final body = payload ?? Uint8List(0);
    return _run(() => _initiator ? _writeMessage1(body) : _writeMessage2(body));
  }

  /// Reads the next handshake message and returns its decrypted payload.
  /// Fails with [NoiseException] for truncated or unauthentic messages
  /// (after which the handshake is unusable) and with [StateError] when it
  /// is not this side's turn.
  Future<Uint8List> readMessage(Uint8List message) async {
    _checkUsable();
    final ourTurn = _initiator ? _messageIndex == 1 : _messageIndex == 0;
    if (!ourTurn) {
      throw StateError('Not our turn to read');
    }
    return _run(
      () => _initiator ? _readMessage2(message) : _readMessage1(message),
    );
  }

  /// Derives the transport keys. Throws [StateError] before completion or if
  /// called more than once: split() is one-shot, matching Noise rev 34 §5.3
  /// (Split discards the HandshakeState). A second call must not be allowed
  /// to re-derive the same keys from the same chaining key, which would
  /// produce two transports with identical keys starting at nonce 0.
  NoiseTransport split() {
    if (!isComplete) {
      throw StateError('Handshake not complete');
    }
    if (_split) {
      throw StateError('split() already called');
    }
    _split = true;
    final symmetric = _symmetric!;
    final (c1, c2) = symmetric.split();
    // Discard the handshake state now that the transport keys are derived:
    // nothing may read the ephemeral key, psk or symmetric state again.
    _cachedHandshakeHash = symmetric.handshakeHash;
    _symmetric = null;
    _e = null;
    _re = null;
    _psk = null;
    _presetEphemeral = null;
    return _initiator ? NoiseTransport._(c1, c2) : NoiseTransport._(c2, c1);
  }

  void _checkUsable() {
    if (_failed) {
      throw StateError('Handshake already failed');
    }
    if (_busy) {
      throw StateError('Handshake step already in progress');
    }
  }

  Future<Uint8List> _run(Future<Uint8List> Function() step) async {
    _busy = true;
    try {
      final result = await step();
      _messageIndex++;
      return result;
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  // -> e, es, s, ss
  Future<Uint8List> _writeMessage1(Uint8List payload) async {
    final e = await _ephemeral();
    final out = BytesBuilder(copy: false);
    _writeE(e, out);
    _symmetric!.mixKey(await dh(e, _rs!)); // es
    out.add(await _symmetric!.encryptAndHash(_s.publicKey)); // s
    _symmetric!.mixKey(await dh(_s, _rs!)); // ss
    out.add(await _symmetric!.encryptAndHash(payload));
    return out.takeBytes();
  }

  Future<Uint8List> _readMessage1(Uint8List message) async {
    const encryptedStaticLength = dhLen + tagLen;
    if (message.length < dhLen + encryptedStaticLength + tagLen) {
      throw const NoiseException('Handshake message 1 too short');
    }
    _readE(Uint8List.sublistView(message, 0, dhLen));
    _symmetric!.mixKey(await dh(_s, _re!)); // es
    final rs = await _symmetric!.decryptAndHash(
      Uint8List.sublistView(message, dhLen, dhLen + encryptedStaticLength),
    );
    _symmetric!.mixKey(await dh(_s, rs)); // ss
    final payload = await _symmetric!.decryptAndHash(
      Uint8List.sublistView(message, dhLen + encryptedStaticLength),
    );
    // Only trust `rs` as the peer's static key once `ss` and the payload
    // tag have authenticated it (Noise rev 34 §7.2): a peer who does not
    // hold the private key matching a claimed static key cannot compute the
    // same `ss` we just mixed in, so it cannot forge that tag. Assigning
    // `_rs` any earlier would let an unauthenticated, attacker-chosen key
    // leak through `remoteStatic` even though the message never verifies.
    _rs = rs; // s
    return payload;
  }

  // <- e, ee, se [, psk]
  Future<Uint8List> _writeMessage2(Uint8List payload) async {
    final e = await _ephemeral();
    final out = BytesBuilder(copy: false);
    _writeE(e, out);
    _symmetric!.mixKey(await dh(e, _re!)); // ee
    _symmetric!.mixKey(await dh(e, _rs!)); // se
    if (_pskMode) {
      _symmetric!.mixKeyAndHash(_psk!); // psk
    }
    out.add(await _symmetric!.encryptAndHash(payload));
    return out.takeBytes();
  }

  Future<Uint8List> _readMessage2(Uint8List message) async {
    if (message.length < dhLen + tagLen) {
      throw const NoiseException('Handshake message 2 too short');
    }
    _readE(Uint8List.sublistView(message, 0, dhLen));
    _symmetric!.mixKey(await dh(_e!, _re!)); // ee
    _symmetric!.mixKey(await dh(_s, _re!)); // se
    if (_pskMode) {
      _symmetric!.mixKeyAndHash(_psk!); // psk
    }
    return _symmetric!.decryptAndHash(Uint8List.sublistView(message, dhLen));
  }

  Future<NoiseKeyPair> _ephemeral() async {
    final e = _presetEphemeral ?? await NoiseKeyPair.generate();
    _e = e;
    return e;
  }

  void _writeE(NoiseKeyPair e, BytesBuilder out) {
    out.add(e.publicKey);
    _symmetric!.mixHash(e.publicKey);
    if (_pskMode) {
      _symmetric!.mixKey(e.publicKey);
    }
  }

  void _readE(Uint8List re) {
    final copy = Uint8List.fromList(re);
    _re = copy;
    _symmetric!.mixHash(copy);
    if (_pskMode) {
      _symmetric!.mixKey(copy);
    }
  }

  static Uint8List _checkedKey(Uint8List key, String name) {
    if (key.length != dhLen) {
      throw ArgumentError.value(key.length, name, 'must be 32 bytes');
    }
    return Uint8List.fromList(key);
  }

  static Uint8List? _checkedPsk(NoisePattern pattern, Uint8List? psk) {
    // ArgumentError.value keeps `invalidValue` around (for example in a
    // crash report), so pass the length instead of the psk bytes themselves
    // — the whole point of a pre-shared key is that it never leaks.
    if (pattern == NoisePattern.ik) {
      if (psk != null) {
        throw ArgumentError.value(
          psk.length,
          'psk',
          'must be null for Noise_IK',
        );
      }
      return null;
    }
    if (psk == null || psk.length != 32) {
      throw ArgumentError.value(
        psk?.length,
        'psk',
        'Noise_IKpsk2 needs a 32-byte psk',
      );
    }
    return Uint8List.fromList(psk);
  }
}

/// Transport cipher pair produced by [NoiseHandshake.split].
///
/// Calls are serialized: each [encrypt] (and each [decrypt]) completes in the
/// order it was called, so nonces always match the order of the results.
final class NoiseTransport {
  NoiseTransport._(this._send, this._receive);

  /// Largest plaintext for one Noise transport message (65535 - 16).
  static const int maxPlaintextLength = 65535 - tagLen;

  final NoiseCipherState _send;
  final NoiseCipherState _receive;
  Future<void> _sendQueue = Future.value();
  Future<void> _receiveQueue = Future.value();

  Future<Uint8List> encrypt(Uint8List plaintext) {
    if (plaintext.length > maxPlaintextLength) {
      throw ArgumentError.value(
        plaintext.length,
        'plaintext',
        'exceeds $maxPlaintextLength bytes',
      );
    }
    final result = _sendQueue.then(
      (_) => _send.encryptWithAd(const <int>[], plaintext),
    );
    _sendQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Throws [NoiseException] if authentication fails (tampering, replay,
  /// reordering or a wrong key).
  Future<Uint8List> decrypt(Uint8List ciphertext) {
    final result = _receiveQueue.then(
      (_) => _receive.decryptWithAd(const <int>[], ciphertext),
    );
    _receiveQueue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
