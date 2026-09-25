import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

/// Polls [condition] every 20 ms until it holds or [timeout] passes.
Future<void> waitUntil(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Real WebSocket connector that keeps the latest socket so a test can cut
/// the connection, and can refuse new connections while [blocked].
final class DroppableConnector {
  RelaySocket? _socket;
  bool blocked = false;

  Future<RelaySocket> call(Uri uri, Map<String, String> headers) async {
    if (blocked) throw const SocketException('blocked by the e2e test');
    return _socket = await ioRelaySocketConnector(uri, headers);
  }

  /// Closes the current socket as if the network had dropped.
  Future<void> drop() async => _socket?.close(4000, 'e2e drop');
}

/// Real HTTP client that can hold `POST /v1/pairings` until [release], so
/// a test can reconnect the agent while the relay still keeps the
/// tombstone of an older pairing.
final class HoldablePairingPosts extends http.BaseClient {
  final _inner = http.Client();
  Completer<void>? _held;

  void hold() => _held ??= Completer<void>();

  void release() {
    _held?.complete();
    _held = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final held = _held;
    if (held != null &&
        request.method == 'POST' &&
        request.url.path == '/v1/pairings') {
      await held.future;
    }
    return _inner.send(request);
  }

  @override
  void close() {
    release();
    _inner.close();
  }
}

/// Collects the decoded text of a tab.
final class TabText {
  TabText(ClientTab tab) {
    tab.events.listen((event) {
      if (event is TabOutput) _buffer.write(event.text);
    });
  }
  final _buffer = StringBuffer();
  String get text => _buffer.toString();
}

/// `/bin/sh` without a login profile keeps the e2e output deterministic.
final class _PlainShell implements ShellResolver {
  const _PlainShell();
  @override
  Future<ShellCommand> resolve() async =>
      const ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh');
}

/// A phone logged into the test account.
final class E2ePhone {
  E2ePhone._(
    this.deviceId,
    this.api,
    this.relay,
    this.connector,
    this.pinned,
    this.service,
  );

  final String deviceId;
  final ShellxApi api;
  final RelayConnection relay;
  final DroppableConnector connector;
  final PinnedStore pinned;
  final ClientService service;

  /// Logs in, starts the [ClientService] and waits until it is connected.
  /// [onCreated] gets the service as soon as it exists, so the caller can
  /// stop it even when the wait fails.
  static Future<E2ePhone> login(
    Uri baseUri,
    String email,
    String password, {
    required String name,
    List<PinnedMachine> pins = const [],
    void Function(E2ePhone phone)? onCreated,
  }) async {
    final storage = InMemoryKeyValueStore();
    final identity = await DeviceIdentity.loadOrCreate(storage);
    final api = ShellxApi(baseUri: baseUri);
    final AuthResult auth;
    try {
      auth = await api.login(
        email,
        password,
        DeviceInfo(
          kind: DeviceKind.mobile,
          name: name,
          platform: DevicePlatform.android,
          publicKey: identity.publicKey,
        ),
      );
    } catch (_) {
      api.close();
      rethrow;
    }
    final pinned = PinnedStore(storage, userId: auth.userId);
    for (final pin in pins) {
      await pinned.add(pin);
    }
    final connector = DroppableConnector();
    final relay = RelayConnection(
      wsUri: wsUriFor(baseUri),
      token: () => api.token,
      connector: connector.call,
    );
    final service = ClientService(
      relay: relay,
      api: api,
      deviceId: auth.deviceId,
      userId: auth.userId,
      identity: identity,
      pinned: pinned,
      appVersion: '1.0.0',
      deviceName: name,
      platform: DevicePlatform.android,
    );
    final phone = E2ePhone._(
      auth.deviceId,
      api,
      relay,
      connector,
      pinned,
      service,
    );
    onCreated?.call(phone);
    await service.start();
    await waitUntil(
      () => relay.state == RelayConnectionState.connected,
      reason: '$name did not connect to the relay',
    );
    return phone;
  }

  Future<void> _dispose() async {
    await service.stop();
    api.close();
  }
}

Uri wsUriFor(Uri baseUri) => baseUri.replace(
  scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
  path: '/v1/ws',
);

/// A fresh account (unique random email; the dev relay has rate limits off)
/// with a real agent (dart:io processes) and two phones: the user's phone
/// and an intruder who knows the password but never scanned the QR code (it
/// pins the agent key it somehow learned).
final class E2eWorld {
  E2eWorld._();

  static const password = 'e2e-password-1234';

  late final String agentId;
  late final NoiseKeyPair agentKey;
  late final TrustedStore trusted;
  late final SessionManager sessions;
  late final AgentService agent;
  late final RelayConnection agentRelay;
  late final DroppableConnector agentConnector;

  /// The agent's HTTP client: holds its `POST /v1/pairings` on request.
  final agentHttp = HoldablePairingPosts();
  late final E2ePhone phone;
  late final E2ePhone intruder;

  /// Added to the agent's clock to expire pairing codes.
  Duration clockSkew = Duration.zero;

  ShellxApi? _agentApi;
  bool _agentStarted = false;
  bool _sessionsCreated = false;
  final _phones = <E2ePhone>[];
  bool _disposed = false;

  /// Everything is torn down again (account included) if a step fails.
  static Future<E2eWorld> create(Uri baseUri) async {
    final world = E2eWorld._();
    try {
      await world._build(baseUri);
    } catch (_) {
      await world.dispose();
      rethrow;
    }
    return world;
  }

  Future<void> _build(Uri baseUri) async {
    final random = Random.secure();
    final tag = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final email = 'e2e-$tag@example.com';

    final storage = InMemoryKeyValueStore();
    agentKey = await DeviceIdentity.loadOrCreate(storage);
    final api = _agentApi = ShellxApi(baseUri: baseUri, httpClient: agentHttp);
    final auth = await api.register(
      email,
      password,
      DeviceInfo(
        kind: DeviceKind.agent,
        name: 'e2e-agent',
        platform: DevicePlatform.macos,
        publicKey: agentKey.publicKey,
      ),
    );
    agentId = auth.deviceId;
    trusted = TrustedStore(storage);
    sessions = SessionManager(
      ptyFactory: const ProcessPtyFactory(),
      shellResolver: const _PlainShell(),
      homeDirectory: Directory.systemTemp.path,
      baseEnvironment: Platform.environment,
    );
    _sessionsCreated = true;
    agentConnector = DroppableConnector();
    agentRelay = RelayConnection(
      wsUri: wsUriFor(baseUri),
      token: () => api.token,
      connector: agentConnector.call,
    );
    agent = AgentService(
      relay: agentRelay,
      api: api,
      deviceId: auth.deviceId,
      identity: agentKey,
      trusted: trusted,
      sessions: sessions,
      pairing: PairingCodeManager(now: () => DateTime.now().add(clockSkew)),
      appVersion: '1.0.0',
    );
    _agentStarted = true;
    await agent.start();
    await waitUntil(
      () => agentRelay.state == RelayConnectionState.connected,
      reason: 'agent did not connect to the relay',
    );

    phone = await E2ePhone.login(
      baseUri,
      email,
      password,
      name: 'e2e-phone',
      onCreated: _phones.add,
    );
    intruder = await E2ePhone.login(
      baseUri,
      email,
      password,
      name: 'e2e-intruder',
      pins: [
        PinnedMachine(
          agentId: auth.deviceId,
          publicKey: agentKey.publicKey,
          pairedAt: DateTime.now().toUtc(),
        ),
      ],
      onCreated: _phones.add,
    );
  }

  /// Pairs [mobile] (the QR flow of spec §5.3) and returns the agent's new
  /// trust entry. With [registered], also waits until the relay has
  /// recorded the pairing (`POST /v1/pairings` landed): only a recorded
  /// pairing can be removed through the relay.
  Future<TrustedDevice> pair(E2ePhone mobile, {bool registered = true}) async {
    final paired = agent.events.firstWhere((e) => e is MobilePaired);
    await mobile.service.pair(agent.startPairing());
    final device =
        ((await paired.timeout(const Duration(seconds: 10))) as MobilePaired)
            .device;
    if (registered) {
      await waitUntil(
        () => isPairingRecorded(mobile),
        reason: 'the relay did not record the pairing',
      );
    }
    return device;
  }

  /// Whether the relay has a pairing between the agent and [phone]
  /// (`paired_with_me` in the phone's `GET /v1/devices`).
  Future<bool> isPairingRecorded(E2ePhone phone) async =>
      (await phone.api.devices()).any((d) => d.id == agentId && d.pairedWithMe);

  /// Stops everything and deletes the account (best effort). Safe to call
  /// on a partly built world, and more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    agentHttp.release();
    if (_sessionsCreated) sessions.closeAll();
    for (final phone in _phones) {
      await _quietly(phone._dispose);
    }
    if (_agentStarted) await _quietly(agent.stop);
    final api = _agentApi;
    if (api != null) {
      // Already gone when a test deleted the account (401): nothing to do.
      await _quietly(() => api.deleteAccount(password));
    }
    agentHttp.close();
  }

  static Future<void> _quietly(Future<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Best-effort cleanup: keep tearing down the rest.
    }
  }
}
