import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// The tabs of one machine. Outlives its page so terminals keep receiving
/// output while the user is elsewhere in the app (spec §9.4).
class TerminalWorkspace extends Controller {
  TerminalWorkspace({required this.machine, ExtraKeysController? extraKeys})
    : extraKeys = extraKeys ?? ExtraKeysController();

  final MachineSession machine;
  final ExtraKeysController extraKeys;
  final Signal<List<TerminalTabController>> _tabs = signal(const []);
  final Signal<int> _active = signal(0);
  late final Computed<TerminalTabController?> _activeTab = computed(() {
    final tabs = _tabs.value;
    return tabs.isEmpty ? null : tabs[_active.value];
  });
  bool _listedSessions = false;

  ReadonlySignal<List<TerminalTabController>> get tabs => _tabs;
  ReadonlySignal<int> get activeIndex => _active;
  ReadonlySignal<TerminalTabController?> get activeTab => _activeTab;

  void select(int index) {
    if (index < 0 || index >= _tabs.peek().length) return;
    _active.value = index;
  }

  /// Runs the IK handshake when needed. Throws the [MachineFailed] state
  /// (untrusted, protocolUnsupported, agentOffline, timeout).
  Future<void> ensureConnected() async {
    if (machine.state is MachineReady) return;
    try {
      await machine.connect();
    } catch (error) {
      // Unreachable under the port contract (`connect()` throws `MachineConnectionException`,
      // never the state object itself) — kept as defence in depth.
      if (error is MachineFailed) rethrow;
      final state = machine.state;
      if (state is MachineFailed) throw state;
      rethrow;
    }
  }

  /// Spec §9.2 #4: the first time the machine page opens, send
  /// `session.list`. Returns the sessions not shown as tabs yet, or null on
  /// later visits.
  Future<List<SessionInfo>?> prepare() async {
    await ensureConnected();
    if (_listedSessions) return null;
    final sessions = await machine.listSessions();
    _listedSessions = true;
    return [
      for (final session in sessions)
        if (!_tabs.peek().any((tab) => tab.id == session.id)) session,
    ];
  }

  /// Throws [AppErrorException] (`session_limit`, `spawn_failed`).
  Future<TerminalTabController> openNew(TerminalGrid grid) async {
    await ensureConnected();
    final handle = await machine.openSession(cols: grid.cols, rows: grid.rows);
    return _add(
      TerminalTabController(
        machine: machine,
        handle: handle,
        modifiers: extraKeys,
        cols: grid.cols,
        rows: grid.rows,
      ),
    );
  }

  /// Attaches an existing session. When the session is gone
  /// (`session_not_found`), the tab still appears, showing "Phiên đã kết thúc".
  Future<TerminalTabController> attach(SessionInfo session, TerminalGrid grid) async {
    final tabs = _tabs.peek();
    final existing = tabs.indexWhere((tab) => tab.id == session.id);
    if (existing >= 0) {
      select(existing);
      return tabs[existing];
    }
    await ensureConnected();
    try {
      final handle = await machine.attach(session.id, cols: grid.cols, rows: grid.rows);
      return _add(
        TerminalTabController(
          machine: machine,
          handle: handle,
          modifiers: extraKeys,
          cols: grid.cols,
          rows: grid.rows,
        ),
      );
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.sessionNotFound) rethrow;
      return _add(TerminalTabController.ended(machine: machine, session: session, modifiers: extraKeys));
    }
  }

  TerminalTabController _add(TerminalTabController tab) {
    final tabs = [..._tabs.peek(), tab];
    batch(() {
      _tabs.value = List.unmodifiable(tabs);
      _active.value = tabs.length - 1;
    });
    return tab;
  }

  /// `×`: sends `session.close` (spec §6.4) and drops the tab. Errors from an
  /// already-ended session are ignored — the tab must always be closable.
  ///
  /// The active tab is tracked by identity, not by index: removing a tab shifts every later
  /// index down by one, so keeping the same index would silently select a different tab (e.g.
  /// tabs [a, b, c, d] with c active at index 2 — closing a must keep c active, not land on d).
  Future<void> close(TerminalTabController tab) async {
    final tabs = [..._tabs.peek()];
    final closingIndex = tabs.indexOf(tab);
    if (closingIndex < 0) return;
    final activeTab = _activeTab.peek();
    tabs.removeAt(closingIndex);
    batch(() {
      _tabs.value = List.unmodifiable(tabs);
      if (identical(activeTab, tab)) {
        // The closed tab was the active one: the neighbour that takes its place, clamped.
        _active.value = tabs.isEmpty ? 0 : closingIndex.clamp(0, tabs.length - 1);
      } else if (activeTab != null) {
        _active.value = tabs.indexOf(activeTab);
      }
    });
    tab.dispose();
    try {
      await machine.closeTab(tab.id);
    } on Object {
      // The session no longer exists on the machine.
    }
  }

  void dispose() {
    for (final tab in _tabs.peek()) {
      tab.dispose();
    }
    _activeTab.dispose();
    _tabs.dispose();
    _active.dispose();
    extraKeys.dispose();
  }
}

