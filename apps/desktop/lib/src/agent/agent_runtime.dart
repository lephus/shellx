import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../config.dart';

/// Pairing codes live 5 minutes (spec §5.3); PairingCodeManager's default TTL.
const Duration kPairingTtl = Duration(minutes: 5);

final class AgentCredentials {
  const AgentCredentials({
    required this.token,
    required this.deviceId,
    required this.userId,
    required this.email,
  });

  final String token;
  final String deviceId;
  final String userId;
  final String email;
}

final class PairingView {
  const PairingView({required this.uri, required this.expiresAt});

  final PairingUri uri;
  final DateTime expiresAt;
}

/// Everything that exists only while signed in with remote access on: the
/// relay link, AgentService and SessionManager. The controller talks to this
/// seam so its tests do not depend on shellx_agent internals.
abstract interface class AgentRuntime {
  /// Starts AgentService, which calls `relay.start()`.
  Future<void> start();

  /// Closes every session, stops AgentService and disconnects from the relay.
  ///
  /// Once it completes the relay is `stopped` and nothing more is emitted
  /// (no `AgentRevoked`), so `api.logout()` can follow. The shells are told
  /// to die but not awaited: `Pty.kill()` returns nothing to wait for.
  Future<void> stop();

  RelayConnectionState get relayState;
  Stream<RelayConnectionState> get relayStates;
  Stream<AgentEvent> get events;
  List<SessionSummary> get sessions;
  Stream<void> get sessionChanges;

  PairingView startPairing();
  void cancelPairing();
  Future<void> revoke(String mobileId);
  void closeSession(int id);
  void closeAllSessions();

  /// While `disconnected`: retries now instead of after the backoff (the
  /// computer woke up). While `replaced` (4001: another instance of this
  /// agent connected): connects again — the relay never does that on its
  /// own (spec §12), so call it in that state only for an explicit user
  /// action (tray "Reconnect"), never automatically. Does nothing before
  /// [start], after [stop], after a 4002 close, or while connecting or
  /// connected.
  void reconnectNow();
}

final class RuntimeParams {
  const RuntimeParams({
    required this.credentials,
    required this.identity,
    required this.trusted,
    required this.api,
  });

  final AgentCredentials credentials;
  final NoiseKeyPair identity;
  final TrustedStore trusted;
  final ShellxApi api;
}

typedef AgentRuntimeFactory = AgentRuntime Function(RuntimeParams params);

/// Production [AgentRuntime] wiring shellx_core + shellx_agent.
final class CoreAgentRuntime implements AgentRuntime {
  CoreAgentRuntime(
    RuntimeParams params, {
    required Uri relayBaseUri,
    required String appVersion,
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    RelaySocketConnector connector = ioRelaySocketConnector,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    final token = params.credentials.token;
    _relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => token,
      connector: connector,
    );
    _sessions = SessionManager(
      ptyFactory: ptyFactory,
      shellResolver: shellResolver,
      homeDirectory: homeDirectory,
      baseEnvironment: baseEnvironment,
    );
    _pairing = PairingCodeManager(now: _now);
    _service = AgentService(
      relay: _relay,
      api: params.api,
      deviceId: params.credentials.deviceId,
      identity: params.identity,
      trusted: params.trusted,
      sessions: _sessions,
      pairing: _pairing,
      appVersion: appVersion,
      clock: _now,
    );
  }

  final DateTime Function() _now;
  late final RelayConnection _relay;
  late final SessionManager _sessions;
  late final PairingCodeManager _pairing;
  late final AgentService _service;

  /// Between [start] and [stop]. A new RelayConnection reports
  /// `disconnected`, so [reconnectNow] checks this first: a relay dialled
  /// before [start] would have no AgentService listening to it.
  bool _running = false;

  /// Exposed for tests.
  PairingCodeManager get pairingCodes => _pairing;

  @override
  Future<void> start() {
    _running = true;
    return _service.start();
  }

  /// AgentService.stop() drops the channels and stops the relay but leaves
  /// sessions alone, so they are closed here first (plan 03 contract).
  @override
  Future<void> stop() async {
    _running = false;
    _sessions.closeAll();
    await _service.stop();
  }

  @override
  RelayConnectionState get relayState => _relay.state;
  @override
  Stream<RelayConnectionState> get relayStates => _relay.states;
  @override
  Stream<AgentEvent> get events => _service.events;
  @override
  List<SessionSummary> get sessions => _sessions.sessions;
  @override
  Stream<void> get sessionChanges => _sessions.changes;

  @override
  PairingView startPairing() {
    final expiresAt = _now().add(kPairingTtl);
    return PairingView(uri: _service.startPairing(), expiresAt: expiresAt);
  }

  @override
  void cancelPairing() => _service.cancelPairing();
  @override
  Future<void> revoke(String mobileId) => _service.revoke(mobileId);
  @override
  void closeSession(int id) => _sessions.closeSession(id);
  @override
  void closeAllSessions() => _sessions.closeAll();

  /// RelayConnection.reconnectNow() acts only while disconnected; after a
  /// 4001 close `relay.start()` is what connects again (AgentService is
  /// still subscribed to the relay, so it sees the new connection).
  @override
  void reconnectNow() {
    if (!_running) return;
    switch (_relay.state) {
      case RelayConnectionState.disconnected:
        _relay.reconnectNow();
      case RelayConnectionState.replaced:
        _relay.start();
      case RelayConnectionState.connecting ||
          RelayConnectionState.connected ||
          RelayConnectionState.revoked ||
          RelayConnectionState.stopped:
        break;
    }
  }
}
