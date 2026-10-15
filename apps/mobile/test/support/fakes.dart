import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
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
  FakeTabHandle({
    required this.id,
    required this.index,
    this.shell = 'zsh',
    this.kind = SessionKind.shellx,
    this.app = '',
    this.title = '',
  });

  @override
  final int id;
  @override
  final int index;
  @override
  final String shell;
  @override
  final SessionKind kind;
  @override
  final String app;
  @override
  final String title;
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

  /// What [desktopSharing] reports (null: an agent older than terminal sharing).
  bool? desktopSharingValue;
  Object? openError;

  /// [openSession] completes only once this does — an open still in flight when something else
  /// runs (the page is left, the workspace dropped).
  Completer<void>? openGate;

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
    ai.noteList();
    return sessions;
  }

  @override
  bool? get desktopSharing => desktopSharingValue;

  @override
  Future<TabHandle> openSession({required int cols, required int rows}) async {
    opened.add((cols: cols, rows: rows));
    final gate = openGate;
    if (gate != null) await gate.future;
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
      handle = FakeTabHandle(
        id: id,
        index: info?.index ?? id,
        shell: info?.shell ?? 'zsh',
        kind: info?.kind ?? SessionKind.shellx,
        app: info?.app ?? '',
        title: info?.title ?? '',
      );
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

  /// V2-2: the machine's AI sessions.
  @override
  final FakeAiMachine ai = FakeAiMachine();

  /// V2-4: the machine's tools.
  @override
  final FakeToolMachine tools = FakeToolMachine();
}

