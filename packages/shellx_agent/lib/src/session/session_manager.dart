import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../context/cwd_url.dart';
import '../context/git_head.dart';
import '../context/listening_ports.dart';
import '../notify/agent_notifications.dart';
import '../notify/command_tracker.dart';
import '../notify/osc_event_parser.dart';
import '../pty/pty.dart';
import '../pty/session_environment.dart';
import '../pty/shell_integration.dart';
import '../pty/shell_resolver.dart';
import '../term/osc_title.dart';
import 'agent_sessions.dart';
import 'local_sessions.dart';
import 'session_ids.dart';
import 'session_stream.dart';

/// Who opened a session (A1 D4): the desktop may close any session, a
/// phone may only end the sessions it opened.
enum SessionOrigin { desktop, phone }

/// Read-only view of a session for the tray menu and the terminal window.
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
    this.origin = SessionOrigin.phone,
    this.title = '',
    this.driver = DriverSide.phone,
    this.runningCommand = false,
    this.cwd,
    this.gitBranch,
    this.ports = const [],
  });
  final int id, index;
  final String shell;
  final DateTime createdAt;
  final String? attachedMobileId;
  final SessionOrigin origin;

  /// Latest OSC 0/2 title; empty until the shell sets one (A1 D13).
  final String title;

  /// Whose size the PTY follows right now (A1 D6).
  final DriverSide driver;

  /// Between OSC 133;C and 133;D (needs the ShellX shell hook, A1 D15).
  final bool runningCommand;

  /// The shell's directory from its hook's OSC 7 (A2 C1); null without a
  /// hook, or after an OSC 7 from another host (D2).
  final String? cwd;

  /// The git branch of [cwd] (C2); null when not a repository or unknown.
  final String? gitBranch;

  /// Listening TCP ports of the session's process tree, ascending (C3).
  final List<int> ports;

  bool get phoneAttached => attachedMobileId != null;
}

const int _minDimension = 1;
const int _maxDimension = 1000;

const Duration _outputDrainGrace = Duration(seconds: 2);

/// How long a session whose shell has exited waits for the send window to
/// clear before giving up on the blocked tail and delivering
/// `session.exited` anyway.
const Duration _drainTimeout = Duration(seconds: 30);

int _clampDimension(int value) => value.clamp(_minDimension, _maxDimension);

bool _noPhoneReceivesDriver(String mobileId) => false;

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.pty,
    required this.stream,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.driver,
  });

  final int id;
  final int index;
  final String shell;
  final DateTime createdAt;
  final Pty pty;
  final SessionStream stream;
  final SessionOrigin origin;

  /// The PTY's current size.
  int cols;
  int rows;

  /// Whose size the PTY follows (A1 D6).
  DriverSide driver;

  /// The attached phone's size; null while no phone is attached.
  int? phoneCols, phoneRows;

  /// The window's size for this session; null until the window sized it.
  int? localCols, localRows;

  /// Last keystroke from each side, for the driver hold.
  DateTime? lastPhoneInput, lastLocalInput;

  final titles = OscTitleParser();
  String title = '';
  String? cwd;
  String? gitBranch;
  List<int> ports = const [];

  /// Bumped by every branch lookup: a late answer to an older one is
  /// dropped (the directory changed meanwhile).
  int branchGeneration = 0;

  /// The shell's pid has been handed to the port watcher ([pty] may only
  /// know it once the process has started).
  bool pidKnown = false;
  final commandEvents = OscEventParser();
  final commands = CommandTracker(threshold: () => null);

  /// The session ends because someone closed it (desktop, phone, revoke,
  /// quit), not because the shell exited on its own.
  bool killedOnRequest = false;

  /// Completes with the shell's exit code (A1 `LocalSessionView.exitCode`).
  final exit = Completer<int>();

  /// Live output for local viewers (A1 §3.1: no ack, no send window).
  final local = StreamController<Uint8List>.broadcast(sync: true);

  /// Driver changes for local viewers.
  final drivers = StreamController<DriverSide>.broadcast(sync: true);

  String? get attachedMobileId => stream.attachedMobileId;
  set attachedMobileId(String? value) => stream.attachedMobileId = value;

  /// Phone that still gets `session.exited` after a `closed_by_host` detach.
  String? exitRecipient;

  /// True once the session is being torn down: a host-initiated close set
  /// this immediately, or the shell has already exited. A closing session
  /// rejects new `session.attach` calls and is hidden from listings, but
  /// stays in the manager (routing acks) until [_finish] removes it.
  bool closing = false;

  /// The shell's exit code, known once the process has actually exited.
  int? finishedExitCode;

  /// Bounds how long a closing session waits for the send window to clear
  /// before [_finish] runs anyway (see [_drainTimeout]).
  Timer? drainTimer;

  /// True as soon as [Pty.exitCode] has completed. From then on the pty is
  /// never killed, written to or resized again: its process id may already
  /// belong to another process (a tree kill would hit the wrong tree).
  bool exited = false;

  StreamSubscription<Uint8List>? output;

  /// Push notifications from this session's output (null when off).
  SessionNotifier? notifier;

  void write(Uint8List data) {
    if (!exited) pty.write(data);
  }

  void resize(int cols, int rows) {
    if (!exited) pty.resize(cols, rows);
  }

  void kill() {
    if (!exited) pty.kill();
  }
}

