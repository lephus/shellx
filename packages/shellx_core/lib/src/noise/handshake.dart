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
    _symmetric.mixHash(prologue);
    _symmetric.mixHash(remoteStatic); // pre-message "<- s"
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
    _symmetric.mixHash(prologue);
    _symmetric.mixHash(localStatic.publicKey); // pre-message "<- s"
  }

  final NoisePattern _pattern;
  final bool _initiator;
  final NoiseKeyPair _s;
  final Uint8List? _psk;
  final NoiseKeyPair? _presetEphemeral;
  final NoiseSymmetricState _symmetric;
  Uint8List? _rs;
  NoiseKeyPair? _e;
  Uint8List? _re;

  /// 0 = before message 1, 1 = before message 2, 2 = complete.
  int _messageIndex = 0;
  bool _busy = false;
  bool _failed = false;

  bool get _pskMode => _pattern == NoisePattern.ikPsk2;

  bool get isComplete => _messageIndex == 2;

  /// Initiator: the key given to the constructor. Responder: set after
  /// reading message 1.
  Uint8List? get remoteStatic => _rs == null ? null : Uint8List.fromList(_rs!);

  Uint8List get handshakeHash => _symmetric.handshakeHash;

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

  /// Derives the transport keys. Throws [StateError] before completion.
  NoiseTransport split() {
    if (!isComplete) {
      throw StateError('Handshake not complete');
    }
    final (c1, c2) = _symmetric.split();
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
    _symmetric.mixKey(await dh(e, _rs!)); // es
    out.add(await _symmetric.encryptAndHash(_s.publicKey)); // s
    _symmetric.mixKey(await dh(_s, _rs!)); // ss
    out.add(await _symmetric.encryptAndHash(payload));
    return out.takeBytes();
  }

  Future<Uint8List> _readMessage1(Uint8List message) async {
    const encryptedStaticLength = dhLen + tagLen;
    if (message.length < dhLen + encryptedStaticLength + tagLen) {
      throw const NoiseException('Handshake message 1 too short');
    }
    _readE(Uint8List.sublistView(message, 0, dhLen));
    _symmetric.mixKey(await dh(_s, _re!)); // es
    final rs = await _symmetric.decryptAndHash(
      Uint8List.sublistView(message, dhLen, dhLen + encryptedStaticLength),
    );
    _rs = rs; // s
    _symmetric.mixKey(await dh(_s, rs)); // ss
    return _symmetric.decryptAndHash(
      Uint8List.sublistView(message, dhLen + encryptedStaticLength),
    );
  }

  // <- e, ee, se [, psk]
  Future<Uint8List> _writeMessage2(Uint8List payload) async {
    final e = await _ephemeral();
    final out = BytesBuilder(copy: false);
    _writeE(e, out);
    _symmetric.mixKey(await dh(e, _re!)); // ee
    _symmetric.mixKey(await dh(e, _rs!)); // se
    if (_pskMode) {
      _symmetric.mixKeyAndHash(_psk!); // psk
    }
    out.add(await _symmetric.encryptAndHash(payload));
    return out.takeBytes();
  }

  Future<Uint8List> _readMessage2(Uint8List message) async {
    if (message.length < dhLen + tagLen) {
      throw const NoiseException('Handshake message 2 too short');
    }
    _readE(Uint8List.sublistView(message, 0, dhLen));
    _symmetric.mixKey(await dh(_e!, _re!)); // ee
    _symmetric.mixKey(await dh(_s, _re!)); // se
    if (_pskMode) {
      _symmetric.mixKeyAndHash(_psk!); // psk
    }
    return _symmetric.decryptAndHash(Uint8List.sublistView(message, dhLen));
  }

  Future<NoiseKeyPair> _ephemeral() async {
    final e = _presetEphemeral ?? await NoiseKeyPair.generate();
    _e = e;
    return e;
  }

  void _writeE(NoiseKeyPair e, BytesBuilder out) {
    out.add(e.publicKey);
    _symmetric.mixHash(e.publicKey);
    if (_pskMode) {
      _symmetric.mixKey(e.publicKey);
    }
  }

  void _readE(Uint8List re) {
    final copy = Uint8List.fromList(re);
    _re = copy;
    _symmetric.mixHash(copy);
    if (_pskMode) {
      _symmetric.mixKey(copy);
    }
  }

  static Uint8List _checkedKey(Uint8List key, String name) {
    if (key.length != dhLen) {
      throw ArgumentError.value(key.length, name, 'must be 32 bytes');
    }
    return Uint8List.fromList(key);
  }

  static Uint8List? _checkedPsk(NoisePattern pattern, Uint8List? psk) {
    if (pattern == NoisePattern.ik) {
      if (psk != null) {
        throw ArgumentError.value(psk, 'psk', 'must be null for Noise_IK');
      }
      return null;
    }
    if (psk == null || psk.length != 32) {
      throw ArgumentError.value(psk, 'psk', 'Noise_IKpsk2 needs a 32-byte psk');
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
