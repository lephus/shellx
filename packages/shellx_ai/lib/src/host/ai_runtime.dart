import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/changes.dart';
import '../model/notices.dart';
import '../model/session_state.dart';
import '../model/timeline.dart';
import 'agent_catalog.dart';
import 'agent_process.dart';
import 'checkpoint_store.dart';

/// What an AI tab reports to the A12 status model (spec D13).
enum AiStatus { running, needsInput, idle, ended }

/// One AI tab. Starts the agent and opens (or loads) its session. Takes a
/// checkpoint before every turn, sends prompts, answers permissions and
/// questions through [state], cancels and stops (spec D6–D16).
///
/// It runs on the app's UI isolate, so nothing here blocks: the agent, git and
/// the file system are all reached asynchronously. [start], [restart],
/// [retry], [send] and [dispose] do not throw when the agent or the
/// checkpoints misbehave: the tab shows a card instead. The settings and
/// revert calls do throw what failed, so the caller knows it was not applied.
final class AiRuntime with Redacted {
  AiRuntime({
    required this.state,
    required Future<AgentReadiness> Function() resolve,
    required AgentLauncher launch,
    required this.clientVersion,
    Future<(Checkpoints?, UndoOff?)> Function()? checkpoints,
    String? resumeSessionId,
    this.preferredConfig = const {},
    this.initializeTimeout = const Duration(seconds: 30),
    this.cancelGrace = const Duration(seconds: 10),
    DateTime Function()? now,
    String? sessionKey,
  }) : _resolve = resolve,
       _launch = launch,
       _checkpoints = checkpoints,
       _resumeId = resumeSessionId,
       _now = now ?? DateTime.now,
       _key =
           sessionKey ??
           's${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  final AiSessionState state;
  final String clientVersion;

  /// Remembered choices per agent (spec D11), applied to new sessions.
  final Map<String, Object> preferredConfig;
  final Duration initializeTimeout;
  final Duration cancelGrace;

  /// A12 status changes, without repeats.
  void Function(AiStatus status)? onStatus;

  final Future<AgentReadiness> Function() _resolve;
  final AgentLauncher _launch;
  final Future<(Checkpoints?, UndoOff?)> Function()? _checkpoints;
  final DateTime Function() _now;
  final String _key;
  String? _resumeId;
  AgentCommand? _command;
  AgentChannel? _channel;

  /// The agent that ran last, kept for its log after it exited.
  AgentChannel? _exited;
  AcpClient? _client;
  Future<void>? _starting;
  Future<void>? _disposing;
  var _expectExit = false;
  var _forced = false;
  ConnectionCloseReason? _garbled;
  var _loading = false;
  var _keepTimeline = false;
  var _disposed = false;
  Checkpoints? _store;
  Future<void>? _warmup;
  Checkpoint? _firstCheckpoint;
  final _turnCheckpoints = <int, Checkpoint>{};
  final _afterTrees = <int, String>{};
  Timer? _cancelTimer;
  Completer<Checkpoint?>? _turnCancel;
  final _permissions = <int, Completer<PermissionOutcome>>{};
  final _asks = <int, Completer<ElicitationResponse>>{};
  final _idle = <Completer<void>>[];
  AiStatus? _lastStatus;

  /// What the agent wrote to stderr ("Xem log"). The last agent's log stays
  /// after it exited: that is when the crash card offers it.
  String get stderrTail => (_channel ?? _exited)?.stderrTail ?? '';

  // ---------------------------------------------------------- lifecycle --

