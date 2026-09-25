import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';
import 'machine_client.dart';
import 'pinned_store.dart';

/// The phone side of the relay protocol: presence, pairing (Noise IKpsk2
/// initiator) and one [MachineClient] per pinned machine.
///
/// [start] loads the pinned machines, subscribes and calls `relay.start()`;
/// [stop] calls `relay.stop()`.
final class ClientService {
  ClientService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required String userId,
    required NoiseKeyPair identity,
    required PinnedStore pinned,
    required String appVersion,
    required String deviceName,
    required DevicePlatform platform,
    Duration handshakeTimeout = const Duration(seconds: 10),
  }) : _relay = relay,
       _api = api,
       _deviceId = deviceId,
       _identity = identity,
       _pinned = pinned,
       _timeout = handshakeTimeout,
       _hello = Hs1Payload(
         proto: kAppProtocolVersion,
         app: appVersion,
         name: deviceName,
         platform: platform,
       );

  /// Waits before the second and third attempt of unpair's DELETE.
  static const _unpairRetryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];

  final RelayConnection _relay;
  final ShellxApi _api;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final PinnedStore _pinned;
  final Duration _timeout;
  final Hs1Payload _hello;

  final _pins = <String, PinnedMachine>{};
  final _machines = <String, MachineClient>{};
  final _online = <String>{};
  final _presence = StreamController<PresenceFrame>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _connected = false;

  /// Pairing handshakes in flight, by channel: the HS2 each one waits for.
  final _pairings =
      <ChannelId, ({String agentId, Completer<Uint8List> reply})>{};

  /// The start in flight, if any.
  Future<void>? _starting;

  /// Bumped by [stop] so a start still loading the pins gives up.
  int _generation = 0;

  Stream<PresenceFrame> get presence => _presence.stream;

  bool isOnline(String agentId) => _online.contains(agentId);

  /// Re-entrant: a call while a start is in flight joins it, and a [stop]
  /// made meanwhile wins (the pending start then subscribes to nothing).
  Future<void> start() {
    if (_subscriptions.isNotEmpty) return Future.value();
    final pending = _starting;
    if (pending != null) return pending;
    late final Future<void> starting;
    starting = _start(_generation).whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
    return _starting = starting;
  }

  Future<void> _start(int generation) async {
    final pinned = await _pinned.list();
    if (generation != _generation) return; // stop() ran meanwhile.
    for (final machine in pinned) {
      _pins[machine.agentId] = machine;
    }
    _subscriptions
      ..add(_relay.frames.listen(_onFrame))
      ..add(_relay.states.listen(_onState));
    _relay.start();
  }

  Future<void> stop() async {
    _generation++;
    _starting = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel()); // May return a root-zone future.
    }
    _subscriptions.clear();
    _onState(RelayConnectionState.stopped);
    await _relay.stop();
  }

  /// The client for a pinned machine; the same instance per [agentId].
  /// Throws [StateError] when the machine is not pinned (call [start] first).
  MachineClient machine(String agentId) {
    if (!_pins.containsKey(agentId)) {
      throw StateError('Machine $agentId is not paired with this phone');
    }
    return _machines[agentId] ??= MachineClient(
      agentId: agentId,
      relay: _relay,
      deviceId: _deviceId,
      identity: _identity,
      hello: _hello,
      timeout: _timeout,
      pinnedKey: () => _pins[agentId]?.publicKey,
      forgetPin: () => _forget(agentId),
    );
  }

  /// Pairs with the machine of a scanned QR (spec §5.3 steps 3–6): Noise
  /// IKpsk2 with the QR's agent key and the one-time code as PSK, then
  /// `pair.confirm` on that channel, then the pin. Throws
  /// [PairingException]; an [ApiException] from `GET /v1/devices`
  /// propagates.
  Future<void> pair(PairingUri uri) async {
    final agentId = uri.agentDeviceId;
    final devices = await _api.devices();
    if (!devices.any((d) => d.id == agentId && d.kind == DeviceKind.agent)) {
      throw const PairingException(PairingFailure.notInAccount);
    }
    if (uri.secret.length != 32 || uri.agentPublicKey.length != 32) {
      throw const PairingException(PairingFailure.invalidOrExpired);
    }
    final handshake = NoiseHandshake.initiator(
      pattern: NoisePattern.ikPsk2,
      localStatic: _identity,
      remoteStatic: uri.agentPublicKey,
      prologue: buildPrologue(
        agentDeviceId: agentId,
        mobileDeviceId: _deviceId,
      ),
      psk: uri.secret,
    );
    final hello = await handshake.writeMessage(_hello.encode());
    final channel = ChannelId.random();
    final reply = Completer<Uint8List>();
    _pairings[channel] = (agentId: agentId, reply: reply);
    try {
      _sendPairing(
        agentId,
        channel,
        ChannelPayload(PayloadKind.hs1IkPsk2, hello).encode(),
      );
      final Uint8List message;
      try {
        // Fails early with agentOffline or timeout when the way is lost.
        message = await reply.future.timeout(_timeout);
      } on TimeoutException {
        throw const PairingException(PairingFailure.timeout);
      }
      // One channel per phone: an HS1 the agent accepted replaced this
      // phone's channel, and a wrong code's HS2 cannot say whether it did.
      _machines[agentId]?.dropChannel();
      final Uint8List plaintext;
      try {
        plaintext = await handshake.readMessage(message);
      } catch (_) {
        // Wrong, expired or used code: HS2 cannot be decrypted (spec §5.3).
        throw const PairingException(PairingFailure.invalidOrExpired);
      }
      final Hs2Payload answer;
      try {
        answer = Hs2Payload.decode(plaintext);
      } catch (_) {
        throw const PairingException(PairingFailure.protocolUnsupported);
      }
      if (answer.proto != kAppProtocolVersion ||
          answer.status == HandshakeStatus.protoUnsupported) {
        throw const PairingException(PairingFailure.protocolUnsupported);
      }
      if (answer.status != HandshakeStatus.ok) {
        throw const PairingException(PairingFailure.invalidOrExpired);
      }
      final secure = SecureChannel(handshake.split());
      _sendPairing(agentId, channel, await secure.seal(const [PairConfirm()]));
      final pin = PinnedMachine(
        agentId: agentId,
        publicKey: Uint8List.fromList(uri.agentPublicKey),
        pairedAt: DateTime.now().toUtc(),
      );
      await _pinned.add(pin);
      _pins[agentId] = pin;
    } finally {
      _pairings.remove(channel);
    }
  }

  /// Sends one DATA frame of a pairing handshake; relay down → `timeout`.
  void _sendPairing(String agentId, ChannelId channel, Uint8List payload) {
    final sent = _relay.send(
      DataFrame(peer: agentId, channel: channel, payload: payload),
    );
    if (!sent) throw const PairingException(PairingFailure.timeout);
  }

  /// Ends the pairing handshakes still waiting for an HS2 from [agentId]
  /// (from any agent when null) with [failure].
  void _abortPairings(PairingFailure failure, {String? agentId}) {
    for (final pairing in _pairings.values) {
      if (agentId != null && pairing.agentId != agentId) continue;
      if (!pairing.reply.isCompleted) {
        pairing.reply.completeError(PairingException(failure));
      }
    }
  }

  /// Settings → unpair (spec §5.5): drops the machine's channel and tabs
  /// (its sessions keep running), forgets the pin, then deletes the pairing
  /// record without a pairing id — the hub tells the agent. The DELETE is
  /// the only way the agent learns of it, so a 5xx or network error is
  /// retried (3 attempts in all) before it propagates; other errors
  /// propagate at once.
  Future<void> unpair(String agentId) async {
    _machines.remove(agentId)?.shutdown();
    await _forget(agentId);
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.deletePairing(agentId, _deviceId);
        return;
      } on ApiException catch (error) {
        final retry = error.status == 0 || error.status >= 500;
        if (!retry || attempt == _unpairRetryDelays.length) rethrow;
      }
      await Future<void>.delayed(_unpairRetryDelays[attempt]);
    }
  }

  Future<void> _forget(String agentId) async {
    _pins.remove(agentId);
    await _pinned.remove(agentId);
  }

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case PresenceFrame(:final deviceId, :final online):
        if (online) {
          _online.add(deviceId);
        } else {
          _online.remove(deviceId);
        }
        _presence.add(frame);
        if (!online) {
          _abortPairings(PairingFailure.agentOffline, agentId: deviceId);
        }
        _machines[deviceId]?.handleFrame(frame);
      case DataFrame(:final peer, :final channel, :final payload):
        final pairing = _pairings[channel];
        if (pairing != null && pairing.agentId == peer) {
          try {
            final decoded = ChannelPayload.decode(payload);
            if (decoded.kind == PayloadKind.hs2 && !pairing.reply.isCompleted) {
              pairing.reply.complete(decoded.noiseMessage);
            }
          } on FrameFormatException {
            // Garbage on the pairing channel: keep waiting for HS2.
          }
          return;
        }
        _machines[peer]?.handleFrame(frame);
      case ErrorFrame(:final code, :final deviceId, :final channel):
        final pairing = _pairings[channel];
        if (pairing != null && pairing.agentId == deviceId) {
          if (code == RelayErrorCode.peerOffline &&
              !pairing.reply.isCompleted) {
            pairing.reply.completeError(
              const PairingException(PairingFailure.agentOffline),
            );
          }
          return;
        }
        _machines[deviceId]?.handleFrame(frame);
      case EventFrame(:final event):
        _onEvent(event);
    }
  }

  /// `pairing_removed` for this phone may name an older pairing than the
  /// one the agent trusts now (the phone does not know pairing ids), so the
  /// pin stays. A live channel to that machine is dropped instead: the next
  /// handshake asks the agent, and only an `untrusted` answer forgets the
  /// pin (spec §12). The relay can only take trust away.
  void _onEvent(Map<String, String> event) {
    if (event['event'] != 'pairing_removed' ||
        event['mobile_id'] != _deviceId) {
      return;
    }
    final agentId = event['agent_id'];
    if (agentId != null) _machines[agentId]?.dropChannel();
  }

  void _onState(RelayConnectionState state) {
    final connected = state == RelayConnectionState.connected;
    if (connected == _connected) return;
    _connected = connected;
    if (connected) return;
    _abortPairings(PairingFailure.timeout); // Relay down.
    for (final deviceId in _online.toList()) {
      _presence.add(PresenceFrame(deviceId: deviceId, online: false));
    }
    _online.clear();
    for (final machine in _machines.values) {
      machine.relayLost();
    }
  }
}
