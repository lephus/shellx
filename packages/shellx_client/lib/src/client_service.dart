import 'dart:async';

import 'package:shellx_core/shellx_core.dart';

import 'machine_client.dart';
import 'pinned_store.dart';

/// The phone side of the relay protocol: presence and one [MachineClient]
/// per pinned machine.
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

  final RelayConnection _relay;
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

  Stream<PresenceFrame> get presence => _presence.stream;

  bool isOnline(String agentId) => _online.contains(agentId);

  Future<void> start() async {
    if (_subscriptions.isNotEmpty) return;
    for (final machine in await _pinned.list()) {
      _pins[machine.agentId] = machine;
    }
    _subscriptions
      ..add(_relay.frames.listen(_onFrame))
      ..add(_relay.states.listen(_onState));
    _relay.start();
  }

  Future<void> stop() async {
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
        _machines[deviceId]?.handleFrame(frame);
      case DataFrame(:final peer):
        _machines[peer]?.handleFrame(frame);
      case ErrorFrame(:final deviceId):
        _machines[deviceId]?.handleFrame(frame);
      case EventFrame():
        break;
    }
  }

  void _onState(RelayConnectionState state) {
    final connected = state == RelayConnectionState.connected;
    if (connected == _connected) return;
    _connected = connected;
    if (connected) return;
    for (final deviceId in _online.toList()) {
      _presence.add(PresenceFrame(deviceId: deviceId, online: false));
    }
    _online.clear();
    for (final machine in _machines.values) {
      machine.relayLost();
    }
  }
}
