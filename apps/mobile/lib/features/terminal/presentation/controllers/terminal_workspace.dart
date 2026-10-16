import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';

/// What the session picker offers (terminal sharing §9.1): the sessions not open as tabs yet, and
/// the agent's `desktop_sharing` for the hint shown when there is no desktop terminal.
final class SessionListing {
  const SessionListing(this.sessions, {required this.desktopSharing, this.aiSupported, this.ai});

  final List<SessionInfo> sessions;

  /// Null: an agent older than terminal sharing ("Cập nhật ShellX trên máy tính…").
  final bool? desktopSharing;

  /// V2-2: whether the computer has AI sessions for phones (false: "Cập nhật ShellX trên máy
  /// tính để dùng phiên AI…"); null when unknown.
  final bool? aiSupported;

  /// V2-2: the computer's AI sessions, agents and folders; null when not supported or not
  /// received yet.
  final AiListing? ai;

  /// "Terminal trên máy tính".
  List<SessionInfo> get desktop => [
    for (final session in sessions)
      if (session.kind == SessionKind.desktop) session,
  ];

  /// "Phiên ShellX".
  List<SessionInfo> get shellx => [
    for (final session in sessions)
      if (session.kind != SessionKind.desktop) session,
  ];

  /// Nothing to pick: `+` opens a new session at once. A computer with AI for phones always
  /// offers the picker ("Phiên AI mới").
  bool get isEmpty => sessions.isEmpty && aiSupported != true;
}

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
  bool _disposed = false;

  /// Local ids of [TerminalTabController.failed] tabs: negative, so never a session's.
  int _nextFailedId = -1;

  ReadonlySignal<List<TerminalTabController>> get tabs => _tabs;
  ReadonlySignal<int> get activeIndex => _active;
  ReadonlySignal<TerminalTabController?> get activeTab => _activeTab;

  /// The user picks a tab: a notification's pending selection no longer applies.
  void select(int index) {
    clearPendingSelect();
    _select(index);
  }

  void _select(int index) {
    if (index < 0 || index >= _tabs.peek().length) return;
    _active.value = index;
    _syncActive();
  }

  int? _pendingSelectId;
  Timer? _pendingTimer;

  bool get hasPendingSelect => _pendingSelectId != null;

  /// A11 D27: a notification named [sessionId] before its tab exists (the phone is still reconnecting).
  /// The tab is selected when it appears and stays selected while tabs keep arriving (a new tab does not
  /// take the focus from it, not even for a moment); the user picking or opening a tab, or [ttl], drops the
  /// request. When the tab is already open it is selected at once.
  void pendingSelect(int sessionId, {Duration ttl = const Duration(seconds: 30)}) {
    if (_disposed) return;
    final index = _tabs.peek().indexWhere((tab) => tab.id == sessionId);
    if (index >= 0) {
      select(index);
      _externalSelect = true;
      return;
    }
    _pendingSelectId = sessionId;
    _pendingTimer?.cancel();
    _pendingTimer = Timer(ttl, clearPendingSelect);
  }

  void clearPendingSelect() {
    _pendingSelectId = null;
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  /// The index of the pending tab in [tabs]; null when nothing is pending or it is not open yet. The
  /// request stays until [ttl] or a user pick, so a tab added or re-attached later lands on it directly
  /// (no flicker through another tab: `activeIndex` and [TerminalTabController.setViewed] never see it).
  int? _pendingIndex(List<TerminalTabController> tabs) {
    final id = _pendingSelectId;
    if (id == null) return null;
    final index = tabs.indexWhere((tab) => tab.id == id);
    return index >= 0 ? index : null;
  }

  /// A10 D29: only the active tab's output is written at the foreground's pace. A11 D28: only the active
  /// tab of a page that is showing is looked at.
  void _syncActive() {
    final active = _activeTab.peek();
    for (final tab in _tabs.peek()) {
      tab.setActive(identical(tab, active));
      tab.setViewed(identical(tab, active) && _viewing);
    }
  }

  bool _viewing = false;

  /// A notification chose a tab that was already open, just before the page is shown: entering the page must
  /// not move to the first tab with new output instead. Dropped once the page is shown or left.
  bool _externalSelect = false;

  /// The terminal page of this machine is on screen (true) or not: left, covered, or the app in the
  /// background (false). Output of a tab that is not looked at is counted by [unseenCount].
  void setViewing(bool viewing) {
    if (_disposed) return;
    _externalSelect = false;
    if (_viewing == viewing) return;
    _viewing = viewing;
    _syncActive();
  }

  /// Tabs with output nobody has looked at. Reactive: read inside a `computed`/`Watch`. Counted from the
  /// tabs each time, so a closed tab is never left in it.
  int get unseenCount => _tabs.value.where((tab) => tab.unseen.value).length;

  /// Agent quick reply §3: the most urgent agent state of the tabs (a waiting agent, else a running one); null
  /// when no tab shows either. Reactive like [unseenCount].
  AgentWireState? get agentState {
    final states = {for (final tab in _tabs.value) tab.agentState.value};
    if (states.contains(AgentWireState.needsInput)) return AgentWireState.needsInput;
    if (states.contains(AgentWireState.running)) return AgentWireState.running;
    return null;
  }

  /// Enters the machine from the list: the first tab with new output is shown. Nothing when none has.
  void selectFirstUnseen() {
    if (_externalSelect) {
      _externalSelect = false;
      return;
    }
    final index = _tabs.peek().indexWhere((tab) => tab.unseen.peek());
    if (index >= 0) _select(index);
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
  Future<SessionListing?> prepare() async {
    await ensureConnected();
    if (_listedSessions) return null;
    return pickable();
  }

  /// How long the picker waits for the first AI listing.
  static const Duration aiListingWait = Duration(seconds: 3);

  /// Terminal sharing §9.1, for `+`: lists the machine's sessions (desktop terminals included)
  /// again, leaving out those already open as tabs.
  Future<SessionListing> pickable() async {
    await ensureConnected();
    final sessions = await machine.listSessions();
    _listedSessions = true;
    final ai = await _pickableAiListing();
    // After the wait for the AI listing: a session attached meanwhile is a tab by now.
    final open = {for (final tab in _tabs.peek()) tab.id};
    return SessionListing(
      [
        for (final session in sessions)
          if (!open.contains(session.id)) session,
      ],
      desktopSharing: machine.desktopSharing,
      aiSupported: machine.ai.supported,
      ai: ai,
    );
  }

  // V2-2: the computer's AI sessions. The list is watched while a page shows it (or the picker is being
  // made), and not otherwise: every relay or presence event would make a handshake with every machine
  // ever watched.
  int _aiHolders = 0;
  bool _aiWatching = false;

  /// What the client holds of the listing predates the last [AiMachine.unwatch]: the computer's changes
  /// do not reach a channel that did not ask for them. Cleared by the first listing that arrives once
  /// the list is watched again.
  bool _aiStale = false;
  StreamSubscription<AiListing>? _aiFeed;

  /// The computer's AI listing as far as it can be trusted: null when none came yet, or none since the
  /// list was last watched (the client still holds the old one then).
  AiListing? get aiListing => _aiStale ? null : machine.ai.listing;

  /// A page shows the computer's AI sessions (the ✦ button, the picker): the list is watched from now
  /// on, once the computer is known to have AI for phones, until the returned function is called. The
  /// client's watch is one switch, not a count, so the holders are counted here: the last to let go
  /// stops it, and a page that is left never stops the watch of one that took its place. Letting go
  /// twice is letting go once.
  void Function() holdAiListing() {
    _aiHolders++;
    _syncAiWatch();
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _aiHolders--;
      _syncAiWatch();
    };
  }

  /// V2-2b: a list of the machine's sessions answered after the listing was held (a page opened from a
  /// notification before the relay was connected, whose own list failed): a holder that waited for it is watched
  /// now if the computer has AI. Nothing when nothing changed.
  void aiSupportLearned() => _syncAiWatch();

  /// Watches while somebody holds the list and the computer has AI; stops when nobody does.
  void _syncAiWatch() {
    final ai = machine.ai;
    final want = !_disposed && _aiHolders > 0 && ai.supported == true;
    if (want == _aiWatching) return;
    _aiWatching = want;
    if (want) {
      _aiFeed = ai.listings.listen((_) => _aiStale = false);
      // A machine that cannot be reached now is asked again on its next channel.
      unawaited(ai.watch().catchError((Object _) {}));
    } else {
      unawaited(_aiFeed?.cancel());
      _aiFeed = null;
      _aiStale = true;
      ai.unwatch();
    }
  }

  /// The listing for the picker: null when the computer has no AI for phones, or did not answer within
  /// [aiListingWait]. The list is watched meanwhile, and let go again afterwards unless a page holds it.
  Future<AiListing?> _pickableAiListing() async {
    if (_disposed || machine.ai.supported != true) return null;
    final release = holdAiListing();
    try {
      return aiListing ?? await _nextAiListing();
    } finally {
      release();
    }
  }

  /// The next listing the computer sends; null once [aiListingWait] has passed, or when the machine is
  /// dropped. Neither the timer nor the subscription outlives the wait.
  Future<AiListing?> _nextAiListing() {
    final next = Completer<AiListing?>();
    void finish(AiListing? listing) {
      if (!next.isCompleted) next.complete(listing);
    }

    final timer = Timer(aiListingWait, () => finish(null));
    final heard = machine.ai.listings.listen(finish, onDone: () => finish(null));
    return next.future.whenComplete(() {
      timer.cancel();
      unawaited(heard.cancel());
    });
  }

  /// Spec §12: `spawn_failed` shows its reason inside a tab, so it becomes a
  /// [TerminalTabController.failed] tab. Throws any other [AppErrorException] (`session_limit`,
  /// shown as the floating notice) and connection failures.
  Future<TerminalTabController> openNew(TerminalGrid grid) async {
    clearPendingSelect(); // the user asked for a new session: it wins
    await ensureConnected();
    final TabHandle handle;
    try {
      handle = await machine.openSession(cols: grid.cols, rows: grid.rows);
    } on AppErrorException catch (error) {
      if (error.code != AppErrorCode.spawnFailed) rethrow;
      return _add(
        TerminalTabController.failed(machine: machine, id: _nextFailedId--, error: error, modifiers: extraKeys),
      );
    }
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
      // A reconnect re-attaching an open tab is not the user's choice: a pending notification tab keeps
      // the focus.
      _select(_pendingIndex(tabs) ?? existing);
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

  /// A request that was still in flight when the workspace was dropped (sign-out, unpair, an
  /// untrusted machine) adds nothing: the new tab is closed again and [StateError] thrown.
  TerminalTabController _add(TerminalTabController tab) {
    if (_disposed) {
      tab.dispose();
      if (tab.hasSession) unawaited(machine.closeTab(tab.id).catchError((Object _) {}));
      throw StateError('The workspace was dropped');
    }
    final tabs = [..._tabs.peek(), tab];
    batch(() {
      _tabs.value = List.unmodifiable(tabs);
      // The new tab takes the focus, unless a notification's tab is pending and open (A11 D27).
      _active.value = _pendingIndex(tabs) ?? tabs.length - 1;
    });
    _syncActive();
    return tab;
  }

  /// `×`: sends `session.close` (spec §6.4) — `session.detach` for a desktop terminal, which keeps
  /// running on the computer — and drops the tab. Errors from an
  /// already-ended session are ignored — the tab must always be closable.
  ///
  /// The active tab is tracked by identity, not by index: removing a tab shifts every later
  /// index down by one, so keeping the same index would silently select a different tab (e.g.
  /// tabs [a, b, c, d] with c active at index 2 — closing a must keep c active, not land on d).
  Future<void> close(TerminalTabController tab) async {
    if (_disposed) return;
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
    _syncActive();
    if (!tab.hasSession) return;
    try {
      await machine.closeTab(tab.id);
    } on Object {
      // The session no longer exists on the machine.
    }
  }

  void dispose() {
    _disposed = true;
    _syncAiWatch();
    clearPendingSelect();
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

  /// Tabs of [agentId] with new output (the dot of the machine list). Reactive like [tabCount].
  int unseenCount(String agentId) {
    _version.value;
    return _workspaces[agentId]?.unseenCount ?? 0;
  }

  /// [TerminalWorkspace.agentState] of [agentId] (the agent dot of the machine list). Reactive like [tabCount].
  AgentWireState? agentState(String agentId) {
    _version.value;
    return _workspaces[agentId]?.agentState;
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
