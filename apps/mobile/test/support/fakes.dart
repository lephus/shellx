import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;

const String agentA = '11111111-1111-4111-8111-111111111111';
const String agentB = '22222222-2222-4222-8222-222222222222';

RemoteDevice agentDevice(
  String id,
  String name, {
  bool online = true,
  DateTime? lastSeenAt,
  DevicePlatform platform = DevicePlatform.macos,
}) => RemoteDevice(
  id: id,
  kind: DeviceKind.agent,
  name: name,
  platform: platform,
  online: online,
  lastSeenAt: lastSeenAt,
  pairedWithMe: false,
);

PinnedMachine pinned(String agentId) =>
    PinnedMachine(agentId: agentId, publicKey: Uint8List(32), pairedAt: DateTime(2026, 9, 25));

/// Like `ClientTab`: events emitted before the first listener are replayed to it, the tab is no
/// longer attached after [TabExited], [TabDetached] or [TabError], and closing it ends the stream.
/// Unlike it, events are delivered synchronously.
class FakeTabHandle implements TabHandle {
  FakeTabHandle({required this.id, required this.index, this.shell = 'zsh'});

  @override
  final int id;
  @override
  final int index;
  @override
  final String shell;
  bool attached = true;
  late final StreamController<TabEvent> _events = StreamController<TabEvent>.broadcast(
    sync: true,
    onListen: _replayBacklog,
  );
  final List<TabEvent> _backlog = [];
  bool _everListened = false;

  void emit(TabEvent event) {
    if (_events.isClosed) return;
    if (event is TabExited || event is TabDetached || event is TabError) attached = false;
    if (_everListened) {
      _events.add(event);
    } else {
      _backlog.add(event);
    }
  }

  /// What `MachineSession.closeTab` does to the tab.
  void close() {
    attached = false;
    unawaited(_events.close());
  }

  bool get isClosed => _events.isClosed;

  void _replayBacklog() {
    if (_everListened) return;
    _everListened = true;
    for (final event in _backlog) {
      _events.add(event);
    }
    _backlog.clear();
  }

  @override
  bool get isAttached => attached;

  @override
  Stream<TabEvent> get events => _events.stream;
}

/// Scriptable [MachineSession]. Unlike `shellx_client`, [input] and [resize] record every call
/// (the real client drops input without a channel and sizes below 1×1), so tests can check the
/// UI's own gating. [FakeBackend.unpair] shuts it down for good ([shutDown]).
class FakeMachineSession implements MachineSession {
  FakeMachineSession(this.agentId);

  @override
  final String agentId;
  MachineConnectionState stateValue = const MachineIdle();
  final StreamController<MachineConnectionState> _states = StreamController<MachineConnectionState>.broadcast(
    sync: true,
  );

  /// Makes [connect] fail like `MachineClient`: state [MachineFailed], then a thrown
  /// [MachineConnectionException]. `untrusted` also ends every attached tab with
  /// `TabError(sessionNotFound)` and calls [onUntrusted] (the pin is forgotten).
  MachineConnectionFailure? connectFailure;
  void Function()? onUntrusted;
  int connectCalls = 0;
  List<SessionInfo> sessions = [];
  int listCalls = 0;
  Object? openError;

  /// Thrown by [attach]; an [AppErrorException] also ends an existing tab of that id with
  /// [TabError], as the agent's `error` does in `shellx_client`.
  final Map<int, Object> attachErrors = {};

  /// The open tabs; closed and cleared by [shutDown].
  final List<FakeTabHandle> handles = [];
  final List<({int cols, int rows})> opened = [];
  final List<({int id, int cols, int rows})> attached = [];
  final List<({int id, Uint8List data})> inputs = [];
  final List<({int id, int cols, int rows})> resizes = [];
  final List<int> closed = [];

  /// Called inside [attach] once the tab is attached, before it returns (simulates catch-up
  /// output: `handle(id).emit(...)`).
  void Function(int id)? attachHook;

  /// Like shellx_client: re-attaching an existing tab returns the same handle.
  bool reuseHandles = false;
  int _nextId = 1;
  bool _shutDown = false;

  bool get isShutDown => _shutDown;

  /// What unpairing does to `MachineClient`, also when the DELETE then fails: the channel is
  /// dropped ([MachineReady] → [MachineIdle]), every tab is closed and removed, and the session is
  /// dead — [connect] and requests throw `MachineConnectionException(untrusted)` (no pin left).
  void shutDown() {
    _shutDown = true;
    for (final handle in handles) {
      handle.close();
    }
    handles.clear();
    if (stateValue is MachineReady) emitState(const MachineIdle());
  }

