import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'fake_relay.dart';

/// Result of [TestMobile.handshake]. [status] is null when no HS2 arrived
/// within 5 s; [decryptFailed] is true when HS2 could not be decrypted.
final class HandshakeResult {
  const HandshakeResult({
    required this.channelId,
    this.status,
    this.channel,
    this.decryptFailed = false,
  });
  final ChannelId channelId;
  final HandshakeStatus? status;
  final MobileChannel? channel;
  final bool decryptFailed;
}

/// A scripted phone that speaks the channel protocol directly (Noise
/// initiator) so AgentService can be tested as a black box.
final class TestMobile {
  TestMobile({
    required FakeRelay relay,
    required this.device,
    required this.identity,
  }) : connection = RelayConnection(
         wsUri: relay.wsUri,
         token: () => device.token,
         connector: relay.connector,
         backoff: Backoff(random: Random(7)),
       );

  final FakeDevice device;
  final NoiseKeyPair identity;
  final RelayConnection connection;
  final _pendingHs2 = <ChannelId, Completer<Uint8List?>>{};
  final channels = <ChannelId, MobileChannel>{};
  final errors = <ErrorFrame>[];

  void start() {
    connection.frames.listen(_onFrame);
    connection.start();
  }

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case DataFrame(:final channel, :final payload):
        final decoded = ChannelPayload.decode(payload);
        if (decoded.kind == PayloadKind.hs2) {
          final pending = _pendingHs2.remove(channel);
          if (pending != null && !pending.isCompleted) {
            pending.complete(decoded.noiseMessage);
          }
        } else if (decoded.kind == PayloadKind.transport) {
          channels[channel]?._receive(decoded.noiseMessage);
        }
      case ErrorFrame():
        errors.add(frame);
      case PresenceFrame() || EventFrame():
        break;
    }
  }

  Future<HandshakeResult> handshake({
    required String agentId,
    required Uint8List agentKey,
    NoisePattern pattern = NoisePattern.ik,
    Uint8List? psk,
    int proto = kAppProtocolVersion,
    String name = 'Test Phone',
  }) async {
    final handshake = NoiseHandshake.initiator(
      pattern: pattern,
      localStatic: identity,
      remoteStatic: agentKey,
      prologue: buildPrologue(
        agentDeviceId: agentId,
        mobileDeviceId: device.id,
      ),
      psk: psk,
    );
    final hello = await handshake.writeMessage(
      Hs1Payload(
        proto: proto,
        app: '1.0.0',
        name: name,
        platform: DevicePlatform.ios,
      ).encode(),
    );
    final channelId = ChannelId.random();
    final reply = Completer<Uint8List?>();
    _pendingHs2[channelId] = reply;
    connection.send(
      DataFrame(
        peer: agentId,
        channel: channelId,
        payload: ChannelPayload(
          pattern == NoisePattern.ik
              ? PayloadKind.hs1Ik
              : PayloadKind.hs1IkPsk2,
          hello,
        ).encode(),
      ),
    );
    final message = await reply.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    _pendingHs2.remove(channelId);
    if (message == null) return HandshakeResult(channelId: channelId);
    final Hs2Payload answer;
    try {
      answer = Hs2Payload.decode(await handshake.readMessage(message));
    } on NoiseException {
      return HandshakeResult(channelId: channelId, decryptFailed: true);
    }
    MobileChannel? channel;
    if (answer.status == HandshakeStatus.ok) {
      channel = MobileChannel._(
        this,
        agentId,
        channelId,
        SecureChannel(handshake.split()),
      );
      channels[channelId] = channel;
    }
    return HandshakeResult(
      channelId: channelId,
      status: answer.status,
      channel: channel,
    );
  }
}

/// The phone end of an established channel.
final class MobileChannel {
  MobileChannel._(this._mobile, this.agentId, this.channelId, this._secure);

  final TestMobile _mobile;
  final String agentId;
  final ChannelId channelId;
  final SecureChannel _secure;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  /// Every decrypted TRANSPORT payload, in arrival order.
  final batches = <List<AppMessage>>[];

  List<AppMessage> get received => [for (final batch in batches) ...batch];

  List<T> messagesOf<T extends AppMessage>() =>
      received.whereType<T>().toList();

  Future<void> send(List<AppMessage> messages) {
    final result = _outbox.then((_) async {
      final payload = await _secure.seal(messages);
      _mobile.connection.send(
        DataFrame(peer: agentId, channel: channelId, payload: payload),
      );
    });
    _outbox = result;
    return result;
  }

  /// Sends [noiseMessage] as a TRANSPORT payload without encrypting it.
  void sendRaw(Uint8List noiseMessage) {
    _mobile.connection.send(
      DataFrame(
        peer: agentId,
        channel: channelId,
        payload: ChannelPayload(PayloadKind.transport, noiseMessage).encode(),
      ),
    );
  }

  void _receive(Uint8List noiseMessage) {
    _inbox = _inbox
        .then((_) async {
          batches.add(await _secure.open(noiseMessage));
        })
        .catchError((Object _) {});
  }
}
