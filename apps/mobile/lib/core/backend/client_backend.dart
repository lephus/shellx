import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/auth/account_session.dart';
import 'package:shellx_mobile/core/backend/backend.dart';
import 'package:shellx_mobile/core/config/app_config.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';

/// Production [BackendFactory]: one [ClientBackend] per sign-in, sharing the app's single
/// [KeyValueStore] and [ShellxApi].
@LazySingleton(as: BackendFactory)
final class ClientBackendFactory implements BackendFactory {
  ClientBackendFactory(this._api, this._store, this._device, this._packageInfo);

  final ShellxApi _api;
  final KeyValueStore _store;
  final DeviceDescription _device;
  final PackageInfo _packageInfo;

  @override
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity) => ClientBackend.start(
    relayBaseUri: AppConfig.relayBaseUri,
    api: _api,
    userId: session.userId,
    deviceId: session.deviceId,
    identity: identity,
    store: _store,
    appVersion: _packageInfo.version,
    device: _device,
  );
}

/// Production [ShellxBackend]: one [RelayConnection] + one [ClientService]
/// per signed-in account.
final class ClientBackend implements ShellxBackend {
  ClientBackend._(this._relay, this._api, this._client, this._pinned);

  final RelayConnection _relay;
  final ShellxApi _api;
  final ClientService _client;
  final PinnedStore _pinned;
  final Map<String, _MachineSessionAdapter> _machines = {};
  bool _disposed = false;

  /// Builds the relay connection and client for a signed-in account and
  /// starts the client (plan 03: `ClientService.start()` loads the pins,
  /// subscribes and calls `relay.start()`; `stop()` calls `relay.stop()`).
  static Future<ClientBackend> start({
    required Uri relayBaseUri,
    required ShellxApi api,
    required String userId,
    required String deviceId,
    required NoiseKeyPair identity,
    required KeyValueStore store,
    required String appVersion,
    required DeviceDescription device,
    RelaySocketConnector connector = ioRelaySocketConnector,
  }) async {
    final relay = RelayConnection(
      wsUri: relayWebSocketUri(relayBaseUri),
      token: () => api.token,
      connector: connector,
    );
    final pinned = PinnedStore(store, userId: userId);
    final client = ClientService(
      relay: relay,
      api: api,
      deviceId: deviceId,
      userId: userId,
      identity: identity,
      pinned: pinned,
      appVersion: appVersion,
      deviceName: device.name,
      platform: device.platform,
    );
    await client.start();
    return ClientBackend._(relay, api, client, pinned);
  }

  @override
  RelayConnectionState get relayState => _relay.state;

  @override
  Stream<RelayConnectionState> get relayStates => _relay.states;

  @override
  void reconnectNow() => _relay.reconnectNow();

  /// A no-op after [dispose].
  @override
  Future<void> suspend() => _disposed ? Future.value() : _client.stop();

  /// `ClientService.start()` may run again after `stop()` and then restarts the relay; while the
  /// client is running (the relay `replaced` included) it returns at once. A no-op after [dispose]:
  /// the relay would dial with the shared [ShellxApi]'s token, which may be the next account's.
  @override
  Future<void> resume() => _disposed ? Future.value() : _client.start();

  @override
  Future<List<RemoteDevice>> devices() async {
    _checkNotDisposed();
    return _api.devices();
  }

  @override
  bool isOnline(String agentId) => _client.isOnline(agentId);

  @override
  Stream<PresenceFrame> get presence => _client.presence;

  @override
  Future<List<PinnedMachine>> pinnedMachines() => _pinned.list();

  @override
  Future<void> pair(PairingUri uri) async {
    _checkNotDisposed();
    return _client.pair(uri);
  }

  /// Asks [ClientService] every time, so a machine forgotten by an `untrusted` handshake or an
  /// unpair throws [StateError]; the session is kept while the [MachineClient] stays the same.
  @override
  MachineSession machine(String agentId) {
    final client = _client.machine(agentId);
    final session = _machines[agentId];
    if (session != null && identical(session._client, client)) return session;
    return _machines[agentId] = _MachineSessionAdapter(client);
  }

  /// `ClientService.unpair` shuts the machine down before its DELETE, which may still fail.
  @override
  Future<void> unpair(String agentId) async {
    _checkNotDisposed();
    _machines.remove(agentId);
    return _client.unpair(agentId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _client.stop();
  }

  /// REST after [dispose] would go out with the shared [ShellxApi]'s token.
  void _checkNotDisposed() {
    if (_disposed) throw StateError('The backend of a signed-out account');
  }
}

final class _MachineSessionAdapter implements MachineSession {
  _MachineSessionAdapter(this._client);

  final MachineClient _client;
  final Map<ClientTab, _TabAdapter> _tabs = Map.identity();

  TabHandle _wrap(ClientTab tab) => _tabs.putIfAbsent(tab, () => _TabAdapter(tab));

  @override
  String get agentId => _client.agentId;

  @override
  MachineConnectionState get state => _client.state;

  @override
  Stream<MachineConnectionState> get states => _client.states;

  @override
  Future<void> connect() => _client.connect();

  @override
  Future<List<SessionInfo>> listSessions() => _client.listSessions();

  @override
  Future<TabHandle> openSession({required int cols, required int rows}) async =>
      _wrap(await _client.openSession(cols: cols, rows: rows));

  @override
  Future<TabHandle> attach(int id, {required int cols, required int rows}) async =>
      _wrap(await _client.attach(id, cols: cols, rows: rows));

  @override
  List<TabHandle> get tabs => [for (final tab in _client.tabs) _wrap(tab)];

  @override
  void input(int id, Uint8List data) => _client.input(id, data);

  @override
  void resize(int id, int cols, int rows) => _client.resize(id, cols, rows);

  /// Drops the wrapper of the tab closed here only: a tab attached under the same id meanwhile
  /// keeps its handle.
  @override
  Future<void> closeTab(int id) async {
    final closing = _client.tabs.where((tab) => tab.id == id).firstOrNull;
    await _client.closeTab(id);
    if (closing != null) _tabs.remove(closing);
  }
}

final class _TabAdapter implements TabHandle {
  _TabAdapter(this._tab);

  final ClientTab _tab;

  @override
  int get id => _tab.id;

  @override
  int get index => _tab.index;

  @override
  String get shell => _tab.shell;

  @override
  bool get isAttached => _tab.isAttached;

  @override
  Stream<TabEvent> get events => _tab.events;
}