  /// A shut-down session fails every handshake like a machine without a pin.
  void _failIfShutDown() {
    if (!_shutDown) return;
    emitState(const MachineFailed(MachineConnectionFailure.untrusted));
    throw const MachineConnectionException(MachineConnectionFailure.untrusted);
  }

  /// Scripts a state change the real client makes on its own (channel lost → [MachineIdle],
  /// automatic resume → [MachineConnecting] / [MachineReady] / [MachineFailed]).
  void emitState(MachineConnectionState state) {
    stateValue = state;
    _states.add(state);
  }

  @override
  MachineConnectionState get state => stateValue;

  @override
  Stream<MachineConnectionState> get states => _states.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    _failIfShutDown();
    if (stateValue is MachineReady) return;
    emitState(const MachineConnecting());
    final failure = connectFailure;
    if (failure != null) {
      if (failure == MachineConnectionFailure.untrusted) {
        onUntrusted?.call();
        for (final handle in handles.where((h) => h.attached).toList()) {
          handle.emit(const TabError(AppErrorCode.sessionNotFound, 'This machine no longer trusts this phone'));
        }
      }
      emitState(MachineFailed(failure));
      throw MachineConnectionException(failure);
    }
    emitState(const MachineReady());
  }

  @override
  Future<List<SessionInfo>> listSessions() async {
    listCalls++;
    _failIfShutDown();
    return sessions;
  }

  @override
  Future<TabHandle> openSession({required int cols, required int rows}) async {
    opened.add((cols: cols, rows: rows));
    _failIfShutDown();
    final error = openError;
    if (error != null) throw error;
    final id = _nextId++;
    final handle = FakeTabHandle(id: 100 + id, index: id);
    handles.add(handle);
    return handle;
  }

  @override
  Future<TabHandle> attach(int id, {required int cols, required int rows}) async {
    attached.add((id: id, cols: cols, rows: rows));
    _failIfShutDown();
    final existing = handles.where((h) => h.id == id).firstOrNull;
    final error = attachErrors[id];
    if (error != null) {
      if (error is AppErrorException) existing?.emit(TabError(error.code, error.message));
      throw error;
    }
    final FakeTabHandle handle;
    if (reuseHandles && existing != null) {
      handle = existing..attached = true;
    } else {
      final info = sessions.where((s) => s.id == id).firstOrNull;
      handle = FakeTabHandle(id: id, index: info?.index ?? id, shell: info?.shell ?? 'zsh');
      handles
        ..removeWhere((h) => h.id == id)
        ..add(handle);
    }
    attachHook?.call(id);
    return handle;
  }

  @override
  List<TabHandle> get tabs => List<TabHandle>.of(handles);

  @override
  void input(int id, Uint8List data) => inputs.add((id: id, data: data));

  @override
  void resize(int id, int cols, int rows) => resizes.add((id: id, cols: cols, rows: rows));

  @override
  Future<void> closeTab(int id) async {
    closed.add(id);
    for (final handle in handles.where((h) => h.id == id).toList()) {
      handles.remove(handle);
      handle.close();
    }
  }

  FakeTabHandle handle(int id) => handles.firstWhere((h) => h.id == id);
}

/// Scriptable [ShellxBackend]. [unpair] (whether or not [unpairError] is set) and an `untrusted`
/// handshake behave like `shellx_client`. Known divergences from the real client:
/// - relay loss, [suspend] and [emitRelay] reach neither the machine states (real: a lost channel
///   moves [MachineReady] to [MachineIdle]; script it with [FakeMachineSession.emitState]) nor
///   presence (real: an offline frame for every online machine; use [emitPresence]);
/// - requests do not connect first, and `attach` of an unknown id succeeds (real:
///   `AppErrorException(sessionNotFound)`);
/// - [resume] emits `connected` even when not suspended;
/// - [dispose] only sets [disposed] (and counts [disposeCalls]);
/// - [pair] neither calls [devices] nor drops the machine's channel;
/// - after `untrusted`, pairing again gives a fresh session (real: the same session, still
///   [MachineFailed]);
/// - [FakeMachineSession.reuseHandles] is false by default (real: a re-attach always returns the
///   same tab);
/// - pins ([pinnedList]) and sessions ([machines]) are tracked separately: [addMachine] pins
///   nothing, and [machine] works for any added machine;
/// - every stream is synchronous.
class FakeBackend implements ShellxBackend {
  FakeBackend({List<RemoteDevice>? devices, List<PinnedMachine>? pinnedList})
    : deviceList = devices ?? [],
      pinnedList = pinnedList ?? [];

