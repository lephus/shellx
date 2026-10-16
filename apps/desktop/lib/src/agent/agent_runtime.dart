import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../config.dart';
import 'session_core.dart';

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
/// relay link, AgentService, the router and the desktop-terminal sharing.
/// The shell sessions are not here (A1 D7, [SessionCore]). The controller
/// talks to this seam so its tests do not depend on shellx_agent internals.
abstract interface class AgentRuntime {
  /// Starts AgentService, which calls `relay.start()`.
  Future<void> start();

  /// Disconnects every phone (`closed_by_host`), stops AgentService and
  /// disconnects from the relay. The shell sessions keep running (A1 D7):
  /// they belong to [SessionCore]; only Quit closes them.
  ///
  /// Takes effect when called (synchronously): the relay is `stopped` and
  /// nothing more is emitted (no `AgentRevoked`). The future completes once
  /// the socket is closed and an upgrade still in flight has settled
  /// (RelayConnection.stop, bounded), so `api.logout()` and a new runtime's
  /// relay link can follow.
  Future<void> stop();

  RelayConnectionState get relayState;
  Stream<RelayConnectionState> get relayStates;
  Stream<AgentEvent> get events;

  /// Desktop terminals (and shell sessions, through the router) changed.
  Stream<void> get sessionChanges;

  PairingView startPairing();
  void cancelPairing();
  Future<void> revoke(String mobileId);

  /// Terminals shared through `shellx-term` (spec §7.6); empty while
  /// terminal sharing is off. [sessionChanges] also fires for them.
  List<DesktopSessionSummary> get desktopSessions;

  /// A phone attached to a desktop terminal (for the notification).
  Stream<DesktopPhoneAttached> get desktopPhoneAttached;

  /// Whether the local server for `shellx-term` runs.
  bool get terminalSharing;

  /// Starts or stops the local server (writes / deletes `endpoint`).
  /// Starting throws when the port cannot be opened (spec §7.9) or this
  /// runtime was built without an endpoint path. Stopping drops every
  /// desktop session at once; the windows keep running.
  Future<void> setTerminalSharing(bool enabled);

  /// Tray "Disconnect phone": the phone leaves; the terminal keeps running.
  void disconnectDesktopPhone(int id);

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

/// What push notifications need from the app (push spec §7). Every getter is
/// read when a notification is built.
final class PushNotificationsSetup {
  const PushNotificationsSetup({
    required this.threshold,
    required this.machineName,
    required this.locale,
    this.hooksDirectory,
  });

  /// "Thông báo khi lệnh chạy lâu xong", read live from the settings; null =
  /// off.
  final Duration? Function() threshold;

  /// The agent's device name (the first part of every title).
  final String Function() machineName;

  /// The computer's language (`Platform.localeName`).
  final String Function() locale;