/// One [TerminalWorkspace] per machine for the signed-in account. A sign-out or a new sign-in
/// (another backend) disposes every workspace of the previous one.
@lazySingleton
class WorkspaceRegistry {
  WorkspaceRegistry(ReadonlySignal<ShellxBackend?> backend) : _backend = backend {
    _stopWatching = backend.subscribe((current) {
      if (identical(current, _owner)) return;
      _clear();
      _owner = current;
    });
  }

  @factoryMethod
  static WorkspaceRegistry create(SessionHolder session) => WorkspaceRegistry(session.backend);

  final ReadonlySignal<ShellxBackend?> _backend;
  final Map<String, TerminalWorkspace> _workspaces = {};
  late final void Function() _stopWatching;
  ShellxBackend? _owner;

  /// Bumped on every create, replace and remove (dispose included) of a cached workspace, so a
  /// `computed`/`Watch` reading [tabCount] recomputes even when it was built before the workspace
  /// existed (the machine list's "N tab" pill).
  final Signal<int> _version = signal(0);

  /// Asks [ShellxBackend.machine] every time (it returns the same [MachineSession] while
  /// the underlying machine client stays the same, and a NEW one after an unpair and re-pair).
  /// Throws [StateError] when [agentId] is not pinned — never paired, unpaired, or forgotten after
  /// an `untrusted` handshake — and then sheds any cached workspace for that id (it is dead: its
  /// `connect()` and requests would throw `MachineConnectionException(untrusted)`).
  TerminalWorkspace forMachine(String agentId) {
    final backend = _backend.peek() ?? (throw StateError('Not signed in'));
    final MachineSession session;
    try {
      session = backend.machine(agentId);
    } on StateError {
      _drop(agentId);
      rethrow;
    }
    final cached = _workspaces[agentId];
    if (cached != null) {
      if (identical(cached.machine, session)) return cached;
      // Unpair followed by re-pair: same agentId, a different underlying machine client.
      cached.dispose();
    }
    final workspace = TerminalWorkspace(machine: session);
    _workspaces[agentId] = workspace;
    _version.value++;
    return workspace;
  }

  /// After unpairing (spec §5.5) or when the machine stops trusting us.
  void remove(String agentId) => _drop(agentId);

  void _drop(String agentId) {
    final removed = _workspaces.remove(agentId);
    if (removed == null) return;
    removed.dispose();
    _version.value++;
  }

  /// Tabs open on this phone for [agentId] (the "2 tab" pill of the machine list). Reactive: read
  /// inside a `computed`/`Watch`, it follows both the workspace's own tabs and this registry's
  /// create/replace/remove of the workspace itself — a workspace created after the pill's first
  /// build is still picked up.
  int tabCount(String agentId) {
    _version.value; // depend on create/replace/remove so a later forMachine() is observed too
    return _workspaces[agentId]?.tabs.value.length ?? 0;
  }

  void _clear() {
    for (final workspace in _workspaces.values) {
      workspace.dispose();
    }
    final hadAny = _workspaces.isNotEmpty;
    _workspaces.clear();
    if (hadAny) _version.value++;
  }

  @disposeMethod
  void dispose() {
    _stopWatching();
    _clear();
    _version.dispose();
  }
}
