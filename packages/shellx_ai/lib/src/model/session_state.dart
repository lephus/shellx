import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';
import 'notices.dart';
import 'timeline.dart';

enum AgentPhase { stopped, starting, needsAuth, ready, running, failed }

/// V2-2b B3: the id of the next permission, question or queued prompt — one
/// counter for the whole run of the process, shared by every
/// [AiSessionState]. A phone names a request by (session id, request id), and
/// a session id outlives the runtime it names: a pane whose runtime is
/// replaced (a folder chosen again, its agent switched off and on) gets a new
/// state. With a counter per state, the new runtime's first request would be
/// 0 again, and a late answer to the old runtime's request 0 would land on
/// it. Never goes back in a run.
var _nextRequestId = 0;

/// The turn in progress.
final class ActiveTurn with Redacted {
  ActiveTurn(this.index, this.startedAt);

  final int index;
  final DateTime startedAt;
  bool cancelRequested = false;

  /// Stop did not end the turn in time: offer "Dừng hẳn" (spec §1.4).
  bool canForceStop = false;

  /// Taken before the prompt went out; null when undo is off.
  Checkpoint? checkpoint;
}

/// A permission request, shown one at a time in order (spec D10).
final class PendingPermission with Redacted {
  PendingPermission(this.id, this.request, this.item);

  final int id;
  final PermissionRequest request;
  final ToolItem item;

  /// The card's title, else the request's (spec §6).
  String get title => item.fields.title ?? request.toolCall.title ?? '';
}

final class PendingAsk with Redacted {
  PendingAsk(this.id, this.item);

  final int id;
  final AskItem item;

  ElicitationRequest get request => item.request;
}

/// A prompt sent while a turn runs; it goes out when the turn ends (D16).
final class QueuedPrompt with Redacted {
  QueuedPrompt(this.id, this.blocks);

  final int id;
  final List<ContentBlock> blocks;

  String get text => blockText(blocks);
}

/// Everything one AI tab shows. The desktop runtime (and the phone, V2-2)
/// changes it; views listen and redraw.
final class AiSessionState with Redacted {
  AiSessionState({
    required this.agentId,
    required this.agentName,
    required this.cwd,
  });

  static const maxQueue = 5;

  final String agentId;
  final String agentName;
  String cwd;

  AgentPhase phase = AgentPhase.stopped;
  String? sessionId;
  String? title;

  /// What `initialize` returned.
  InitializeResult? agent;
  final timeline = Timeline();
  List<PlanEntry> plan = const [];
  List<AvailableCommand> commands = const [];
  List<ConfigOption>? configOptions;
  SessionModes? modes;
  Usage? usage;
  ActiveTurn? turn;
  final List<PendingPermission> permissions = [];
  final List<PendingAsk> asks = [];
  final List<QueuedPrompt> queue = [];

  /// Goes up on every change.
  int version = 0;
  final _listeners = <void Function()>[];

  AgentCapabilities get capabilities =>
      agent?.capabilities ?? const AgentCapabilities();

  List<AuthMethod> get authMethods => agent?.authMethods ?? const [];

  /// A permission or a question waits for the user (A12 "Cần bạn").
  bool get needsInput => permissions.isNotEmpty || asks.isNotEmpty;

  PendingPermission? get currentPermission =>
      permissions.isEmpty ? null : permissions.first;

  PendingAsk? get currentAsk => asks.isEmpty ? null : asks.first;