/// A mirrored AI session for tests (V2-2). Fed like the real one: a desktop-side [AiSubscription]
/// over [desktop] makes the bodies, [sync] applies them as the phone would.
///
/// It acts like [AiSessionLink] (`shellx_client`) where tests rely on it: a lost channel keeps the
/// mirror and the next [sync] attaches again with what the mirror holds; a closed link — by the
/// computer ([close]) or by [detach] — is final, and a [detach]ed one ends its [changes].
class FakeAiSession implements AiSessionHandle {
  FakeAiSession(this.sid, {AiSessionState? desktop})
    : desktop =
          desktop ?? (AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')..setPhase(AgentPhase.ready));

  @override
  final String sid;

  /// The session as the computer holds it; tests change it like the agent would.
  final AiSessionState desktop;
  late final AiSubscription _sub = AiSubscription(desktop, generation: 1);

  /// False before the first [sync] and after [lose]: the next [sync] attaches (a snapshot, which
  /// goes on from the numbers before it after a loss).
  var _attached = false;

  @override
  final AiMirror mirror = AiMirror();
  AiLinkState stateValue = AiLinkState.attaching;
  String? closedReasonValue;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  bool detached = false;
  int earlierCalls = 0;
  var _notifying = false;
  var _notifyAgain = false;
  var _ended = false;

  /// Tells the listeners, like the real link: a change made from inside a listener (a `detach()` from
  /// its callback, say) is told once the round is over, and a detached link ends [changes] after the
  /// last round.
  void _notify() {
    if (_changes.isClosed) return;
    if (_notifying) {
      _notifyAgain = true;
      return;
    }
    _notifying = true;
    try {
      do {
        _notifyAgain = false;
        _changes.add(null);
      } while (_notifyAgain);
    } finally {
      _notifying = false;
    }
    if (_ended) unawaited(_changes.close());
  }

  /// Brings the phone's mirror up to date with [desktop] (the snapshot first; a long text comes in
  /// pieces, all of them). A closed link takes no more bodies.
  void sync() {
    if (stateValue == AiLinkState.closed) return;
    var out = _attached ? _sub.delta() : _sub.attach(mirror.generation < 0 ? null : mirror.have);
    _attached = true;
    for (var round = 0; round < 1000; round++) {
      for (final o in out) {
        mirror.apply(decodeBody(o.body)!, snapshot: o.snapshot);
        _sub.ack(o.seq);
      }
      if (!_sub.dirty) break;
      out = _sub.delta();
    }
    stateValue = AiLinkState.live;
    _notify();
  }

  /// The computer closed it ([reason]: `gone`, `desktop_closed`, …).
  void close(String reason) {
    if (_ended) return;
    stateValue = AiLinkState.closed;
    closedReasonValue = reason;
    _notify();
  }

  /// The channel dropped: the mirror stays, the link re-attaches ([sync]). A link that is not live
  /// (still attaching, or closed) has nothing to tell.
  void lose() {
    _attached = false;
    if (stateValue != AiLinkState.live) return;
    stateValue = AiLinkState.attaching;
    _notify();
  }

  @override
  AiLinkState get state => stateValue;

  @override
  String? get closedReason => closedReasonValue;

  @override
  Stream<void> get changes => _changes.stream;

  /// Like the real link: closed with reason `detached` (unless the computer closed it first), told to
  /// the listeners once, then [changes] ends.
  @override
  void detach() {
    detached = true;
    if (stateValue != AiLinkState.closed) {
      stateValue = AiLinkState.closed;
      closedReasonValue = 'detached';
      _notify();
    }
    _ended = true;
    if (!_notifying) unawaited(_changes.close());
  }

  /// Counts the tap; asks the computer only while the link is live and older items exist.
  @override
  void loadEarlier() {
    earlierCalls++;
    if (stateValue != AiLinkState.live || !mirror.hasEarlier) return;
    for (final o in _sub.earlier(mirror.from)) {
      mirror.apply(decodeBody(o.body)!, snapshot: false);
      _sub.ack(o.seq);
    }
    _notify();
  }
}

/// Scriptable [AiMachine] (V2-2): records every request.
/// - [failWith] makes requests fail with that `ai.result` code ([AiRequestException]);
/// - [connectFailure] makes them, and [watch], fail like a machine that cannot be reached
///   ([MachineConnectionException]);
/// - [gate] holds them in flight: what is set meanwhile decides how they end.
///
/// [attach] gives the same link while it is open and, like `MachineAi`, a new one over the same
/// session once it closed.
class FakeAiMachine implements AiMachine {
  bool? supportedValue;
  AiListing? listingValue;
  final StreamController<AiListing> _listings = StreamController<AiListing>.broadcast(sync: true);
  final Map<String, FakeAiSession> sessions = {};
  final List<(String, String)> prompts = [];
  final List<(String, int, String)> permissionAnswers = [];
  final List<(String, int, ElicitationResponse)> askAnswers = [];
  final List<String> cancels = [];
  final List<String> forceStops = [];
  final List<(String, int)> unqueued = [];
  final List<(String, String)> opened = [];
  String? failWith;
  MachineConnectionFailure? connectFailure;
  String openedSid = 'e.-9';
  int watchCalls = 0;

  /// Every [unwatch], the ones that found nothing watched included.
  int unwatchCalls = 0;

  /// The list is wanted: set by [watch] (also when the machine cannot be reached: the real one asks
  /// for the list on every new channel from its first call on), cleared by [unwatch].
  bool watching = false;

  /// Somebody still listens to [listings]: what a screen that is gone must not leave behind.
  bool get hasListingListener => _listings.hasListener;

  /// The machine is dropped (unpaired, signed out): its listings end, as `MachineAi.dispose` ends them.
  Future<void> endListings() => _listings.close();

  /// Requests wait for this when set (an answer still travelling).
  Completer<void>? gate;

  /// A listing came from the computer: it has AI, as the real client learns from an `ai.list.result`
  /// ([AiListing.unavailable]: no window serves it yet). Its sessions are [seen] from now on.
  void emitListing(AiListing listing) {
    supportedValue = true;
    listingValue = listing;
    for (final session in listing.sessions) {
      seenSessions[session.sid] = session;
    }
    _listings.add(listing);
  }

  /// V2-2b B1: the computer's `ai` protocol as the app knows it (null: no list answered yet).
  int? protocolValue;

  /// What the computer's `session.list.result` says (`ai`): a list of the sessions
  /// ([FakeMachineSession.listSessions]) teaches it, as the real client learns it. Null: the test sets
  /// [protocolValue] and [supportedValue] itself.
  int? listedProtocol;