  /// Where the shell hooks of ShellX sessions are written (spec §4.4); null
  /// starts shells without them (no command notifications in sessions).
  final String? hooksDirectory;
}

/// Production [AgentRuntime] wiring shellx_core + shellx_agent.
final class CoreAgentRuntime implements AgentRuntime {
  CoreAgentRuntime(
    RuntimeParams params, {
    required SessionCore core,
    required Uri relayBaseUri,
    required String appVersion,
    String? termEndpointPath,
    RelaySocketConnector connector = ioRelaySocketConnector,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _core = core {
    final token = params.credentials.token;
    _relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => token,
      connector: connector,
    );
    _desktopSessions = DesktopSessionManager(
      nextId: core.ids,
      notifications: core.notifications,
    );
    _sharing = termEndpointPath == null
        ? null
        : TerminalSharing(
            endpointPath: termEndpointPath,
            sessions: _desktopSessions,
          );
    _router = SessionRouter(
      shells: core.sessions,
      desktop: _desktopSessions,
      desktopSharing: () => _sharing?.enabled ?? false,
      ai: core.ai,
      tools: core.tools,
    );
    _pairing = PairingCodeManager(now: _now);
    _service = AgentService(
      relay: _relay,
      api: params.api,
      deviceId: params.credentials.deviceId,
      identity: params.identity,
      trusted: params.trusted,
      sessions: _router,
      pairing: _pairing,
      appVersion: appVersion,
      clock: _now,
    );
  }

  final DateTime Function() _now;
  final SessionCore _core;
  late final RelayConnection _relay;
  late final DesktopSessionManager _desktopSessions;
  late final TerminalSharing? _sharing;
  late final SessionRouter _router;
  late final PairingCodeManager _pairing;
  late final AgentService _service;

  /// Between [start] and [stop]. A new RelayConnection reports
  /// `disconnected`, so [reconnectNow] checks this first: a relay dialled
  /// before [start] would have no AgentService listening to it.
  bool _running = false;

  /// Exposed for tests.
  PairingCodeManager get pairingCodes => _pairing;

  /// Exposed for tests: null without [PushNotificationsSetup].
  AgentNotifications? get notifications => _core.notifications;

  /// A phone opening a channel (the count goes up) or pairing may just have
  /// allowed notifications: the sender's pause after an unheard one ends.
  @visibleForTesting
  void onAgentEvent(AgentEvent event) {
    switch (event) {
      case ActiveChannelsChanged(:final count):
        if (count > _channels) _core.notifications?.phoneConnected();
        _channels = count;
      case MobilePaired():
        _core.notifications?.phoneConnected();
      case SessionOpenedByMobile() || AgentRevoked():
        break;
    }
  }

  int _channels = 0;
  StreamSubscription<AgentEvent>? _eventWatch;

  /// Exposed for tests: the ShellX sessions (the core's).
  SessionManager get shellSessions => _core.sessions;

  @override
  Future<void> start() {
    _running = true;
    if (_core.notifications != null) {
      _eventWatch ??= _service.events.listen(onAgentEvent);
    }
    return _service.start();
  }

  /// AgentService.stop() drops the channels and stops the relay; first
  /// every phone is told `closed_by_host` and let go. No shell is killed
  /// (A1 D7). Desktop terminals only lose their phones (spec §7.2); the
  /// local server closes and `endpoint` goes, the windows keep running and
  /// retrying. The router is disposed last so the shell sessions stop
  /// forwarding into it.
  @override
  Future<void> stop() async {
    _running = false;
    unawaited(_eventWatch?.cancel());
    _eventWatch = null;
    _router.disconnectAllPhones();
    final stopping = _service.stop();
    try {
      await _sharing?.stop();
    } catch (_) {
      // Best effort: the windows keep running either way.
    }
    try {
      await stopping;
    } finally {
      _router.dispose();
    }
  }

  @override
  RelayConnectionState get relayState => _relay.state;
  @override
  Stream<RelayConnectionState> get relayStates => _relay.states;
  @override
  Stream<AgentEvent> get events => _service.events;
  @override
  Stream<void> get sessionChanges => _router.changes;
  @override
  List<DesktopSessionSummary> get desktopSessions => _desktopSessions.sessions;
  @override
  Stream<DesktopPhoneAttached> get desktopPhoneAttached =>
      _desktopSessions.phoneAttached;
  @override
  bool get terminalSharing => _sharing?.enabled ?? false;

  @override
  Future<void> setTerminalSharing(bool enabled) async {
    final sharing = _sharing;
    if (sharing == null) {
      if (enabled) throw StateError('terminal sharing is not available');
      return;
    }
    await (enabled ? sharing.start() : sharing.stop());
  }

  @override
  void disconnectDesktopPhone(int id) => _desktopSessions.disconnectPhone(id);

  @override
  PairingView startPairing() {
    final expiresAt = _now().add(kPairingTtl);
    return PairingView(uri: _service.startPairing(), expiresAt: expiresAt);
  }

  @override
  void cancelPairing() => _service.cancelPairing();
  @override
  Future<void> revoke(String mobileId) => _service.revoke(mobileId);

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