/// Owns every terminal session of the agent (spec v1 §6.5 and §7; A1 §3.1).
/// Created once per process (A1 D7): it outlives every relay connection.
///
/// Session ids come from [nextId]; by default a private `sessionIdAllocator`
/// (random start in [1, 2^31) from [random], default `Random.secure()`, then
/// +1), so a phone re-attaching after an agent restart cannot land on a new
/// session that reuses its old id (spec §6.4). `index` is still 1..n.
final class SessionManager implements AgentSessions, LocalSessions {
  SessionManager({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    int maxSessions = 32,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Duration driverHold = const Duration(seconds: 1),
    DateTime Function()? clock,
    bool Function(String mobileId)? receivesDriver,
    Random? random,
    int Function()? nextId,
    AgentNotifications? notifications,
    ShellIntegration? shellIntegration,
    GitBranchLookup? gitHeads,
    PortProbe? portProbe,
    bool windowsPaths = false,
    String localHostName = '',
    void Function(String message)? log,
  }) : _ptyFactory = ptyFactory,
       _gitHeads = gitHeads,
       _windowsPaths = windowsPaths,
       _localHostName = localHostName,
       _notifications = notifications,
       _shellIntegration = shellIntegration,
       _shellResolver = shellResolver,
       _homeDirectory = homeDirectory,
       _baseEnvironment = baseEnvironment,
       _maxSessions = maxSessions,
       _bufferCapacity = bufferCapacity,
       _sendWindow = sendWindow,
       _driverHold = driverHold,
       _clock = clock ?? DateTime.now,
       receivesDriver = receivesDriver ?? _noPhoneReceivesDriver,
       _nextId = nextId ?? sessionIdAllocator(random ?? Random.secure()) {
    if (portProbe != null) {
      _portWatcher = PortWatcher(
        probe: portProbe,
        shells: _shellPids,
        onPorts: _applyPorts,
        now: _clock,
        log: log,
      );
    }
  }

  final PtyFactory _ptyFactory;
  final ShellResolver _shellResolver;
  final String _homeDirectory;
  final Map<String, String> _baseEnvironment;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;
  final AgentNotifications? _notifications;

  /// Branch lookups (A2 C2); null: no branches.
  final GitBranchLookup? _gitHeads;

  /// OSC 7 paths are Windows paths (`C:\…`, UNC).
  final bool _windowsPaths;

  /// `Platform.localHostname`: which OSC 7 hosts are this computer (D2).
  final String _localHostName;

  /// Listening ports (A2 C3); null: no ports.
  PortWatcher? _portWatcher;

  /// While one side typed less than this ago, a keystroke from the other
  /// side is written but does not take the driver (and the PTY size) away:
  /// two people typing at once must not resize the PTY on every key.
  final Duration _driverHold;
  final DateTime Function() _clock;