  /// A list of the machine's sessions came back.
  void noteList() {
    final protocol = listedProtocol;
    if (protocol == null) return;
    protocolValue = protocol;
    supportedValue = protocol >= 1;
  }

  /// V2-2b B22, B23: every session of every listing emitted.
  final Map<String, AiSessionInfo> seenSessions = {};

  @override
  int? get protocol => protocolValue;

  @override
  bool can(String feature) => (protocolValue ?? 0) >= 2 && (listingValue?.features.contains(feature) ?? false);

  @override
  AiSessionInfo? seen(String sid) => seenSessions[sid];

  FakeAiSession session(String sid) => sessions.putIfAbsent(sid, () => FakeAiSession(sid));

  Future<void> _request() async {
    await gate?.future;
    final failure = connectFailure;
    if (failure != null) throw MachineConnectionException(failure);
    final code = failWith;
    if (code != null) throw AiRequestException(code);
  }

  @override
  bool? get supported => supportedValue;

  @override
  AiListing? get listing => listingValue;

  @override
  Stream<AiListing> get listings => _listings.stream;

  @override
  Future<void> watch() async {
    watchCalls++;
    watching = true;
    final failure = connectFailure;
    if (failure != null) throw MachineConnectionException(failure);
  }

  @override
  void unwatch() {
    unwatchCalls++;
    watching = false;
  }

  @override
  AiSessionHandle attach(String sid) {
    final current = sessions[sid];
    if (current != null && current.state == AiLinkState.closed) {
      sessions[sid] = FakeAiSession(sid, desktop: current.desktop);
    }
    return session(sid);
  }

  @override
  Future<void> prompt(String sid, String text) async {
    prompts.add((sid, text));
    await _request();
  }

  @override
  Future<void> answerPermission(String sid, int permission, String option) async {
    permissionAnswers.add((sid, permission, option));
    await _request();
  }

  @override
  Future<void> answerAsk(String sid, int ask, ElicitationResponse response) async {
    askAnswers.add((sid, ask, response));
    await _request();
  }

  @override
  Future<void> cancel(String sid) async {
    cancels.add(sid);
    await _request();
  }

  @override
  Future<void> forceStop(String sid) async {
    forceStops.add(sid);
    await _request();
  }

  @override
  Future<void> unqueue(String sid, int queued) async {
    unqueued.add((sid, queued));
    await _request();
  }

  @override
  Future<String> open(String agent, String folder) async {
    opened.add((agent, folder));
    await _request();
    return openedSid;
  }
}

/// Scriptable [ToolMachine] (V2-4): the list as a test sets it, and the pages it made.
class FakeToolMachine implements ToolMachine {
  bool? supportedValue;
  ToolListing? listingValue;
  final StreamController<ToolListing> _listings = StreamController<ToolListing>.broadcast(sync: true);
  int watchCalls = 0;
  int unwatchCalls = 0;
  bool watching = false;

  /// Makes [watch] fail like the real one does for a machine that cannot be reached (the list is
  /// wanted all the same: the real client asks for it on every new channel from its first call on).
  MachineConnectionFailure? connectFailure;

  /// Somebody still listens to [listings]: what a screen that is gone must not leave behind.
  bool get hasListingListener => _listings.hasListener;

  /// The machine is dropped (unpaired, signed out): its lists end.
  Future<void> endListings() => _listings.close();

  /// Every page made, in order, and the texts each was given.
  final List<FakeToolPage> pages = [];
  final List<ToolHostTexts> texts = [];

  /// A list from the computer: it has tools.
  void emitListing(ToolListing listing) {
    supportedValue = true;
    listingValue = listing;
    _listings.add(listing);
  }

  @override
  bool? get supported => supportedValue;

  @override
  ToolListing? get listing => listingValue;

  @override
  Stream<ToolListing> get listings => _listings.stream;

