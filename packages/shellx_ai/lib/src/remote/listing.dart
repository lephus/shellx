import 'package:shellx_acp/shellx_acp.dart';

import '../model/session_state.dart';
import 'wire.dart';

/// A session's state in a phone's lists and header (V2-2 §4.3). The words
/// on the wire are [wire]; an unknown word reads as [idle].
enum AiRemoteState {
  running('running'),
  needsInput('needs_input'),
  idle('idle'),
  starting('starting'),
  stopped('stopped'),
  needsAuth('needs_auth'),
  failed('failed'),

  /// The AI tab has no project folder yet (V2-1 D5): chosen on the computer.
  noFolder('no_folder'),

  /// Its agent is switched off or removed in Settings › Agents.
  agentOff('agent_off');

  const AiRemoteState(this.wire);

  final String wire;

  static AiRemoteState parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => idle);
}

// The longest strings a listing carries, in UTF-8 bytes. A title, a path or
// a name can be as long as an agent or a folder makes it; a message cannot
// (V2-2 D4), and one that is too big drops the phone's whole channel.
const int _titleBytes = 200;
const int _acpIdBytes = 200;
const int _pathBytes = 600;
const int _nameBytes = 200;
const int _waitingBytes = 240;

/// What [state] shows a phone: a waiting permission or question wins.
AiRemoteState aiRemoteStateOf(AiSessionState state) => switch (state.phase) {
  AgentPhase.stopped => AiRemoteState.stopped,
  AgentPhase.starting => AiRemoteState.starting,
  AgentPhase.needsAuth => AiRemoteState.needsAuth,
  AgentPhase.failed => AiRemoteState.failed,
  AgentPhase.ready ||
  AgentPhase.running when state.needsInput => AiRemoteState.needsInput,
  AgentPhase.ready => AiRemoteState.idle,
  AgentPhase.running => AiRemoteState.running,
};

/// What the agent waits for, in one line ("Sửa src/main.ts"); null when
/// nothing waits.
String? aiWaitingOf(AiSessionState state) {
  final permission = state.currentPermission;
  if (permission != null) return clipText(permission.title, 240);
  final ask = state.currentAsk;
  if (ask != null) return clipText(ask.request.message, 240);
  return null;
}

/// One AI session in a phone's list.
final class AiSessionInfo with Redacted {
  const AiSessionInfo({
    required this.sid,
    required this.agentId,
    required this.agentName,
    required this.title,
    required this.state,
    this.cwd,
    this.since,
    this.waiting,
    this.acpSessionId,
  });

  /// The desktop's handle for the session (opaque to the phone).
  final String sid;
  final String agentId;

  /// "Claude", "Codex"… (V2-1 D21: never "Claude Code").
  final String agentName;

  /// The tab title (V2-1 D2); empty for a session with none yet.
  final String title;
  final AiRemoteState state;
  final String? cwd;

  /// When the running turn started (ms since epoch), for "Đang chạy · 0:12".
  final int? since;

  /// What the agent waits for while [state] is [AiRemoteState.needsInput].
  final String? waiting;

  /// The agent's own session id: after a desktop restart the phone finds
  /// the same session again under its new [sid].
  final String? acpSessionId;

  /// The long strings are cut (see the limits above); [sid] and [agentId]
  /// are keys the phone sends back, and go whole.
  Map<String, Object?> toJson() => {
    'sid': sid,
    'agent': agentId,
    'name': clipText(agentName, _nameBytes),
    'title': clipText(title, _titleBytes),
    'state': state.wire,
    if (cwd != null) 'cwd': clipText(cwd!, _pathBytes),
    if (since != null) 'since': since,
    if (waiting != null) 'waiting': clipText(waiting!, _waitingBytes),
    if (acpSessionId != null) 'acp': clipText(acpSessionId!, _acpIdBytes),
  };

  /// Null without a `sid`.
  static AiSessionInfo? fromJson(Map<String, Object?> j) {
    final sid = jString(j, 'sid');
    if (sid == null || sid.isEmpty) return null;
    return AiSessionInfo(
      sid: sid,
      agentId: jString(j, 'agent') ?? '',
      agentName: jString(j, 'name') ?? '',
      title: jString(j, 'title') ?? '',
      state: AiRemoteState.parse(jString(j, 'state')),
      cwd: jString(j, 'cwd'),
      since: jInt(j, 'since'),
      waiting: jString(j, 'waiting'),
      acpSessionId: jString(j, 'acp'),
    );
  }
}

/// An agent a phone may start a session with.
final class AiAgentChoice with Redacted {
  const AiAgentChoice({
    required this.id,
    required this.name,
    this.ready = true,
  });

  final String id;
  final String name;

  /// False: installed but not usable now (needs install, Node…); shown
  /// greyed with "Cài trên máy tính".
  final bool ready;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': clipText(name, _nameBytes),
    'ready': ready,
  };

  static AiAgentChoice? fromJson(Map<String, Object?> j) {
    final id = jString(j, 'id');
    if (id == null || id.isEmpty) return null;
    return AiAgentChoice(
      id: id,
      name: jString(j, 'name') ?? id,
      ready: j['ready'] != false,
    );
  }
}

/// A folder a phone may start a session in: a key the desktop made, never
/// a path the phone chose (V2-2 D9).
final class AiFolderChoice with Redacted {
  const AiFolderChoice({required this.key, required this.name, this.path});

  final String key;

  /// The workspace's name, else the folder's.
  final String name;
  final String? path;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': clipText(name, _nameBytes),
    if (path != null) 'path': clipText(path!, _pathBytes),
  };

  static AiFolderChoice? fromJson(Map<String, Object?> j) {
    final key = jString(j, 'key');
    if (key == null || key.isEmpty) return null;
    return AiFolderChoice(
      key: key,
      name: jString(j, 'name') ?? key,
      path: jString(j, 'path'),
    );
  }
}

/// A desktop's AI sessions, and what a new one may use (`ai.list.result`).
final class AiListing with Redacted {
  const AiListing({
    this.available = true,
    this.sessions = const [],
    this.agents = const [],
    this.folders = const [],
    this.defaultAgent,
  });

  /// No window serves AI (`available: false` on the envelope).
  static const unavailable = AiListing(available: false);

  /// From the envelope (`AiListResult.available`), not the body.
  final bool available;
  final List<AiSessionInfo> sessions;
  final List<AiAgentChoice> agents;
  final List<AiFolderChoice> folders;
  final String? defaultAgent;

  /// Sessions waiting for the user.
  int get needsInput =>
      sessions.where((s) => s.state == AiRemoteState.needsInput).length;

  Map<String, Object?> toJson() => {
    'v': kAiWireVersion,
    'sessions': [for (final s in sessions) s.toJson()],
    'agents': [for (final a in agents) a.toJson()],
    'folders': [for (final f in folders) f.toJson()],
    if (defaultAgent != null) 'default_agent': defaultAgent,
  };

  static AiListing fromJson(
    Map<String, Object?> j, {
    required bool available,
  }) => AiListing(
    available: available,
    sessions: [
      for (final s in jMaps(j, 'sessions')) ?AiSessionInfo.fromJson(s),
    ],
    agents: [for (final a in jMaps(j, 'agents')) ?AiAgentChoice.fromJson(a)],
    folders: [for (final f in jMaps(j, 'folders')) ?AiFolderChoice.fromJson(f)],
    defaultAgent: jString(j, 'default_agent'),
  );
}
