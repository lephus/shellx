import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../trust/trusted_store.dart';

/// Outcome of answering one HS1.
final class HandshakeAnswer {
  const HandshakeAnswer({
    required this.reply,
    required this.status,
    required this.hello,
    required this.remoteStatic,
    required this.transport,
    required this.pairingSecret,
  });

  /// Encoded `ChannelPayload(hs2, …)` — the DATA payload to send back.
  final Uint8List reply;
  final HandshakeStatus status;
  final Hs1Payload hello;
  final Uint8List remoteStatic;

  /// Transport keys; non-null only when [status] is ok.
  final NoiseTransport? transport;

  /// PSK of an accepted pairing handshake; null otherwise.
  final Uint8List? pairingSecret;
}

/// Noise responder for HS1_IK / HS1_IKPSK2 (spec §5.3, §5.4, §6.3).
final class HandshakeResponder {
  HandshakeResponder({
    required String deviceId,
    required NoiseKeyPair identity,
    required String appVersion,
    required TrustedStore trusted,
    required PairingCodeManager pairing,
    Random? random,
  }) : _deviceId = deviceId,
       _identity = identity,
       _appVersion = appVersion,
       _trusted = trusted,
       _pairing = pairing,
       _random = random ?? Random.secure();

  final String _deviceId;
  final NoiseKeyPair _identity;
  final String _appVersion;
  final TrustedStore _trusted;
  final PairingCodeManager _pairing;
  final Random _random;

  /// Returns null when message 1 cannot be decrypted or decoded: nothing
  /// can be answered (wrong agent key, prologue mismatch, garbage).
  Future<HandshakeAnswer?> answer({
    required String mobileId,
    required PayloadKind kind,
    required Uint8List message,
  }) async {
    final NoisePattern pattern;
    Uint8List? psk;
    Uint8List? activeSecret;
    switch (kind) {
      case PayloadKind.hs1Ik:
        pattern = NoisePattern.ik;
      case PayloadKind.hs1IkPsk2:
        pattern = NoisePattern.ikPsk2;
        activeSecret = _pairing.activeSecret;
        // No active code: answer with a random PSK so the phone cannot even
        // decrypt HS2, and never accept the pairing.
        psk = activeSecret ?? _randomBytes(32);
      case PayloadKind.hs2 || PayloadKind.transport:
        return null;
    }
    final handshake = NoiseHandshake.responder(
      pattern: pattern,
      localStatic: _identity,
      prologue: buildPrologue(
        agentDeviceId: _deviceId,
        mobileDeviceId: mobileId,
      ),
      psk: psk,
    );
    final Hs1Payload hello;
    try {
      hello = Hs1Payload.decode(await handshake.readMessage(message));
    } catch (_) {
      return null; // Undecryptable or malformed HS1: nothing to answer.
    }
    final remoteStatic = handshake.remoteStatic!;
    final HandshakeStatus status;
    if (hello.proto != kAppProtocolVersion) {
      status = HandshakeStatus.protoUnsupported;
    } else if (pattern == NoisePattern.ikPsk2) {
      status = activeSecret == null
          ? HandshakeStatus.pairingInvalid
          : HandshakeStatus.ok;
    } else {
      // Trust binds the relay peer id AND the static key proven by Noise.
      final device = await _trusted.find(mobileId);
      status =
          device != null && constantTimeEquals(device.publicKey, remoteStatic)
          ? HandshakeStatus.ok
          : HandshakeStatus.untrusted;
    }
    final reply = await handshake.writeMessage(
      Hs2Payload(
        proto: kAppProtocolVersion,
        app: _appVersion,
        status: status,
      ).encode(),
    );
    final ok = status == HandshakeStatus.ok;
    return HandshakeAnswer(
      reply: ChannelPayload(PayloadKind.hs2, reply).encode(),
      status: status,
      hello: hello,
      remoteStatic: remoteStatic,
      transport: ok ? handshake.split() : null,
      pairingSecret: ok && pattern == NoisePattern.ikPsk2 ? psk : null,
    );
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