  @override
  Future<void> watch() async {
    watchCalls++;
    watching = true;
    final failure = connectFailure;
    if (failure != null) throw MachineConnectionException(failure);
  }

  @override
  void unwatch() {
    unwatchCalls++;
    watching = false;
  }

  @override
  ToolPageSession page(ToolInfo tool, ToolHostTexts texts) {
    this.texts.add(texts);
    final page = FakeToolPage(tool);
    pages.add(page);
    return page;
  }
}

/// Scriptable [ToolPageSession]: a test sets the phase and says what the page must do.
class FakeToolPage implements ToolPageSession {
  FakeToolPage(this.tool);

  final ToolInfo tool;
  ToolPhase phaseValue = ToolPhase.opening;
  int? servedPortValue;
  int requestsValue = 0;
  final StreamController<void> _changes = StreamController<void>.broadcast(sync: true);
  final StreamController<ToolPageEvent> _events = StreamController<ToolPageEvent>.broadcast(sync: true);
  int starts = 0;
  int homes = 0;
  int pauses = 0;
  int resumes = 0;
  int closes = 0;
  int resets = 0;

  void setPhase(ToolPhase phase) {
    phaseValue = phase;
    _changes.add(null);
  }

  /// Served on [port] ([tool]'s own by default) and told to load its entry URL.
  void ready({int? port}) {
    servedPortValue = port ?? tool.port;
    setPhase(ToolPhase.ready);
    _events.add(ToolLoad(Uri.parse('http://localhost:$servedPortValue/__shellx/enter?n=x&to=%2F')));
  }

  void emit(ToolPageEvent event) => _events.add(event);

  @override
  ToolPhase get phase => phaseValue;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<ToolPageEvent> get events => _events.stream;

  @override
  int get port => tool.port;

  @override
  int? get servedPort => servedPortValue;

  @override
  int? get alias {
    final served = servedPortValue;
    return served != null && served != tool.port ? served : null;
  }

  /// Ports of the workspace's other tools this page serves too (E4); [origins] holds them while something is
  /// served.
  final Set<int> siblingPorts = {};

  @override
  Set<String> get origins {
    final served = servedPortValue;
    if (served == null) return {};
    return {'http://localhost:$served', for (final sibling in siblingPorts) 'http://localhost:$sibling'};
  }

  @override
  int get requests => requestsValue;

  @override
  void resetRequests() {
    resets++;
    requestsValue = 0;
  }

  @override
  void start() => starts++;

  @override
  void home() => homes++;

  @override
  Future<void> pause() async {
    pauses++;
    setPhase(ToolPhase.paused);
  }

  @override
  void resume() => resumes++;

  @override
  Future<void> close() async {
    closes++;
    phaseValue = ToolPhase.closed;
  }
}

/// Scriptable [ShellxBackend]. [unpair] (whether or not [unpairError] is set) and an `untrusted`
/// handshake behave like `shellx_client`. Known divergences from the real client:
/// - [suspend] and [emitRelay] reach neither the machine states (real: a lost channel moves
///   [MachineReady] to [MachineIdle]; script it with [FakeMachineSession.emitState]) nor presence
///   on their own — use [emitRelayLoss] for the synthetic offline PRESENCE the real client raises
///   for every online machine on relay loss or suspend, or [emitPresence] for one hub-reported
///   change;
/// - requests do not connect first, and `attach` of an unknown id succeeds (real:
///   `AppErrorException(sessionNotFound)`);
/// - [resume] emits `connected` even when not suspended;
/// - [dispose] only sets [disposed] (and counts [disposeCalls]); [disposeGate] holds its future
///   back like a relay dial still settling, [disposeError] then makes it fail;
/// - [pair] neither calls [devices] nor drops the machine's channel;
/// - after `untrusted`, pairing again gives a fresh session (real: the same session, still
///   [MachineFailed]);
/// - [FakeMachineSession.reuseHandles] is false by default (real: a re-attach always returns the
///   same tab);
/// - pins ([pinnedList]) and sessions ([machines]) are tracked separately: [addMachine] pins
///   nothing, and [machine] works for any added machine;
/// - [FakeMachineSession.ai] carries on after [unpair] (real: the machine's AI links and listing end
///   with it), and its requests do not connect first (script [FakeAiMachine.connectFailure]);
/// - every stream is synchronous.
class FakeBackend implements ShellxBackend {
  FakeBackend({List<RemoteDevice>? devices, List<PinnedMachine>? pinnedList})
    : deviceList = devices ?? [],
      pinnedList = pinnedList ?? [];