  /// Whether [mobileId] understands `session.driver` (it sent
  /// `session.list {desktop: true}`). `SessionRouter` sets this; an old app
  /// never gets a message its decoder rejects (spec §7.9).
  bool Function(String mobileId) receivesDriver;

  /// Starts zsh/bash/PowerShell with the push-notification hook (spec
  /// §4.4); null starts the resolved shell unchanged.
  final ShellIntegration? _shellIntegration;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _opened = StreamController<SessionOpenedEvent>.broadcast();
  final _sessions = <int, _Session>{};
  final int Function() _nextId;
  int _pendingOpens = 0;

  /// Bumped by [closeAll] and [closeSessionsAttachedTo] so a phone's open
  /// that is still awaiting [_shellResolver] can tell it was told to tear
  /// down in the meantime and kill the pty instead of registering it.
  int _epoch = 0;

  /// Bumped by [closeAll] only: a revoke never voids a window's open.
  int _closeAllEpoch = 0;

  /// Messages to deliver, in order. A synchronous broadcast stream: a
  /// listener must not call back into the manager (e.g. `handle`)
  /// synchronously from its callback. [_pump] tolerates this (it updates
  /// its own bookkeeping before each send), but other callers are not
  /// guaranteed to be reentrant-safe.
  @override
  Stream<OutboundMessage> get outbound => _outbound.stream;

  /// Fires whenever the session list, an attachment, a title, a driver,
  /// a running command, a directory, a branch or the ports change.
  @override
  Stream<void> get changes => _changes.stream;

  @override
  Stream<SessionOpenedEvent> get opened => _opened.stream;