  /// Starts the agent and opens (or loads) the session. A restored tab
  /// calls this when it is first shown (spec D14). Never throws: a problem
  /// becomes a card and the phase `failed`.
  Future<void> start() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<void> _start() async {
    if (_disposed) return;
    switch (state.phase) {
      case AgentPhase.starting ||
          AgentPhase.ready ||
          AgentPhase.running ||
          AgentPhase.needsAuth:
        return;
      case AgentPhase.stopped || AgentPhase.failed:
        break;
    }
    state.setPhase(AgentPhase.starting);
    state.resolveNotices((n) => n is! UndoUnavailable && n is! CannotResume);
    final folderThere = await Directory(state.cwd).exists();
    if (_disposed) return _gone();
    if (!folderThere) return _fail(const FolderMissing());
    final AgentReadiness readiness;
    try {
      readiness = await _resolve();
    } on Object {
      return _fail(const StartFailed(StartFailure.spawn));
    }
    if (_disposed) return _gone();
    switch (readiness) {
      case AgentReady(:final command):
        _command = command;
      case AgentNeedsNode(:final required, :final found):
        return _fail(NodeMissing(required: required, found: found));
      case AgentNeedsInstall(:final install):
        return _fail(AgentNotInstalled(canInstall: install != null));
      case AgentNotFound(:final command, :final shimOnly):
        return _fail(AgentMissing(command, shimOnly: shimOnly));
    }
    final AgentChannel channel;
    try {
      channel = await _launch(_command!, cwd: state.cwd);
    } on Object {
      return _fail(const StartFailed(StartFailure.spawn));
    }
    if (_disposed) {
      // The tab went away while its process was starting: nobody will use it.
      await channel.stop();
      return _gone();
    }
    _channel = channel;
    final client =
        AcpClient(
            JsonRpcConnection(input: channel.stdout, output: channel.stdin),
          )
          ..onUpdate = _onUpdate
          ..onPermission = _onPermission
          ..onElicitation = _onElicitation
          ..onElicitationComplete = state.completeUrlAsk;
    _client = client;
    unawaited(channel.exitCode.then((code) => _onExit(channel, code)));
    // Output ShellX cannot read stops the agent (spec §6).
    unawaited(
      client.connection.done.then((reason) {
        if (identical(_client, client) &&
            (reason == ConnectionCloseReason.lineTooLong ||
                reason == ConnectionCloseReason.tooManyBadLines)) {
          _garbled = reason;
          unawaited(channel.kill());
        }
      }),
    );
    final InitializeResult init;
    try {
      init = await client
          .initialize(clientVersion: clientVersion)
          .timeout(initializeTimeout);
    } on TimeoutException {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.timeout));
    } on JsonRpcError {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.protocol));
    } on ConnectionClosed {
      return; // _onExit has reported it.
    }
    if (init.protocolVersion != 1) {
      await _stopAgent();
      return _fail(const StartFailed(StartFailure.protocol));
    }
    state.setAgent(init);
    await _openSession();
  }

  Future<void> _openSession() async {
    final client = _client;
    if (client == null) return;
    final resume = _resumeId;
    var fresh = false;
    try {
      if (resume != null && state.capabilities.loadSession) {
        _loading = true;
        _keepTimeline = state.timeline.items.isNotEmpty;
        final r = await client.loadSession(sessionId: resume, cwd: state.cwd);
        state.setSession(
          resume,
          configOptions: r.configOptions,
          modes: r.modes,
        );
      } else {
        if (resume != null) {
          // Said once, whatever comes next (a sign-in, a retry).
          _resumeId = null;
          state.addNotice(const CannotResume());
        }
        final r = await client.newSession(cwd: state.cwd);
        if (r.sessionId.isEmpty) {
          await _stopAgent();
          return _fail(const StartFailed(StartFailure.protocol));
        }
        state.setSession(
          r.sessionId,
          configOptions: r.configOptions,
          modes: r.modes,
        );
        await _applyPreferred();
      }
    } on JsonRpcError catch (e) {
      if (e.code == JsonRpcError.authRequired) {
        // One open card: a retry that is still signed out replaces the old.
        state.resolveNotices((n) => n is LoginNeeded);
        state.addNotice(LoginNeeded(state.authMethods));
        state.setPhase(AgentPhase.needsAuth);
        _wakeIdle(force: true);
        return;
      }
      if (resume != null && e.code == JsonRpcError.resourceNotFound) {
        fresh = true;
      } else {
        await _stopAgent();
        return _fail(const StartFailed(StartFailure.session));
      }
    } on ConnectionClosed {
      return;
    } finally {
      _loading = false;
      _keepTimeline = false;
    }
    if (fresh) {
      _resumeId = null;
      state.addNotice(const CannotResume());
      return _openSession();
    }
    _resumeId = state.sessionId;
    state.resolveNotices((n) => n is LoginNeeded);
    state.setPhase(AgentPhase.ready);
    _warmCheckpoints();
    if (!_drainQueue()) _wakeIdle();
  }

  /// Applies remembered choices; never "Bypass permissions" (ruling R6).
  Future<void> _applyPreferred() async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    for (final MapEntry(key: id, :value) in preferredConfig.entries) {
      final option = state.configOptions?.where((o) => o.id == id).firstOrNull;
      if (option == null || option.currentValue == value) continue;
      final valid = switch (option.kind) {
        ConfigKind.select =>
          value is String && option.choices.any((c) => c.value == value),
        ConfigKind.boolean => value is bool,
        ConfigKind.other => false,
      };
      final bypass =
          (option.category == 'mode' || option.id == 'mode') &&
          value == 'bypassPermissions';
      if (!valid || bypass) continue;
      try {
        await _applyConfig(client, sid, id, value);
      } on JsonRpcError {
        // Keep the agent's value.
      }
    }
  }

  Future<void> _applyConfig(
    AcpClient client,
    String sid,
    String id,
    Object value,
  ) async {
    final updated = await client.setConfigOption(sid, id, value);
    state.configOptions =
        updated ??
        [
          for (final o in state.configOptions ?? const <ConfigOption>[])
            o.id == id ? o.withValue(value) : o,
        ];
    state.touch();
  }

  /// The first snapshot of a project runs in the background (spec D12).
  void _warmCheckpoints() {
    final get = _checkpoints;
    if (get == null || _warmup != null) return;
    _warmup = () async {
      final (Checkpoints?, UndoOff?) found;
      try {
        found = await get();
      } on Object {
        // Without the answer there is no undo; say so, the turns still run.
        state.addNotice(const UndoUnavailable(UndoOff.failed));
        return;
      }
      final (store, off) = found;
      if (store == null) {
        if (off != null) state.addNotice(UndoUnavailable(off));
        return;
      }
      _store = store;
      final ck = store.off == null ? await store.snapshot('$_key/0') : null;
      final reason = store.off;
      if (ck == null && reason != null) {
        state.addNotice(UndoUnavailable(reason));
      }
    }().catchError((Object _) {});
  }

  /// "Khởi động lại": a new agent process, then `session/load`.
  Future<void> restart() async {
    if (_disposed) return;
    await _stopAgent();
    // A start under way ends with the agent it had (its pipe closes) or, if it
    // had none yet, with a whole new one; wait, then stop what it left.
    final starting = _starting;
    if (starting != null) {
      await starting.then<void>((_) {}, onError: (Object _) {});
      await _stopAgent();
    }
    if (_disposed) return;
    state.setPhase(AgentPhase.stopped);
    await start();
  }

  /// After the run sheet's login exits 0, or after the setup is fixed
  /// (spec D8): a live agent reopens the session; otherwise start again.
  Future<void> retry() async {
    if (state.phase == AgentPhase.needsAuth && _client != null) {
      state.setPhase(AgentPhase.starting);
      await _openSession();
      return;
    }
    if (state.phase == AgentPhase.failed || state.phase == AgentPhase.stopped) {
      await start();
    }
  }

  /// For an agent-type login method: `authenticate`, then the session. False
  /// unless the agent is waiting for a sign-in and the session then opens.
  Future<bool> authenticate(String methodId) async {
    final client = _client;
    if (client == null || state.phase != AgentPhase.needsAuth) return false;
    try {
      await client.authenticate(methodId);
    } on JsonRpcError {
      return false;
    } on ConnectionClosed {
      return false;
    }
    // A second call, a retry or a restart may have got there first.
    if (state.phase != AgentPhase.needsAuth || !identical(client, _client)) {
      return state.phase == AgentPhase.ready;
    }
    state.setPhase(AgentPhase.starting);
    await _openSession();
    return state.phase == AgentPhase.ready;
  }

  /// The run sheet's command for a terminal login: the agent's own command
  /// plus the method's args and env (spec D8). Null before a resolve.
  AgentCommand? loginCommand(AuthMethodTerminal method) =>
      _command?.withArgs(method.args, method.env);

  /// Stops the agent and ends every turn and wait. Safe to call twice.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _cancelTimer?.cancel();
    await _stopAgent();
    _wakeIdle(force: true);
  }

  // -------------------------------------------------------------- turns --

  /// Sends [prompt], or queues it while a turn runs or the agent starts
  /// (at most 5, spec D16). False when it cannot be taken.
  Future<bool> send(List<ContentBlock> prompt) async {
    if (_disposed) return false;
    switch (state.phase) {
      case AgentPhase.ready:
        unawaited(_runTurn(prompt));
        return true;
      case AgentPhase.running || AgentPhase.starting:
        return state.enqueue(prompt) != null;
      case AgentPhase.stopped:
        if (state.enqueue(prompt) == null) return false;
        unawaited(start());
        return true;
      case AgentPhase.needsAuth || AgentPhase.failed:
        return false;
    }
  }

  Future<void> _runTurn(List<ContentBlock> prompt) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    final turn = state.beginTurn(prompt, _now());
    final cancelled = _turnCancel = Completer<Checkpoint?>();
    _status(AiStatus.running);
    final warmup = _warmup;
    if (warmup != null) await Future.any<void>([warmup, cancelled.future]);
    final store = _store;
    if (store != null && store.off == null && !turn.cancelRequested) {
      final snap = store
          .snapshot('$_key/${turn.index}')
          .catchError((Object _) => null);
      final ck = await Future.any<Checkpoint?>([snap, cancelled.future]);
      if (!turn.cancelRequested) {
        if (ck == null) {
          state.addNotice(
            UndoUnavailable(
              store.off ?? UndoOff.failed,
              turnOnly: store.off == null,
            ),
          );
        } else {
          turn.checkpoint = ck;
          _turnCheckpoints[turn.index] = ck;
          _firstCheckpoint ??= ck;
        }
      }
    }
    if (turn.cancelRequested) {
      // Stopped before the prompt went out: nothing to tell the agent.
      return _finishTurn(
        turn,
        TurnOutcome.cancelled,
        stopReason: StopReason.cancelled,
      );
    }
    try {
      final reason = await client.prompt(sid, prompt);
      await _finishTurn(
        turn,
        reason == StopReason.cancelled
            ? TurnOutcome.cancelled
            : TurnOutcome.finished,
        stopReason: reason,
      );
    } on JsonRpcError catch (e) {
      await _finishTurn(turn, TurnOutcome.failed, error: e.message);
    } on ConnectionClosed {
      // The agent is gone: _onExit ends the turn.
    }
  }

  Future<void> _finishTurn(
    ActiveTurn turn,
    TurnOutcome outcome, {
    StopReason? stopReason,
    String? error,
  }) async {
    if (!identical(state.turn, turn)) return;
    final endedAt = _now();
    _cancelTimer?.cancel();
    _cancelTimer = null;
    _cancelPending();
    String? after;
    List<FileChange>? changes;
    final store = _store;
    final ck = turn.checkpoint;
    if (store != null && ck != null) {
      // The undo data is a bonus: it never holds the turn up or fails it.
      after = await store.currentTree().catchError((Object _) => null);
      if (after != null) {
        _afterTrees[turn.index] = after;
        changes = await store
            .changes(ck.tree, after)
            .catchError((Object _) => <FileChange>[]);
      }
    }
    if (!identical(state.turn, turn)) return;
    // A question that came in while the turn was wrapped up is settled too:
    // nothing may wait for an answer once its turn is over.
    _cancelPending();
    state.endTurn(
      outcome: outcome,
      at: endedAt,
      stopReason: stopReason,
      error: error,
      afterTree: after,
      changes: changes,
    );
    if (!_drainQueue()) {
      _status(AiStatus.idle);
      _wakeIdle();
    }
  }

  bool _drainQueue() {
    if (state.phase != AgentPhase.ready || _client == null) return false;
    final next = state.takeQueued();
    if (next == null) return false;
    unawaited(_runTurn(next.blocks));
    return true;
  }

  /// Stop (Esc): `session/cancel`, and every open question is answered
  /// `cancelled`. After [cancelGrace], "Dừng hẳn" is offered (spec §1.4).
  void cancel() {
    final turn = state.turn;
    if (turn == null || turn.cancelRequested) return;
    turn.cancelRequested = true;
    final sid = state.sessionId;
    if (sid != null) _client?.cancel(sid);
    _cancelPending();
    final c = _turnCancel;
    if (c != null && !c.isCompleted) c.complete(null);
    _cancelTimer = Timer(cancelGrace, () {
      if (identical(state.turn, turn)) {
        turn.canForceStop = true;
        state.touch();
      }
    });
    state.touch();
  }

  /// "Dừng hẳn": kill the agent. The turn ends as stopped, and the next
  /// prompt restarts the agent with `session/load`.
  Future<void> forceStop() async {
    final channel = _channel;
    if (channel == null) return;
    _forced = true;
    await channel.kill();
  }

  /// Completes when no turn runs and nothing is queued, or when nothing can
  /// run without the user (the agent ended, failed or waits for a sign-in).
  Future<void> whenIdle() {
    if (_isIdle) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  bool get _isIdle => switch (state.phase) {
    AgentPhase.starting => false,
    AgentPhase.stopped || AgentPhase.failed || AgentPhase.needsAuth => true,
    AgentPhase.ready ||
    AgentPhase.running => state.turn == null && state.queue.isEmpty,
  };

  void _wakeIdle({bool force = false}) {
    if (!force && !_isIdle) return;
    for (final c in _idle) {
      if (!c.isCompleted) c.complete();
    }
    _idle.clear();
  }

  // ------------------------------------------------- agent → user asks --

  Future<PermissionOutcome> _onPermission(PermissionRequest request) {
    if (state.turn?.cancelRequested ?? false) {
      return Future.value(const PermissionCancelled());
    }
    final p = state.addPermission(request, _now());
    final c = Completer<PermissionOutcome>();
    _permissions[p.id] = c;
    _status(AiStatus.needsInput);
    return c.future;
  }

  /// The user's pick on the permission bar; null = cancelled.
  void answerPermission(int id, String? optionId) => _answerPermission(
    id,
    optionId == null
        ? const PermissionCancelled()
        : PermissionSelected(optionId),
  );

  void _answerPermission(
    int id,
    PermissionOutcome outcome, {
    bool quiet = false,
  }) {
    final c = _permissions.remove(id);
    if (c == null) return;
    state.resolvePermission(id, outcome);
    c.complete(outcome);
    if (!quiet) _afterAnswer();
  }

  Future<ElicitationResponse> _onElicitation(ElicitationRequest request) {
    if (state.turn?.cancelRequested ?? false) {
      return Future.value(const ElicitCancel());
    }
    if (request is ElicitationOther ||
        (request is ElicitationForm && !request.supported)) {
      state.addAsk(request, autoDeclined: true);
      return Future.value(const ElicitDecline());
    }
    final a = state.addAsk(request)!;
    final c = Completer<ElicitationResponse>();
    _asks[a.id] = c;
    _status(AiStatus.needsInput);
    return c.future;
  }

  /// The user's answer to a question card (spec D22).
  void answerAsk(int id, ElicitationResponse response) =>
      _answerAsk(id, response);

  void _answerAsk(int id, ElicitationResponse response, {bool quiet = false}) {
    final c = _asks.remove(id);
    if (c == null) return;
    state.resolveAsk(id, response);
    c.complete(response);
    if (!quiet) _afterAnswer();
  }

  /// The user answered: back to what the tab was doing before it asked.
  void _afterAnswer() {
    if (state.needsInput) return;
    _status(state.turn != null ? AiStatus.running : AiStatus.idle);
  }

  void _cancelPending() {
    for (final id in [..._permissions.keys]) {
      _answerPermission(id, const PermissionCancelled(), quiet: true);
    }
    for (final id in [..._asks.keys]) {
      _answerAsk(id, const ElicitCancel(), quiet: true);
    }
  }

  void _onUpdate(String sessionId, SessionUpdate update) {
    final current = state.sessionId;
    if (!_loading && current != null && sessionId != current) return;
    state.applyUpdate(
      update,
      _now(),
      history: _loading,
      timelineToo: !(_loading && _keepTimeline),
    );
  }

  // ------------------------------------------------------------- config --

  /// Sends the choice; the state follows the agent's answer. Throws what the
  /// agent answered, so the caller knows it was not applied.
  Future<void> setConfig(String configId, Object value) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    await _applyConfig(client, sid, configId, value);
  }

  /// For agents with only legacy `modes` (spec D11).
  Future<void> setMode(String modeId) async {
    final client = _client;
    final sid = state.sessionId;
    if (client == null || sid == null) return;
    await client.setMode(sid, modeId);
    state.modes = state.modes?.withCurrent(modeId);
    state.touch();
  }

  /// `session/list` for this folder (spec D15); null when not offered.
  Future<ListSessionsResult?> listSessions({String? cursor}) async {
    final client = _client;
    if (client == null || !state.capabilities.listSessions) return null;
    try {
      return await client.listSessions(cwd: state.cwd, cursor: cursor);
    } on JsonRpcError {
      return null;
    } on ConnectionClosed {
      return null;
    }
  }

  // --------------------------------------------------------------- undo --

  /// The checkpoint taken before [turn]; null when undo was off for it.
  Checkpoint? checkpointOf(int turn) => _turnCheckpoints[turn];

  /// The disk now against the checkpoint before [turn] ("Lượt này"). Null
  /// when there is none or the store could not answer.
  Future<List<FileChange>?> changesSince(int turn) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    return ck == null || store == null
        ? null
        : _undoRead(() => store.changes(ck.tree));
  }

  /// The disk now against the first checkpoint ("Cả phiên").
  Future<List<FileChange>?> sessionChanges() async {
    final ck = _firstCheckpoint;
    final store = _store;
    return ck == null || store == null
        ? null
        : _undoRead(() => store.changes(ck.tree));
  }

  /// Files changed since [turn] ended ("đã sửa sau lượt").
  Future<Set<String>?> changedAfterTurn(int turn) async {
    final after = _afterTrees[turn];
    final store = _store;
    return after == null || store == null
        ? null
        : _undoRead(() => store.changedSince(after));
  }

  /// Puts [paths] back as they were before [turn]. Refused while a turn runs.
  Future<bool> revert(int turn, Iterable<String> paths) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    if (ck == null || store == null || state.turn != null) return false;
    await store.restore(ck.commit, paths);
    return true;
  }

  /// Puts [paths] back as they were before the first turn.
  Future<bool> revertSession(Iterable<String> paths) async {
    final ck = _firstCheckpoint;
    final store = _store;
    if (ck == null || store == null || state.turn != null) return false;
    await store.restore(ck.commit, paths);
    return true;
  }

  /// [path] as it was before [turn]; null when it did not exist then.
  Future<List<int>?> fileBefore(int turn, String path) async {
    final ck = _turnCheckpoints[turn];
    final store = _store;
    return ck == null || store == null
        ? null
        : _undoRead<List<int>?>(() => store.fileAt(ck.tree, path));
  }

  /// A question to the store: null when it cannot answer (git failed). The
  /// panels draw "nothing to show" rather than an error.
  Future<T?> _undoRead<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  // ------------------------------------------------------------ process --

  Future<void> _stopAgent() async {
    final channel = _channel;
    if (channel == null) return;
    _expectExit = true;
    await channel.stop();
    await channel.exitCode;
  }

  void _onExit(AgentChannel channel, int code) {
    if (!identical(channel, _channel)) return;
    _channel = null;
    _exited = channel;
    _client = null;
    _cancelTimer?.cancel();
    _cancelPending();
    final garbled = _garbled;
    final stopped = (_expectExit || _forced) && garbled == null;
    if (state.turn != null) {
      state.endTurn(
        outcome: stopped ? TurnOutcome.cancelled : TurnOutcome.interrupted,
        at: _now(),
        stopReason: stopped ? StopReason.cancelled : null,
      );
    }
    if (stopped) {
      state.setPhase(AgentPhase.stopped);
    } else {
      state.addNotice(
        garbled != null ? AgentOutputInvalid(garbled) : AgentExited(code),
      );
      state.setPhase(AgentPhase.failed);
    }
    _expectExit = false;
    _forced = false;
    _garbled = null;
    _status(AiStatus.ended);
    _wakeIdle(force: true);
  }

  void _fail(AiNotice notice) {
    if (_disposed) return _gone();
    state.addNotice(notice);
    state.setPhase(AgentPhase.failed);
    _wakeIdle(force: true);
  }

  /// The tab was disposed while its agent was starting.
  void _gone() {
    state.setPhase(AgentPhase.stopped);
    _wakeIdle(force: true);
  }

  void _status(AiStatus status) {
    if (_lastStatus == status) return;
    _lastStatus = status;
    onStatus?.call(status);
  }
}