  List<RemoteDevice> deviceList;
  List<PinnedMachine> pinnedList;
  Object? devicesError;

  /// Thrown by [pinnedMachines] instead of returning [pinnedList] (e.g. a Keychain/Keystore read
  /// failure).
  Object? pinnedError;

  /// [devices] completes only once this does — a `GET /v1/devices` still in flight when something
  /// else runs (e.g. the caller is disposed).
  Completer<void>? devicesGate;
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

  /// [unpair] waits for this after dropping the machine, before it succeeds or throws
  /// [unpairError] — a DELETE still retrying.
  Completer<void>? unpairGate;
  final List<PairingUri> paired = [];

  /// Every [pair] call, failed ones included.
  int pairCalls = 0;
  final List<String> unpaired = [];
  int reconnectCalls = 0;
  int suspendCalls = 0;
  int resumeCalls = 0;
  int disposeCalls = 0;
  bool disposed = false;

  /// [dispose] completes only once this does (real: `RelayConnection.stop()` waits up to 15 s for
  /// a dial in flight).
  Completer<void>? disposeGate;

  /// Thrown by [dispose] after it disposed (and after [disposeGate]).
  Object? disposeError;

  /// Thrown by [resume] instead of reconnecting (real: e.g. a Keychain error loading the pins).
  Object? resumeError;

  void emitRelay(RelayConnectionState state) {
    relayStateValue = state;
    _relay.add(state);
  }

  void emitPresence(String deviceId, {required bool online}) {
    online ? onlineIds.add(deviceId) : onlineIds.remove(deviceId);
    _presence.add(PresenceFrame(deviceId: deviceId, online: online));
  }

  /// `ClientService._onState`, on relay loss or `suspend` (`stop()`): an offline frame for every
  /// online machine, then it clears its own online set — and [relayState] itself has already
  /// changed by the time any of those frames reaches a listener. Reproduces that same order, so a
  /// listener reading [relayState] while handling one of these frames sees the new, non-connected
  /// state rather than the old one.
  void emitRelayLoss([RelayConnectionState to = RelayConnectionState.disconnected]) {
    relayStateValue = to;
    for (final deviceId in onlineIds.toList()) {
      _presence.add(PresenceFrame(deviceId: deviceId, online: false));
    }
    onlineIds.clear();
    _relay.add(to);
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
    final error = resumeError;
    if (error != null) throw error;
    emitRelay(RelayConnectionState.connected);
  }

  @override
  Future<List<RemoteDevice>> devices() async {
    final gate = devicesGate;
    if (gate != null) await gate.future;
    final error = devicesError;
    if (error != null) throw error;
    return deviceList;
  }

  @override
  bool isOnline(String agentId) => onlineIds.contains(agentId);

  @override
  Stream<PresenceFrame> get presence => _presence.stream;

  @override
  Future<List<PinnedMachine>> pinnedMachines() async {
    final error = pinnedError;
    if (error != null) throw error;
    return pinnedList;
  }

  @override
  Future<void> pair(PairingUri uri) async {
    pairCalls++;
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
    final gate = unpairGate;
    if (gate != null) await gate.future;
    final error = unpairError;
    if (error != null) throw error;
  }

  /// Every [registerPushToken] call, failed ones included.
  final List<(String, PushPlatform)> pushTokens = [];

  /// Thrown by [registerPushToken] (e.g. offline, or a relay without push support: 404).
  Object? pushTokenError;

  /// [registerPushToken] completes only once this does.
  Completer<void>? pushTokenGate;