  @override
  List<SessionSummary> get sessions => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionSummary(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt,
          attachedMobileId: s.attachedMobileId,
          origin: s.origin,
          title: s.title,
          driver: s.driver,
          runningCommand: s.commands.running,
          cwd: s.cwd,
          gitBranch: s.gitBranch,
          ports: s.ports,
        ),
  ];

  /// Listable sessions, as `session.list.result` entries (A1: no context).
  List<SessionInfo> get sessionInfos => _infos(context: false);

  /// The same with `cwd` and `branch`, for phones that listed with
  /// `desktop: true` (A2 C4).
  List<SessionInfo> get sessionInfosWithContext => _infos(context: true);

  List<SessionInfo> _infos({required bool context}) => [
    for (final s in _sessions.values)
      if (!s.closing)
        SessionInfo(
          id: s.id,
          index: s.index,
          shell: s.shell,
          createdAt: s.createdAt.millisecondsSinceEpoch,
          attached: s.attachedMobileId != null,
          cwd: context ? s.cwd ?? '' : '',
          branch: context ? s.gitBranch ?? '' : '',
        ),
  ];

  /// Handles one decrypted message from phone [mobileId].
  @override
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList():
        _send(mobileId, SessionListResult(sessionInfos));
      case SessionOpen(:final cols, :final rows):
        await _open(mobileId, cols, rows);
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq):
        _attach(mobileId, id, cols, rows, lastSeq);
      case InputMessage(:final id, :final data):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        _phoneActive(session, input: true);
        session.write(data);
      case ResizeMessage(:final id, :final cols, :final rows):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.phoneCols = _clampDimension(cols);
        session.phoneRows = _clampDimension(rows);
        _phoneActive(session, input: false);
      case AckMessage(:final id, :final seq):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.stream.ack(seq);
        _pump(session);
      case SessionClose(:final id):
        final session = _sessions[id];
        if (session == null) {
          _notFound(mobileId, id);
          return;
        }
        if (session.origin == SessionOrigin.desktop) {
          // A1 D4: a phone never ends a terminal opened on this computer.
          if (session.attachedMobileId == mobileId && !session.closing) {
            _send(
              mobileId,
              SessionDetached(id: id, reason: DetachReason.closedByHost),
            );
            _phoneLeft(session);
            _changes.add(null);
          }
          return;
        }
        session.killedOnRequest = true;
        session.kill();
      default:
        // pair.confirm is handled by AgentService; agent→phone types are
        // never accepted from a phone.
        break;
    }
  }

  /// The channel to [mobileId] is gone: its sessions become unattached
  /// (no message is sent). A session that was already draining after its
  /// shell exited (spec: no attached phone) finishes immediately instead of
  /// waiting out the send window or the drain timeout.
  @override
  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final session in _sessions.values.toList()) {
      final wasAttached = session.attachedMobileId == mobileId;
      if (wasAttached) {
        _phoneLeft(session);
        changed = true;
      }
      if (session.exitRecipient == mobileId) session.exitRecipient = null;
      if (wasAttached && session.closing) _finish(session);
    }
    if (changed) _changes.add(null);
  }

  /// [mobileId] was revoked: the sessions it opened and is attached to are
  /// killed; a desktop-origin session it is attached to only loses it
  /// (`closed_by_host`, A1 D4).
  ///
  /// Precondition: no `session.open` from a phone is pending (awaiting the
  /// shell resolver). The epoch bump is global for phone opens, so it would
  /// also void an open in flight for another phone. AgentService guarantees
  /// this: it calls this from its inbox, which awaits every [handle] call.
  /// A window's [open] is never voided by a revoke.
  @override
  void closeSessionsAttachedTo(String mobileId) {
    _epoch++;
    var changed = false;
    for (final session in _sessions.values.toList()) {
      if (session.attachedMobileId != mobileId) continue;
      if (session.origin == SessionOrigin.phone) {
        session.killedOnRequest = true;
        session.kill();
      } else if (!session.closing) {
        _send(
          mobileId,
          SessionDetached(id: session.id, reason: DetachReason.closedByHost),
        );
        _phoneLeft(session);
        changed = true;
      }
    }
    if (changed) _changes.add(null);
  }

  /// The relay runtime stops (sign-out, remote access off, network loss —
  /// A1 D7): every phone is let go silently, like a dropped channel; no
  /// shell is killed. No `session.detached {closed_by_host}`: that tells a
  /// phone the shell is gone for good, while it keeps running and the
  /// phone should re-attach once it reconnects. A session already draining
  /// after its shell exited finishes now (nobody will hear its tail).
  void disconnectAllPhones() {
    var changed = false;
    for (final session in _sessions.values.toList()) {
      session.exitRecipient = null;
      if (session.attachedMobileId == null) continue;
      changed = true;
      if (session.closing) {
        session.attachedMobileId = null;
        _finish(session);
        continue;
      }
      _phoneLeft(session);
    }
    if (changed) _changes.add(null);
  }

  /// Closes a session from the tray or the window: `session.detached
  /// {closed_by_host}` now, `session.exited` once the shell is gone. Marks
  /// the session closing immediately so a `session.attach` racing the kill
  /// cannot steal [_Session.exitRecipient] before the shell has actually
  /// exited.
  void closeSession(int id) {
    final session = _sessions[id];
    if (session == null || session.closing) return;
    session.closing = true;
    session.killedOnRequest = true;
    final mobileId = session.attachedMobileId;
    if (mobileId != null) {
      _send(
        mobileId,
        SessionDetached(id: id, reason: DetachReason.closedByHost),
      );
      session.attachedMobileId = null;
      session.exitRecipient = mobileId;
    }
    _changes.add(null);
    session.kill();
  }

  /// Quit only (A1 D7): every shell ends.
  void closeAll() {
    _epoch++;
    _closeAllEpoch++;
    for (final id in _sessions.keys.toList()) {
      closeSession(id);
    }
  }

  @override
  LocalSessionView view(int id) {
    final session = _sessions[id];
    if (session == null) throw StateError('No session $id');
    return _LocalView(this, session);
  }

  @override
  void close(int id) => closeSession(id);

  @override
  void watchPorts(bool visible) => _portWatcher?.setVisible(visible);

  /// Session id → shell pid, for [PortWatcher] (D3: ptys without a pid
  /// have no ports). An exited shell is left out: its pid stays set but
  /// may already belong to another process, whose tree must not land on
  /// this tab.
  Map<int, int> _shellPids() {
    final pids = <int, int>{};
    for (final s in _sessions.values) {
      if (s.closing || s.exited) continue;
      final pid = _pidOf(s);
      if (pid != null) pids[s.id] = pid;
    }
    return pids;
  }

  static int? _pidOf(_Session session) {
    final pty = session.pty;
    return pty is PtyProcessId ? (pty as PtyProcessId).processId : null;
  }

  /// The port watcher classifies listeners against the shells it knew: it
  /// is told when a shell's pid becomes known.
  void _notePid(_Session session) {
    if (session.pidKnown || session.exited || _pidOf(session) == null) return;
    session.pidKnown = true;
    _portWatcher?.sessionsChanged();
  }

  /// The shell exited: its ports go now (the watcher publishes nothing
  /// once no session is left) and it leaves the watcher's snapshot.
  void _shellGone(_Session session) {
    _portWatcher?.sessionsChanged();
    if (session.ports.isEmpty) return;
    session.ports = const [];
    if (!session.closing) _changes.add(null);
  }

  void _applyPorts(Map<int, List<int>> ports) {
    var changed = false;
    for (final s in _sessions.values) {
      final next = ports[s.id] ?? const <int>[];
      if (_sameInts(next, s.ports)) continue;
      s.ports = List.unmodifiable(next);
      changed = true;
    }
    if (changed) _changes.add(null);
  }

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _localWrite(_Session session, Uint8List data) {
    if (session.closing) return;
    _localActive(session, input: true);
    session.write(data);
  }

  void _localReply(_Session session, Uint8List data) {
    if (session.closing || session.driver != DriverSide.desktop) return;
    session.write(data);
  }

  void _localResize(_Session session, int cols, int rows) {
    if (session.closing) return;
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final known = session.localCols != null;
    if (known && c == session.localCols && r == session.localRows) return;
    session.localCols = c;
    session.localRows = r;
    if (!known && session.driver == DriverSide.phone) return;
    _localActive(session, input: false);
  }

  /// A session the computer opens itself (the terminal window): nobody is
  /// attached, the desktop drives. Throws [SessionLimitException] or
  /// [SpawnFailedException].
  @override
  Future<int> open({required int cols, required int rows}) async {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final session = await _spawn(c, r, origin: SessionOrigin.desktop);
    if (session == null) {
      throw const SpawnFailedException('ShellX is closing every session');
    }
    session.localCols = c;
    session.localRows = r;
    _changes.add(null);
    return session.id;
  }

  Future<void> _open(String mobileId, int cols, int rows) async {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    final _Session? session;
    try {
      session = await _spawn(c, r, origin: SessionOrigin.phone);
    } on SessionLimitException {
      _send(
        mobileId,
        ErrorMessage(
          code: AppErrorCode.sessionLimit,
          message: 'This machine already has $_maxSessions open sessions.',
        ),
      );
      return;
    } on SpawnFailedException catch (error) {
      _send(
        mobileId,
        ErrorMessage(code: AppErrorCode.spawnFailed, message: error.message),
      );
      return;
    }
    // closeAll or closeSessionsAttachedTo ran while the shell was still
    // spawning: the opener already isn't getting a new session either way,
    // so this is dropped silently rather than answering spawn_failed.
    if (session == null) return;
    session.attachedMobileId = mobileId;
    session.phoneCols = c;
    session.phoneRows = r;
    _send(
      mobileId,
      SessionOpened(id: session.id, index: session.index, shell: session.shell),
    );
    _opened.add(SessionOpenedEvent(mobileId, session.id));
    _changes.add(null);
  }

  /// Starts a shell and registers its session (not attached, no event).
  /// Null when a teardown voided the open while the shell was spawning (the
  /// pty is killed).
  Future<_Session?> _spawn(
    int cols,
    int rows, {
    required SessionOrigin origin,
  }) async {
    if (_sessions.length + _pendingOpens >= _maxSessions) {
      throw SessionLimitException(_maxSessions);
    }
    final epoch = _epoch;
    final closeAllEpoch = _closeAllEpoch;
    _pendingOpens++;
    final ShellCommand command;
    final Pty pty;
    try {
      command = await _shellResolver.resolve();
      final launch = _launch(command);
      pty = _ptyFactory.spawn(
        launch.command,
        workingDirectory: _homeDirectory,
        environment: launch.environment,
        cols: cols,
        rows: rows,
      );
    } catch (error) {
      throw SpawnFailedException('$error');
    } finally {
      _pendingOpens--;
    }
    final voided = origin == SessionOrigin.phone
        ? epoch != _epoch
        : closeAllEpoch != _closeAllEpoch;
    if (voided) {
      pty.kill();
      return null;
    }
    final id = _nextId();
    final session = _Session(
      id: id,
      index: _lowestFreeIndex(),
      shell: command.name,
      createdAt: _clock(),
      pty: pty,
      stream: SessionStream(
        id: id,
        capacity: _bufferCapacity,
        sendWindow: _sendWindow,
        send: _send,
      ),
      cols: cols,
      rows: rows,
      origin: origin,
      driver: origin == SessionOrigin.phone
          ? DriverSide.phone
          : DriverSide.desktop,
    );
    session.notifier = _notifications?.forShell(
      sessionId: session.id,
      index: session.index,
    );
    _sessions[session.id] = session;
    session.pidKnown = _pidOf(session) != null;
    _watch(session);
    _portWatcher?.sessionsChanged();
    return session;
  }

  ShellLaunch _launch(ShellCommand command) {
    final environment = buildSessionEnvironment(_baseEnvironment);
    final integration = _shellIntegration;
    if (integration == null) return ShellLaunch(command, environment);
    try {
      return integration.apply(command, environment);
    } catch (_) {
      return ShellLaunch(command, environment);
    }
  }

  void _attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final session = _sessions[id];
    if (session == null || session.closing) {
      // A closing session (host-initiated close, or the shell already
      // exited) is not attachable: answering not_found here, instead of
      // letting the attach succeed, keeps `exitRecipient` intact so the
      // phone the host closed still gets `session.exited`.
      _notFound(mobileId, id);
      return;
    }
    final previous = session.stream.attach(mobileId, lastSeq);
    session.exitRecipient = null;
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    session.phoneCols = c;
    session.phoneRows = r;
    session.lastPhoneInput = null;
    if (lastSeq > 0) {
      // A resume after a dropped channel (the phone already has the
      // screen up to lastSeq): it only records its size, so a desktop
      // typing in this tab keeps the driver until the phone types or
      // resizes. The phone is told who drives, since it may remember
      // driving before the drop.
      if (session.driver == DriverSide.phone) _applySize(session, c, r);
      if (receivesDriver(mobileId)) {
        _send(mobileId, SessionDriver(id: id, by: session.driver));
      }
      _send(mobileId, SessionAttached(id: id));
      if (previous != mobileId) _changes.add(null);
      return;
    }
    _setDriver(session, DriverSide.phone); // A1 D6: a fresh attach drives.
    if (c == session.cols && r == session.rows) {
      // Same size: bounce the height so full-screen programs redraw.
      session.resize(c, r > _minDimension ? r - 1 : r + 1);
      session.resize(c, r);
    } else {
      session.cols = c;
      session.rows = r;
      session.resize(c, r);
    }
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) _changes.add(null);
  }

  /// The phone typed or resized. Typing takes the driver unless the window
  /// typed less than [_driverHold] ago; a resize always takes it.
  void _phoneActive(_Session session, {required bool input}) {
    final now = _clock();
    if (session.driver != DriverSide.phone) {
      if (input && _recent(session.lastLocalInput, now)) {
        session.lastPhoneInput = now;
        return;
      }
      _setDriver(session, DriverSide.phone);
    }
    if (input) session.lastPhoneInput = now;
    final c = session.phoneCols;
    final r = session.phoneRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  /// The window typed or resized (Task 2's `LocalSessionView`); mirror of
  /// [_phoneActive].
  void _localActive(_Session session, {required bool input}) {
    final now = _clock();
    if (session.driver != DriverSide.desktop) {
      if (input && _recent(session.lastPhoneInput, now)) {
        session.lastLocalInput = now;
        return;
      }
      _setDriver(session, DriverSide.desktop);
    }
    if (input) session.lastLocalInput = now;
    final c = session.localCols;
    final r = session.localRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  bool _recent(DateTime? at, DateTime now) =>
      at != null && now.difference(at) < _driverHold;

  /// Tells local viewers and an attached phone that understands it.
  void _setDriver(_Session session, DriverSide side) {
    if (session.driver == side) return;
    session.driver = side;
    if (!session.drivers.isClosed) session.drivers.add(side);
    final mobileId = session.attachedMobileId;
    if (mobileId != null && receivesDriver(mobileId)) {
      _send(mobileId, SessionDriver(id: session.id, by: side));
    }
    _changes.add(null);
  }

  void _applySize(_Session session, int cols, int rows) {
    if (cols == session.cols && rows == session.rows) return;
    session.cols = cols;
    session.rows = rows;
    session.resize(cols, rows);
  }

  /// The attached phone is gone (detach, channel loss, revoke, runtime
  /// stop): the desktop drives again, at the window's size when known.
  void _phoneLeft(_Session session) {
    session.attachedMobileId = null;
    session.phoneCols = null;
    session.phoneRows = null;
    session.lastPhoneInput = null;
    if (session.driver != DriverSide.phone) return;
    _setDriver(session, DriverSide.desktop);
    final c = session.localCols;
    final r = session.localRows;
    if (c != null && r != null) _applySize(session, c, r);
  }

  void _watch(_Session session) {
    final outputDone = Completer<void>();
    session.output = session.pty.output.listen(
      (data) {
        session.stream.append(data);
        if (!session.local.isClosed) session.local.add(data);
        _pump(session);
        session.notifier?.feed(data);
        _notePid(session);
        _track(session, data);
      },
      onDone: outputDone.complete,
      onError: (Object _) {},
    );
    session.pty.exitCode.then(
      (code) async {
        session.exited = true; // First: no kill/write/resize from here on.
        _shellGone(session);
        await outputDone.future.timeout(_outputDrainGrace, onTimeout: () {});
        _processExited(session, code);
      },
      onError: (Object _) {
        session.exited = true;
        _shellGone(session);
        _processExited(session, -1);
      },
    );
  }

  /// Title (OSC 0/2) and running command (OSC 133) from live output.
  void _track(_Session session, Uint8List data) {
    var changed = false;
    try {
      final title = session.titles.feed(data);
      if (title != null && title != session.title) {
        session.title = title;
        changed = true;
      }
      final wasRunning = session.commands.running;
      for (final event in session.commandEvents.feed(data)) {
        session.commands.handle(event);
        switch (event) {
          case CwdReported(:final url):
            if (_setCwd(session, url)) changed = true;
          case CommandFinished():
            _lookUpBranch(session, refresh: true); // git switch, git init…
          default:
            break;
        }
      }
      if (session.commands.running != wasRunning) changed = true;
    } catch (_) {
      // Parsing never breaks the session.
    }
    if (changed && !session.closing) _changes.add(null);
  }

  /// A2 C1/D2. True when the summary changed.
  bool _setCwd(_Session session, String url) {
    final reported = parseCwdUrl(
      url,
      windows: _windowsPaths,
      localHostName: _localHostName,
    );
    switch (reported) {
      case null:
        return false; // malformed: keep what we had
      case RemoteCwd():
        if (session.cwd == null && session.gitBranch == null) return false;
        session.cwd = null;
        session.gitBranch = null;
        session.branchGeneration++;
        return true;
      case LocalCwd(:final path):
        if (path == session.cwd) return false;
        session.cwd = path;
        // The old branch stays until the lookup answers (no flicker).
        _lookUpBranch(session, refresh: false);
        return true;
    }
  }

  void _lookUpBranch(_Session session, {required bool refresh}) {
    final git = _gitHeads;
    final cwd = session.cwd;
    if (git == null || cwd == null) return;
    final generation = ++session.branchGeneration;
    if (cwd.startsWith(r'\\')) {
      _setBranch(session, null, generation); // UNC: never looked up (§5)
      return;
    }
    unawaited(
      git
          .branchFor(cwd, refresh: refresh)
          .then<void>(
            (branch) => _setBranch(session, branch, generation),
            // Too slow: the branch is unknown, so the one shown stays (an
            // unknown answer is not "not a repo").
            onError: (Object _) {},
          ),
    );
  }

  void _setBranch(_Session session, String? branch, int generation) {
    if (generation != session.branchGeneration ||
        session.closing ||
        !identical(_sessions[session.id], session) ||
        branch == session.gitBranch) {
      return;
    }
    session.gitBranch = branch;
    _changes.add(null);
  }

  /// The shell process has exited. If nobody is attached, finishes right
  /// away as before. Otherwise, marks the session closing (spec item 4: it
  /// stops being listable/attachable from here on) and, if the send window
  /// still has buffered bytes to deliver, keeps draining as further acks
  /// arrive rather than dropping the tail — until it is fully drained, the
  /// phone detaches ([mobileDisconnected]), or [_drainTimeout] elapses.
  void _processExited(_Session session, int exitCode) {
    if (!session.exit.isCompleted) session.exit.complete(exitCode);
    if (!identical(_sessions[session.id], session)) return;
    session.closing = true;
    session.finishedExitCode = exitCode;
    _pump(session); // may already finish (and remove) the session below.
    if (!_sessions.containsKey(session.id)) return;
    if (session.attachedMobileId == null) {
      _finish(session);
      return;
    }
    session.drainTimer = Timer(_drainTimeout, () => _finish(session));
    _changes.add(null);
  }

  /// Removes the session and delivers `session.exited` to whoever should
  /// still hear about it. Safe to call more than once for the same session.
  void _finish(_Session session) {
    if (!identical(_sessions[session.id], session)) return;
    session.drainTimer?.cancel();
    session.drainTimer = null;
    final recipient = session.attachedMobileId ?? session.exitRecipient;
    _sessions.remove(session.id);
    session.ports = const [];
    _portWatcher?.sessionsChanged();
    session.output?.cancel();
    unawaited(session.local.close());
    unawaited(session.drivers.close());
    if (recipient != null) {
      _send(
        recipient,
        SessionExited(id: session.id, exitCode: session.finishedExitCode ?? -1),
      );
    }
    _changes.add(null);
  }

  /// Sends what the send window allows; once a closing session (its shell
  /// has exited) has handed every buffered byte out, hands off to [_finish].
  void _pump(_Session session) {
    if (session.attachedMobileId == null) return;
    session.stream.pump();
    if (session.closing && session.stream.drained) _finish(session);
  }

  _Session? _attachedTo(String mobileId, int id) {
    final session = _sessions[id];
    return session != null && session.attachedMobileId == mobileId
        ? session
        : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) {
    _send(
      mobileId,
      ErrorMessage(
        code: AppErrorCode.sessionNotFound,
        message: 'Session $id not found',
        id: id,
      ),
    );
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}

final class _LocalView implements LocalSessionView {
  _LocalView(this._manager, this._session)
    : backlog = _session.stream.buffered {
    _subscription = _session.local.stream.listen(
      _output.add,
      onDone: () => unawaited(_output.close()),
    );
  }

  final SessionManager _manager;
  final _Session _session;
  late final _output = StreamController<Uint8List>(
    onCancel: () => _subscription.cancel(),
  );
  late final StreamSubscription<Uint8List> _subscription;

  /// Set by [dispose]: a disposed (or replaced) view must never answer a
  /// cursor-position or device-attributes query a second time.
  bool _disposed = false;

  @override
  final Uint8List backlog;

  @override
  int get id => _session.id;
  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Stream<DriverSide> get driver => _session.drivers.stream;
  @override
  Future<int> get exitCode => _session.exit.future;
  @override
  bool get closedOnRequest => _session.killedOnRequest;

  @override
  void write(Uint8List data) {
    if (!_disposed) _manager._localWrite(_session, data);
  }

  @override
  void reply(Uint8List data) {
    if (!_disposed) _manager._localReply(_session, data);
  }

  @override
  void resize(int cols, int rows) {
    if (!_disposed) _manager._localResize(_session, cols, rows);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    if (!_output.isClosed) unawaited(_output.close());
  }
}