  List<RemoteDevice> deviceList;
  List<PinnedMachine> pinnedList;
  Object? devicesError;
  final Set<String> onlineIds = {};
  RelayConnectionState relayStateValue = RelayConnectionState.connected;
  final StreamController<RelayConnectionState> _relay = StreamController<RelayConnectionState>.broadcast(sync: true);
  final StreamController<PresenceFrame> _presence = StreamController<PresenceFrame>.broadcast(sync: true);
  final Map<String, FakeMachineSession> machines = {};

  /// Sessions forgotten by an `untrusted` handshake: `ClientService` keeps them until [unpair]
  /// shuts them down.
  final Map<String, FakeMachineSession> _untrusted = {};
  Object? pairError;

  /// Thrown by [unpair] after the machine is shut down and its pin dropped, like a DELETE that
  /// failed three times in `shellx_client`.
  Object? unpairError;
  final List<PairingUri> paired = [];
  final List<String> unpaired = [];
  int reconnectCalls = 0;
  int suspendCalls = 0;
  int resumeCalls = 0;
  int disposeCalls = 0;
  bool disposed = false;

  void emitRelay(RelayConnectionState state) {
    relayStateValue = state;
    _relay.add(state);
  }

  void emitPresence(String deviceId, {required bool online}) {
    online ? onlineIds.add(deviceId) : onlineIds.remove(deviceId);
    _presence.add(PresenceFrame(deviceId: deviceId, online: online));
  }

  /// The machine's session; an `untrusted` handshake forgets it, as `shellx_client` forgets the
  /// pin ([machine] then throws, [pinnedMachines] no longer lists it).
  FakeMachineSession addMachine(String agentId) => machines.putIfAbsent(
    agentId,
    () => FakeMachineSession(agentId)..onUntrusted = () => _forgetUntrusted(agentId),
  );

  void _forgetUntrusted(String agentId) {
    final session = machines[agentId];
    if (session != null) _untrusted[agentId] = session;
    _forget(agentId);
  }

  void _forget(String agentId) {
    pinnedList = pinnedList.where((m) => m.agentId != agentId).toList();
    machines.remove(agentId);
  }

  @override
  RelayConnectionState get relayState => relayStateValue;

  @override
  Stream<RelayConnectionState> get relayStates => _relay.stream;

  @override
  void reconnectNow() => reconnectCalls++;

  @override
  Future<void> suspend() async {
    suspendCalls++;
    emitRelay(RelayConnectionState.stopped);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    emitRelay(RelayConnectionState.connected);
  }

  @override
  Future<List<RemoteDevice>> devices() async {
    final error = devicesError;
    if (error != null) throw error;
    return deviceList;
  }

  @override
  bool isOnline(String agentId) => onlineIds.contains(agentId);

  @override
  Stream<PresenceFrame> get presence => _presence.stream;

  @override
  Future<List<PinnedMachine>> pinnedMachines() async => pinnedList;

  @override
  Future<void> pair(PairingUri uri) async {
    final error = pairError;
    if (error != null) throw error;
    paired.add(uri);
    final agentId = uri.agentDeviceId;
    pinnedList = [...pinnedList.where((m) => m.agentId != agentId), pinned(agentId)];
    addMachine(agentId);
  }

  @override
  MachineSession machine(String agentId) => machines[agentId] ?? (throw StateError('not pinned: $agentId'));

  @override
  Future<void> unpair(String agentId) async {
    unpaired.add(agentId);
    // Like `ClientService.unpair`: shut down and forgotten before the DELETE, which may fail.
    machines[agentId]?.shutDown();
    _untrusted.remove(agentId)?.shutDown();
    _forget(agentId);
    final error = unpairError;
    if (error != null) throw error;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
  }
}

/// Hands out a new [FakeBackend] per sign-in and records what it was asked for.
class FakeBackendFactory implements BackendFactory {
  FakeBackendFactory([FakeBackend Function()? build]) : _build = build ?? FakeBackend.new;

  final FakeBackend Function() _build;
  final List<FakeBackend> backends = [];
  final List<AccountSession> sessions = [];
  final List<NoiseKeyPair> identities = [];

  @override
  Future<ShellxBackend> create(AccountSession session, NoiseKeyPair identity) async {
    sessions.add(session);
    identities.add(identity);
    final backend = _build();
    backends.add(backend);
    return backend;
  }
}