  /// The tab title (spec D2): the session title, else the first prompt
  /// (spaces collapsed, 40 characters), else null ("Phiên AI mới").
  String? get label {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    for (final item in timeline.items) {
      if (item is! UserItem) continue;
      final text = item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final runes = text.runes.toList();
      return runes.length <= 40
          ? text
          : '${String.fromCharCodes(runes.take(40))}…';
    }
    return null;
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Something changed: bump [version] and tell the listeners.
  void touch() {
    version++;
    for (final l in [..._listeners]) {
      l();
    }
  }

  void setPhase(AgentPhase value) {
    if (phase == value) return;
    phase = value;
    touch();
  }

  void setAgent(InitializeResult result) {
    agent = result;
    touch();
  }

  void setSession(
    String id, {
    List<ConfigOption>? configOptions,
    SessionModes? modes,
  }) {
    sessionId = id;
    if (configOptions != null) this.configOptions = configOptions;
    if (modes != null) this.modes = modes;
    touch();
  }

  /// Applies one `session/update`.
  ///
  /// [history]: replayed by `session/load`, so user messages start turns.
  /// [timelineToo]: false drops message and tool updates, for a restart
  /// whose replay repeats what the timeline already shows.
  void applyUpdate(
    SessionUpdate update,
    DateTime at, {
    bool history = false,
    bool timelineToo = true,
  }) {
    switch (update) {
      case PlanUpdated(:final entries):
        plan = entries;
      case CommandsUpdated(:final commands):
        this.commands = commands;
      case ModeUpdated(:final currentModeId):
        modes = modes?.withCurrent(currentModeId);
      case ConfigUpdated(:final options):
        configOptions = options;
      case SessionInfoUpdated(:final hasTitle, title: final newTitle):
        if (hasTitle) title = newTitle;
      case UsageUpdated(:final usage):
        this.usage = usage;
      case UnknownUpdate():
        return;
      case UserMessageChunk() when !history && turn != null:
        return;
      default:
        if (!timelineToo) return;
        timeline.apply(update, at);
    }
    touch();
  }

  /// Starts a turn: the prompt joins the timeline.
  ActiveTurn beginTurn(List<ContentBlock> prompt, DateTime at) {
    timeline.startTurn(prompt);
    final t = ActiveTurn(timeline.turn, at);
    turn = t;
    phase = AgentPhase.running;
    touch();
    return t;
  }

  /// Ends the turn in progress with its summary card. Calls still open are
  /// stopped unless the agent finished the turn itself.
  TurnEndItem? endTurn({
    required TurnOutcome outcome,
    required DateTime at,
    StopReason? stopReason,
    String? error,
    String? afterTree,
    List<FileChange>? changes,
  }) {
    final t = turn;
    if (t == null) return null;
    if (outcome != TurnOutcome.finished) timeline.stopOpenTools(at);
    final item = TurnEndItem(
      t.index,
      outcome: outcome,
      elapsed: at.difference(t.startedAt),
      stopReason: stopReason,
      error: error,
      checkpoint: t.checkpoint,
      afterTree: afterTree,
      changes: changes,
    );
    timeline.add(item);
    turn = null;
    if (phase == AgentPhase.running) phase = AgentPhase.ready;
    touch();
    return item;
  }

  /// Queues a permission request; its card is created from the request
  /// when the agent sent none (spec §6).
  PendingPermission addPermission(PermissionRequest request, DateTime at) {
    final item = timeline.toolFor(request.toolCallId, request.toolCall, at)
      ..awaitingPermission = true;
    final p = PendingPermission(_nextRequestId++, request, item);
    permissions.add(p);
    touch();
    return p;
  }

  void resolvePermission(int id, PermissionOutcome outcome) {
    final i = permissions.indexWhere((p) => p.id == id);
    if (i < 0) return;
    final p = permissions.removeAt(i);
    final item = p.item
      ..awaitingPermission = permissions.any((q) => identical(q.item, p.item));
    switch (outcome) {
      case PermissionSelected(:final optionId):
        item.permissionAnswer = p.request.options
            .where((o) => o.optionId == optionId)
            .firstOrNull;
      case PermissionCancelled():
        item.permissionCancelled = true;
    }
    item.rev++;
    touch();
  }

  /// Adds a question card; null (and already answered `decline`) when
  /// [autoDeclined].
  PendingAsk? addAsk(ElicitationRequest request, {bool autoDeclined = false}) {
    final item = AskItem(
      timeline.turn,
      _nextRequestId++,
      request,
      autoDeclined: autoDeclined,
    );
    timeline.add(item);
    if (autoDeclined) {
      item.response = const ElicitDecline();
      touch();
      return null;
    }
    final a = PendingAsk(item.id, item);
    asks.add(a);
    touch();
    return a;
  }

  void resolveAsk(int id, ElicitationResponse response) {
    final i = asks.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = asks.removeAt(i);
    a.item
      ..response = response
      ..rev += 1;
    touch();
  }

  void completeUrlAsk(String elicitationId) {
    var changed = false;
    for (final item in timeline.items) {
      if (item is AskItem &&
          item.request is ElicitationUrl &&
          (item.request as ElicitationUrl).elicitationId == elicitationId) {
        item
          ..completed = true
          ..rev += 1;
        changed = true;
      }
    }
    if (changed) touch();
  }

  NoticeItem addNotice(AiNotice notice) {
    final item = NoticeItem(timeline.turn, notice);
    timeline.add(item);
    touch();
    return item;
  }

  /// Folds the open notices [test] matches (the problem is solved).
  void resolveNotices(bool Function(AiNotice notice) test) {
    var changed = false;
    for (final item in timeline.items) {
      if (item is NoticeItem && !item.resolved && test(item.notice)) {
        item
          ..resolved = true
          ..rev += 1;
        changed = true;
      }
    }
    if (changed) touch();
  }

  /// Null when [maxQueue] prompts already wait.
  QueuedPrompt? enqueue(List<ContentBlock> blocks) {
    if (queue.length >= maxQueue) return null;
    final q = QueuedPrompt(_nextRequestId++, [...blocks]);
    queue.add(q);
    touch();
    return q;
  }

  void removeQueued(int id) {
    final before = queue.length;
    queue.removeWhere((q) => q.id == id);
    if (queue.length != before) touch();
  }

  QueuedPrompt? takeQueued() {
    if (queue.isEmpty) return null;
    final q = queue.removeAt(0);
    touch();
    return q;
  }
}