  @override
  Future<void> registerPushToken(String token, PushPlatform platform) async {
    pushTokens.add((token, platform));
    await pushTokenGate?.future;
    final error = pushTokenError;
    if (error != null) throw error;
  }

  int pushTokenDeletes = 0;

  @override
  Future<void> deletePushToken() async => pushTokenDeletes++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
    final gate = disposeGate;
    if (gate != null) await gate.future;
    final error = disposeError;
    if (error != null) throw error;
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

/// A [SessionHolder] for page tests: signed in around [backend] (or signed out without one),
/// recording what the pages ask of it.
class FakeSessionHolder implements SessionHolder {
  FakeSessionHolder([ShellxBackend? backend])
    : _backend = signal<ShellxBackend?>(backend),
      _session = signal<AccountSession?>(
        backend == null
            ? null
            : const AccountSession(userId: 'user-1', deviceId: 'device-1', token: 'token-1', email: 'me@example.com'),
      );

  final Signal<ShellxBackend?> _backend;
  final Signal<AccountSession?> _session;
  final Signal<SignOutReason?> _signOutReason = signal(null);
  late final Computed<bool> _authenticated = computed(() => _session.value != null);
  int reconnectCalls = 0;
  int logoutCalls = 0;
  int restoreCalls = 0;
  int backgroundCalls = 0;
  int foregroundCalls = 0;
  final List<String> deletePasswords = [];
  Object? deleteError;

  /// [deleteAccount] completes only once this does, so a test can observe [DeleteAccountController]
  /// while a deletion is still pending.
  Completer<void>? deleteGate;
  final List<(String, String, String)> authCalls = [];
  Object? authError;

  /// [login] and [register] complete only once this does, so a test can observe a form while its
  /// request is still pending.
  Completer<void>? authGate;

  @override
  String? lastEmail;

  set signOutReasonValue(SignOutReason? reason) => _signOutReason.value = reason;

  /// What the end of a sign-out does (Task 11): session, backend and [reason] change in one batch,
  /// and [WorkspaceRegistry] then disposes every workspace of the old backend at once.
  void signOut([SignOutReason reason = SignOutReason.revoked]) => batch(() {
    _session.value = null;
    _backend.value = null;
    _signOutReason.value = reason;
  });

  /// A new sign-in around [backend] (the old backend, if any, is replaced in the same batch).
  void signIn(ShellxBackend backend) => batch(() {
    _session.value = const AccountSession(
      userId: 'user-1',
      deviceId: 'device-1',
      token: 'token-1',
      email: 'me@example.com',
    );
    _backend.value = backend;
    _signOutReason.value = null;
  });

  @override
  ReadonlySignal<ShellxBackend?> get backend => _backend;

  @override
  ShellxBackend get requireBackend => _backend.peek() ?? (throw StateError('Not signed in'));

  @override
  ReadonlySignal<AccountSession?> get session => _session;

  @override
  ReadonlySignal<bool> get isAuthenticated => _authenticated;

  @override
  ReadonlySignal<SignOutReason?> get signOutReason => _signOutReason;

  @override
  String get appVersion => '1.0.0';

  /// Thrown by [restore] after counting the call (e.g. a Keychain/Keystore read failure).
  Object? restoreError;

  @override
  Future<void> restore() async {
    restoreCalls++;
    final error = restoreError;
    if (error != null) throw error;
  }

  @override
  Future<void> login(String email, String password) => _auth('login', email, password);

  @override
  Future<void> register(String email, String password) => _auth('register', email, password);

  Future<void> _auth(String kind, String email, String password) async {
    authCalls.add((kind, email, password));
    final gate = authGate;
    if (gate != null) await gate.future;
    final error = authError;
    if (error != null) throw error;
  }

  @override
  Future<void> reconnectReplaced() async => reconnectCalls++;

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<void> deleteAccount(String password) async {
    deletePasswords.add(password);
    final gate = deleteGate;
    if (gate != null) await gate.future;
    final error = deleteError;
    if (error != null) throw error;
  }

  @override
  void onBackground() => backgroundCalls++;

  @override
  void onForeground() => foregroundCalls++;
}
