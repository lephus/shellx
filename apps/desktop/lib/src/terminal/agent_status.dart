import 'package:flutter/foundation.dart';

/// A12 D9: how long a running agent's pane may stay silent before it counts
/// as idle (its spinner always prints, so silence means it stopped).
const Duration kAgentQuietDecay = Duration(seconds: 20);

/// A12 D4: the events of one pane at most this many per second.
const int kAgentEventsPerSecond = 20;

/// A12 D4: the longest message kept, in characters.
const int kAgentMessageMax = 1024;

/// A12 D4: an `at` this far from now is the sender's clock being wrong.
const Duration kAgentClockSkew = Duration(minutes: 10);

/// The agents ShellX knows by name (wire names: the enum names).
enum AgentKind { claude, codex, gemini, opencode }

enum AgentState { running, needsInput, idle, done, unknown }

/// Wire names: start / running / needs_input / idle / end / notice.
enum AgentEventKind { start, running, needsInput, idle, end, notice }

/// A session id may enter a command only after this (A12 constraints).
final RegExp kSessionId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

bool isValidSessionId(String s) => kSessionId.hasMatch(s);

/// One report from an agent's hook, already validated. Its words come from
/// a process the user does not control: [toString] shows nothing.
@immutable
final class AgentEvent {
  const AgentEvent({
    required this.pane,
    required this.agent,
    required this.kind,
    required this.at,
    this.session,
    this.message,
    this.ok = true,
  });

  final int pane;
  final AgentKind agent;
  final AgentEventKind kind;
  final DateTime at;

  /// Already matched against [kSessionId].
  final String? session;

  /// Already cleaned and clipped.
  final String? message;
  final bool ok;

  @override
  String toString() => '…';
}

/// What ShellX knows about the agent in one pane.
@immutable
final class AgentPane {
  const AgentPane({
    required this.agent,
    required this.state,
    required this.since,
    required this.lastEventAt,
    this.session,
    this.runningSince,
  });

  final AgentKind agent;
  final AgentState state;

  /// When [state] began.
  final DateTime since;

  /// The `at` of the newest event applied (older ones are ignored).
  final DateTime lastEventAt;
  final String? session;

  /// When the current turn began (set by `running`, kept while it waits for
  /// the user); null when no turn is under way.
  final DateTime? runningSince;

  AgentPane copyWith({
    AgentKind? agent,
    AgentState? state,
    DateTime? since,
    DateTime? lastEventAt,
    String? session,
    Object? runningSince = _keep,
  }) => AgentPane(
    agent: agent ?? this.agent,
    state: state ?? this.state,
    since: since ?? this.since,
    lastEventAt: lastEventAt ?? this.lastEventAt,
    session: session ?? this.session,
    runningSince: identical(runningSince, _keep)
        ? this.runningSince
        : runningSince as DateTime?,
  );

  static const Object _keep = Object();

  @override
  String toString() => '…';
}

/// A12 D9. null = no record (the agent ended, or never reported).
AgentPane? reduceAgent(
  AgentPane? prev,
  AgentEvent e, {
  required bool paneVisible,
}) {
  // Hook processes can finish in another order than they started.
  if (prev != null && e.at.isBefore(prev.lastEventAt)) return prev;
  switch (e.kind) {
    case AgentEventKind.end:
      return null;
    case AgentEventKind.notice:
      return prev; // a word, not a state
    case AgentEventKind.start:
      return AgentPane(
        agent: e.agent,
        state: AgentState.idle,
        since: e.at,
        lastEventAt: e.at,
        session: e.session,
      );
    case AgentEventKind.running:
      final already = prev?.state == AgentState.running;
      return AgentPane(
        agent: e.agent,
        state: AgentState.running,
        since: already ? prev!.since : e.at,
        lastEventAt: e.at,
        session: e.session ?? prev?.session,
        runningSince: already ? (prev!.runningSince ?? e.at) : e.at,
      );
    case AgentEventKind.needsInput:
      return AgentPane(
        agent: e.agent,
        state: AgentState.needsInput,
        since: prev?.state == AgentState.needsInput ? prev!.since : e.at,
        lastEventAt: e.at,
        session: e.session ?? prev?.session,
        runningSince: prev?.runningSince,
      );
    case AgentEventKind.idle:
      // The agent still waits for an answer: an "idle prompt" reminder does
      // not make the question go away. Typing, a new prompt or the end do.
      if (prev != null && prev.state == AgentState.needsInput) {
        return prev.copyWith(
          lastEventAt: e.at,
          session: e.session ?? prev.session,
        );
      }
      final next = paneVisible ? AgentState.idle : AgentState.done;
      return AgentPane(
        agent: e.agent,
        state: next,
        since: prev?.state == next ? prev!.since : e.at,
        lastEventAt: e.at,
        session: e.session ?? prev?.session,
        runningSince: prev?.runningSince,
      );
  }
}

