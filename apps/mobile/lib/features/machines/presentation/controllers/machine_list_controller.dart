import 'dart:async';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// Spec §9.2 #2: agents from `GET /v1/devices`, kept live with PRESENCE.
@injectable
class MachineListController extends Controller {
  MachineListController({
    required ShellxBackend backend,
    WorkspaceRegistry? registry,
    Future<void> Function()? onReconnectReplaced,
    DateTime Function()? now,
  }) : _backend = backend,
       _registry = registry,
       _onReconnectReplaced = onReconnectReplaced,
       _now = now ?? DateTime.now {
    _relayState = signal(backend.relayState);
    _presence = backend.presence.listen(_onPresence);
    _relay = backend.relayStates.listen((relayState) {
      if (_disposed) return;
      _relayState.value = relayState;
      // Presence may have been missed while disconnected: the REST snapshot catches it up.
      if (relayState == RelayConnectionState.connected) unawaited(refresh());
    });
  }

  @factoryMethod
  static MachineListController create(SessionHolder session, WorkspaceRegistry registry) => MachineListController(
    backend: session.requireBackend,
    registry: registry,
    onReconnectReplaced: session.reconnectReplaced,
  );

  final ShellxBackend _backend;
  final WorkspaceRegistry? _registry;
  final Future<void> Function()? _onReconnectReplaced;
  final DateTime Function() _now;
  late final Signal<RelayConnectionState> _relayState;
  late final Computed<bool> _waiting = computed(() => _relayState.value != RelayConnectionState.connected);
  late final StreamSubscription<PresenceFrame> _presence;
  late final StreamSubscription<RelayConnectionState> _relay;
  bool _disposed = false;

  /// Online machines first, then offline, each sorted by name; agents only. A failed refresh
  /// keeps the last list and holds the spec §12 text in `state.error` — `ShellxBackend.devices()`
  /// and `pinnedMachines()` (a Keychain/Keystore read) can both throw, and neither is ever left
  /// unhandled.
  final StateSignal<MachineList> state = StateSignal(const MachineList([]));

  ShellxBackend get backend => _backend;

  /// The relay is not connected: cards dim, say "Đang chờ kết nối" and cannot be opened.
  ReadonlySignal<bool> get waiting => _waiting;

  /// The clock "Lần cuối online: …" is measured against.
  DateTime now() => _now();

  /// Tabs open on this phone for [agentId] ("2 tab"). Delegates to the reactive
  /// `WorkspaceRegistry.tabCount`, so a `computed`/`Watch` reading this follows it.
  int tabsOpen(String agentId) => _registry?.tabCount(agentId) ?? 0;

  /// "Kết nối lại" after close code 4001 (spec §12).
  void reconnectReplaced() => unawaited(_onReconnectReplaced?.call());

  Future<void> refresh() => mainStateGuard(_load, state: state);

  Future<MachineList> _load() async {
    final devices = await _backend.devices();
    final pinned = {for (final machine in await _backend.pinnedMachines()) machine.agentId};
    final live = _backend.relayState == RelayConnectionState.connected;
    return _sorted([
      for (final device in devices)
        if (device.kind == DeviceKind.agent)
          MachineEntry(
            id: device.id,
            name: device.name,
            platform: device.platform,
            // While connected the hub's PRESENCE is fresher than the REST snapshot.
            online: live ? _backend.isOnline(device.id) : device.online,
            lastSeenAt: device.lastSeenAt,
            paired: pinned.contains(device.id),
          ),
    ]);
  }

  /// Design "Danh sách máy": online on top, "Offline" below.
  MachineList _sorted(List<MachineEntry> machines) {
    int byName(MachineEntry a, MachineEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return MachineList(
      List.unmodifiable([
        ...machines.where((m) => m.online).toList()..sort(byName),
        ...machines.where((m) => !m.online).toList()..sort(byName),
      ]),
    );
  }

  /// The hub only reports PRESENCE while the relay is connected. An offline frame that arrives
  /// while it is not connected is therefore not from the hub: it is the synthetic one
  /// `ClientService._onState` raises for every machine it had as online, right when the relay is
  /// lost or `ShellxBackend.suspend` stops the client — before the client clears its own online
  /// set. Only a frame that arrives while genuinely connected stamps "last online" with the local
  /// clock; the synthetic one leaves the last known time alone, and the REST snapshot from the
  /// refresh that follows a reconnect supplies the real one.
  void _onPresence(PresenceFrame frame) {
    if (_disposed) return;
    final machines = state.peek().machines;
    final index = machines.indexWhere((machine) => machine.id == frame.deviceId);
    if (index < 0) {
      // A computer that just registered: fetch its name.
      if (frame.online) unawaited(refresh());
      return;
    }
    final machine = machines[index];
    if (machine.online == frame.online) return;
    final fromHub = _backend.relayState == RelayConnectionState.connected;
    final updated = List.of(machines)
      ..[index] = machine.copyWith(online: frame.online, lastSeenAt: (!frame.online && fromHub) ? _now() : null);
    state.value = _sorted(updated);
  }

  void dispose() {
    _disposed = true;
    unawaited(_presence.cancel());
    unawaited(_relay.cancel());
    _waiting.dispose();
    _relayState.dispose();
    state.dispose();
  }
}
