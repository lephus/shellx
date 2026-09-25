import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../session/session_manager.dart';
import '../trust/trusted_store.dart';
import 'agent_channel.dart';
import 'agent_events.dart';
import 'handshake_responder.dart';

/// The agent side of the relay protocol: answers handshakes, keeps at most
/// one encrypted channel per phone, routes app messages to [SessionManager]
/// and completes pairing.
///
/// [start] subscribes and calls `relay.start()`. [stop] drops every channel
/// and calls `relay.stop()`; it does not close sessions (call
/// `SessionManager.closeAll()` for that).
final class AgentService {
  AgentService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required NoiseKeyPair identity,
    required TrustedStore trusted,
    required SessionManager sessions,
    required PairingCodeManager pairing,
    required String appVersion,
    Duration flushInterval = const Duration(milliseconds: 16),
  }) : _relay = relay,
       _api = api,
       _deviceId = deviceId,
       _identity = identity,
       _trusted = trusted,
       _sessions = sessions,
       _pairing = pairing,
       _flushInterval = flushInterval,
       _responder = HandshakeResponder(
         deviceId: deviceId,
         identity: identity,
         appVersion: appVersion,
         trusted: trusted,
         pairing: pairing,
       );

  final RelayConnection _relay;
  final ShellxApi _api;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final TrustedStore _trusted;
  final SessionManager _sessions;
  final PairingCodeManager _pairing;
  final Duration _flushInterval;
  final HandshakeResponder _responder;

  final _events = StreamController<AgentEvent>.broadcast();
  final _channels = <String, AgentChannel>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _inbox = Future.value();
  bool _running = false;

  Stream<AgentEvent> get events => _events.stream;

  int get activeChannelCount => _channels.length;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _subscriptions
      ..add(_relay.frames.listen((frame) => _enqueue(() => _onFrame(frame))))
      ..add(
        _relay.states.listen(
          (state) => _enqueue(() async {
            if (state == RelayConnectionState.connected) return;
            _dropAllChannels();
            if (state == RelayConnectionState.revoked) {
              _events.add(const AgentRevoked());
            }
          }),
        ),
      )
      ..add(
        _sessions.outbound.listen(
          (out) => _channels[out.mobileId]?.enqueue(out.message),
        ),
      )
      ..add(
        _sessions.opened.listen(
          (event) => _events.add(
            SessionOpenedByMobile(
              mobileName: _channels[event.mobileId]?.name ?? event.mobileId,
              sessionId: event.sessionId,
            ),
          ),
        ),
      );
    _relay.start();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    for (final subscription in _subscriptions) {
      // Not awaited: cancel() may return a root-zone future.
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _dropAllChannels();
    await _relay.stop();
  }

  /// Creates a single-use pairing code and the QR URI that carries it.
  PairingUri startPairing() {
    final offer = _pairing.create();
    return PairingUri(
      agentDeviceId: _deviceId,
      agentPublicKey: _identity.publicKey,
      secret: offer.secret,
    );
  }

  /// The QR window was closed: the code stops working immediately.
  void cancelPairing() => _pairing.invalidate();

  /// Tray → "Paired devices" → Revoke (spec §5.5).
  Future<void> revoke(String mobileId) async {
    await _trusted.remove(mobileId);
    _sessions.closeSessionsAttachedTo(mobileId);
    _dropChannel(mobileId);
    try {
      await _api.deletePairing(_deviceId, mobileId);
    } on ApiException {
      // The server record is display-only; local trust is already gone.
    }
  }

  void _enqueue(Future<void> Function() task) {
    _inbox = _inbox
        .then((_) {
          if (!_running) return null;
          return task();
        })
        .catchError((Object _) {});
  }

  Future<void> _onFrame(RelayFrame frame) async {
    switch (frame) {
      case DataFrame():
        await _onData(frame);
      case PresenceFrame(:final deviceId, :final online):
        if (!online) _dropChannel(deviceId);
      case ErrorFrame(:final code, :final deviceId, :final channel):
        if (code == RelayErrorCode.peerOffline &&
            _channels[deviceId]?.channelId == channel) {
          _dropChannel(deviceId);
        }
      case EventFrame(:final event):
        await _onEvent(event);
    }
  }

  Future<void> _onData(DataFrame frame) async {
    final ChannelPayload payload;
    try {
      payload = ChannelPayload.decode(frame.payload);
    } on FrameFormatException {
      return;
    }
    switch (payload.kind) {
      case PayloadKind.hs1Ik || PayloadKind.hs1IkPsk2:
        await _onHello(frame, payload);
      case PayloadKind.transport:
        await _onTransport(frame, payload.noiseMessage);
      case PayloadKind.hs2:
        break; // The agent is always the responder.
    }
  }

  Future<void> _onHello(DataFrame frame, ChannelPayload payload) async {
    final mobileId = frame.peer;
    final answer = await _responder.answer(
      mobileId: mobileId,
      kind: payload.kind,
      message: payload.noiseMessage,
    );
    if (answer == null || !_running) return;
    _relay.send(
      DataFrame(peer: mobileId, channel: frame.channel, payload: answer.reply),
    );
    final transport = answer.transport;
    if (transport == null) return; // Status was not ok: no channel.
    // One channel per phone: a new accepted HS1 replaces the old channel.
    final previous = _channels.remove(mobileId);
    if (previous != null) {
      previous.close();
      _sessions.mobileDisconnected(mobileId);
    }
    _channels[mobileId] = AgentChannel(
      mobileId: mobileId,
      channelId: frame.channel,
      name: answer.hello.name,
      remoteStatic: answer.remoteStatic,
      secure: SecureChannel(transport),
      send: _relay.send,
      pairingSecret: answer.pairingSecret,
      flushInterval: _flushInterval,
    );
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  Future<void> _onTransport(DataFrame frame, Uint8List noiseMessage) async {
    final mobileId = frame.peer;
    final channel = _channels[mobileId];
    if (channel == null || channel.channelId != frame.channel) return;
    final List<AppMessage> messages;
    try {
      messages = await channel.open(noiseMessage);
    } catch (_) {
      _dropChannel(mobileId); // Any decrypt/decode error kills the channel.
      return;
    }
    for (final message in messages) {
      if (!identical(_channels[mobileId], channel)) return;
      if (channel.isPairing) {
        await _completePairing(channel, message);
        return;
      }
      if (message is PairConfirm) continue;
      await _sessions.handle(mobileId, message);
    }
  }

  /// Pairing succeeds only on a decrypted `pair.confirm` while the code used
  /// for the handshake is still the active one (spec §5.3 step 5).
  Future<void> _completePairing(
    AgentChannel channel,
    AppMessage message,
  ) async {
    _dropChannel(channel.mobileId); // A pairing channel carries one message.
    final active = _pairing.activeSecret;
    if (message is! PairConfirm ||
        active == null ||
        !constantTimeEquals(active, channel.pairingSecret!)) {
      return;
    }
    _pairing.invalidate();
    final device = TrustedDevice(
      mobileId: channel.mobileId,
      publicKey: channel.remoteStatic,
      name: channel.name,
      pairedAt: DateTime.now().toUtc(),
    );
    await _trusted.add(device);
    _events.add(MobilePaired(device));
    try {
      await _api.createPairing(channel.mobileId);
    } on ApiException {
      // Display-only record; the pairing is already effective locally.
    }
  }

  Future<void> _onEvent(Map<String, String> event) async {
    if (event['event'] != 'pairing_removed' || event['agent_id'] != _deviceId) {
      return;
    }
    final mobileId = event['mobile_id'];
    if (mobileId == null) return;
    await _trusted.remove(mobileId);
    _dropChannel(mobileId);
  }

  void _dropChannel(String mobileId) {
    final channel = _channels.remove(mobileId);
    if (channel == null) return;
    channel.close();
    _sessions.mobileDisconnected(mobileId);
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  void _dropAllChannels() {
    for (final mobileId in _channels.keys.toList()) {
      _dropChannel(mobileId);
    }
  }
}
