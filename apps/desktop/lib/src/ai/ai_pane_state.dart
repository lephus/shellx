import 'package:flutter/foundation.dart';

/// V2-1 D2: what a tab mainly holds.
enum TabKind { terminal, ai }

/// V2-1 D3: AI pane ids are negative, counted down from -1 by the tab list
/// and never reused in a run. Session ids (the daemon counts from 1) and
/// tab ids (session ids, or the synthetic range from 2e9) are positive, so
/// the spaces never meet. A negative pane id must never reach
/// `LocalSessions`, the terminal links, or restore's `keyOf` (which negates
/// tab ids for a displaced tab, A11 D20).
bool isAiPaneId(int id) => id < 0;

const Object _unset = Object();

/// The tab list's record of an AI pane (V2-1 D2, D3, D14). The conversation
/// lives in the pane's runtime (`ai/ai_runtimes.dart`), never here; nothing
/// here is ever logged ([toString] is `…`, D20).
@immutable
final class AiPaneState {
  const AiPaneState({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.title,
    this.cwd,
    this.sessionId,
  });

  /// The pane's leaf id in its tab's tree: negative.
  final int id;

  /// A catalog id (`claude`, `codex`, `gemini`, `opencode`) or a custom
  /// agent's id.
  final String agentId;

  /// What the header, the sidebar and notifications call the agent
  /// ("Claude", never "Claude Code": D21).
  final String agentName;

  /// The automatic tab title (D2): the session title, else the first
  /// prompt (40 characters), else "New AI session" in the app language.
  final String title;

  /// The project folder; null until the user chooses one (D5).
  final String? cwd;

  /// The agent's session; a runtime made while it is set reopens it with
  /// `session/load` (D14, D15). Null before the first session exists.
  final String? sessionId;

  AiPaneState copyWith({
    String? title,
    Object? cwd = _unset,
    Object? sessionId = _unset,
  }) => AiPaneState(
    id: id,
    agentId: agentId,
    agentName: agentName,
    title: title ?? this.title,
    cwd: identical(cwd, _unset) ? this.cwd : cwd as String?,
    sessionId: identical(sessionId, _unset)
        ? this.sessionId
        : sessionId as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is AiPaneState &&
      other.id == id &&
      other.agentId == agentId &&
      other.agentName == agentName &&
      other.title == title &&
      other.cwd == cwd &&
      other.sessionId == sessionId;

  @override
  int get hashCode =>
      Object.hash(id, agentId, agentName, title, cwd, sessionId);

  @override
  String toString() => '…';
}