/// The user typed into the pane: an answered question is a running agent.
AgentPane userTyped(AgentPane p, DateTime now) =>
    p.state != AgentState.needsInput
    ? p
    : p.copyWith(
        state: AgentState.running,
        since: now,
        runningSince: p.runningSince ?? now,
      );

/// The pane is in view: "done" has been seen.
AgentPane paneSeen(AgentPane p, DateTime now) => p.state != AgentState.done
    ? p
    : p.copyWith(state: AgentState.idle, since: now);

/// The pane printed nothing for [kAgentQuietDecay] (the caller decides).
AgentPane quietFor(AgentPane p, DateTime now) => p.state != AgentState.running
    ? p
    : p.copyWith(state: AgentState.idle, since: now, runningSince: null);

/// needsInput > running > done > idle > unknown.
AgentState aggregate(Iterable<AgentState> states) {
  const order = [
    AgentState.needsInput,
    AgentState.running,
    AgentState.done,
    AgentState.idle,
    AgentState.unknown,
  ];
  final seen = states.toSet();
  for (final s in order) {
    if (seen.contains(s)) return s;
  }
  return AgentState.unknown;
}

/// Whether [s] shows anywhere (restored `unknown` records do not).
bool agentStateVisible(AgentState s) => s != AgentState.unknown;

/// The wire/CLI word of a state: running / needs_input / idle / done.
String agentStateWire(AgentState s) => switch (s) {
  AgentState.running => 'running',
  AgentState.needsInput => 'needs_input',
  AgentState.idle => 'idle',
  AgentState.done => 'done',
  AgentState.unknown => 'unknown',
};

const _eventNames = {
  'start': AgentEventKind.start,
  'running': AgentEventKind.running,
  'needs_input': AgentEventKind.needsInput,
  'idle': AgentEventKind.idle,
  'end': AgentEventKind.end,
  'notice': AgentEventKind.notice,
};

/// Direction marks, embeds/isolates, line and paragraph separators.
final RegExp _bidi = RegExp(
  r'[\u200e\u200f\u202a-\u202e\u2066-\u2069\u2028\u2029]',
);
final RegExp _controls = RegExp(r'[\x00-\x1F\x7F\u0080-\u009F]');

/// A12 D4: controls become spaces, bidi marks go, at most
/// [kAgentMessageMax] characters; blank is none.
String? cleanAgentMessage(Object? raw) {
  if (raw is! String) return null;
  final t = String.fromCharCodes(
    raw
        .replaceAll(_bidi, '')
        .replaceAll(_controls, ' ')
        .runes
        .take(kAgentMessageMax),
  ).trim();
  return t.isEmpty ? null : t;
}

/// A12 D4: the request's fields, checked again (the sender is not trusted).
/// null = `bad_request` (pane, agent or event unusable). A bad `session` is
/// dropped but the event is kept; an `at` away from [now] by more than
/// [kAgentClockSkew] is replaced by [now]. Extra keys are ignored.
AgentEvent? decodeAgentEvent(
  Map<String, Object?> fields, {
  required DateTime now,
}) {
  final pane = fields['pane'];
  if (pane is! int) return null;
  final agent = switch (fields['agent']) {
    final String name => AgentKind.values.where((a) => a.name == name),
    _ => const <AgentKind>[],
  }.firstOrNull;
  if (agent == null) return null;
  final kind = switch (fields['event']) {
    final String name => _eventNames[name],
    _ => null,
  };
  if (kind == null) return null;
  var at = now;
  final sent = fields['at'];
  if (sent is int) {
    final candidate = DateTime.fromMillisecondsSinceEpoch(sent, isUtc: true);
    if (candidate.difference(now.toUtc()).abs() <= kAgentClockSkew) {
      at = candidate;
    }
  }
  final session = fields['session'];
  return AgentEvent(
    pane: pane,
    agent: agent,
    kind: kind,
    at: at,
    session: session is String && isValidSessionId(session) ? session : null,
    message: cleanAgentMessage(fields['message']),
    ok: fields['ok'] != false,
  );
}
