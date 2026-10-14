import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-2 §5: the words of AI sessions on the phone (the desktop's V2-1 §4
/// wording, said the same way).
abstract final class AiWords {
  /// A session's state in a list or header.
  static String state(S s, AiRemoteState state) => switch (state) {
    AiRemoteState.running => s.aiStateRunning,
    AiRemoteState.needsInput => s.aiStateNeedsInput,
    AiRemoteState.idle => s.aiStateIdle,
    AiRemoteState.starting => s.aiStateStarting,
    AiRemoteState.stopped => s.aiStateStopped,
    AiRemoteState.needsAuth => s.aiStateNeedsAuth,
    AiRemoteState.failed => s.aiStateFailed,
    AiRemoteState.noFolder => s.aiStateNoFolder,
    AiRemoteState.agentOff => s.aiStateAgentOff,
  };

  /// The header's state: what the desktop's runtime phase and the pending
  /// requests say (the same rule as `aiRemoteStateOf`: a waiting permission
  /// or question shows only while the agent is ready or running).
  static AiRemoteState headState(MirrorHead head) {
    if (head.unavailable != null) return head.unavailable!;
    final waiting = head.permission != null || head.ask != null;
    return switch (head.phase) {
      'ready' || 'running' when waiting => AiRemoteState.needsInput,
      'running' => AiRemoteState.running,
      'ready' => AiRemoteState.idle,
      'starting' => AiRemoteState.starting,
      'needsAuth' => AiRemoteState.needsAuth,
      'failed' => AiRemoteState.failed,
      _ => AiRemoteState.stopped,
    };
  }

  /// "0:12", "3:05", "1:02:03".
  static String clock(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  /// V2-1 D10: the main label of a permission option by kind; the agent's
  /// own words when the kind is unknown.
  static String option(S s, PermissionOption o) => switch (o.kind) {
    PermissionKind.allowOnce => s.aiPermAllowOnce,
    PermissionKind.allowAlways => s.aiPermAllowAlways,
    PermissionKind.rejectOnce => s.aiPermRejectOnce,
    PermissionKind.rejectAlways => s.aiPermRejectAlways,
    PermissionKind.other => o.name,
  };

  /// V2-1 D11: Claude's known mode ids in the app's words; others as sent.
  static String? mode(S s, MirrorHead head) => switch (head.modeId) {
    'default' => s.aiModeDefault,
    'acceptEdits' => s.aiModeAcceptEdits,
    'plan' => s.aiModePlan,
    'auto' => s.aiModeAuto,
    'bypassPermissions' => s.aiModeBypass,
    _ => head.modeName,
  };

  /// The last part of [path] ("src/main.ts" → "main.ts"), both separators.
  static String fileName(String path) {
    final parts = path.split(RegExp(r'[\\/]'))..removeWhere((p) => p.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  /// `mcp__server__tool` → "server · tool" (V2-1 §4.2).
  static String toolName(String title) {
    final m = RegExp(r'^mcp__([^_]+(?:_[^_]+)*)__(.+)$').firstMatch(title);
    return m == null ? title : '${m.group(1)} · ${m.group(2)}';
  }

  /// A tool card's one line (V2-1 §4.2): a verb and what it acts on.
  static String toolTitle(S s, MirrorTool t) {
    final location = t.locations.isEmpty ? null : t.locations.first.path;
    final diff = t.diffs.isEmpty ? null : t.diffs.first;
    final title = t.title ?? '';
    final target = location != null
        ? fileName(location)
        : diff != null
        ? fileName(diff.path)
        : title;
    return switch (t.kind) {
      ToolKind.read => s.aiToolRead(target),
      ToolKind.edit when diff != null && diff.oldText == null => s.aiToolCreate(target),
      ToolKind.edit => s.aiToolEdit(target),
      ToolKind.delete => s.aiToolDelete(target),
      ToolKind.move => s.aiToolMove(target),
      ToolKind.search => s.aiToolSearch(title),
      ToolKind.fetch => s.aiToolFetch(title),
      ToolKind.execute => s.aiToolExecute(title),
      ToolKind.think => s.aiThought,
      ToolKind.switchMode => s.aiToolSwitchMode,
      ToolKind.other || null => toolName(title),
    };
  }

  /// A notice card's text (V2-1 §4.5).
  static String notice(S s, MirrorNotice n, String agent) {
    int arg(String key) => n.args[key] is int ? n.args[key]! as int : 0;
    return switch (n.kind) {
      'login' => s.aiNoticeLogin(agent),
      'node' => s.aiNoticeNode(agent, arg('required')),
      'not_installed' => s.aiNoticeNotInstalled(agent),
      'missing' => s.aiNoticeMissing(agent),
      'exited' => s.aiNoticeExited(agent, arg('code')),
      'invalid' => s.aiNoticeInvalid(agent),
      'start_failed' => s.aiNoticeStartFailed(agent),
      'cannot_resume' => s.aiNoticeCannotResume,
      'folder_missing' => s.aiNoticeFolderMissing,
      'undo_off' => s.aiNoticeUndoOff,
      _ => s.aiNoticeOther,
    };
  }

  /// What a failed request shows (`ai.result` codes, V2-2 §4.6); null when
  /// nothing needs saying (a stop that came after the turn ended: the
  /// header already shows it). [answer]: the request was an answer.
  ///
  /// `not_found` and `unavailable` are also how a request in flight ends when its session closes or the
  /// window quits. A lost channel is no code but a `MachineConnectionException`: the caller words it
  /// `offline`.
  static String? failure(S s, String code, {bool answer = false}) => switch (code) {
    'stale' => answer ? s.aiAnsweredElsewhere : null,
    'queue_full' => s.aiQueueFull,
    'too_large' => s.aiTooLong(kAiMaxPromptKb),
    'offline' => s.aiReconnecting,
    'unavailable' => s.aiUnavailable,
    'not_found' || 'gone' => s.aiClosedGone,
    _ => s.aiRequestFailed(code),
  };

  /// What the strip of a closed session says (`AiSessionHandle.closedReason`): `desktop_closed`
  /// (ShellX quit on the computer), `unavailable` (no window serves AI), `unreadable` (the computer
  /// keeps sending what this version cannot read: see it there). `gone`, `detached`, a newer
  /// computer's word or none: the session is closed on the computer.
  static String closed(S s, String? reason) => switch (reason) {
    'desktop_closed' => s.aiClosedDesktop,
    'unavailable' => s.aiUnavailable,
    'unreadable' => s.aiClosedUnreadable,
    _ => s.aiClosedGone,
  };

  /// A permission that came without options (the computer leaves them out when its header would not
  /// fit a message) is answered on the computer; null when there are buttons to show.
  static String? permissionOnComputer(S s, MirrorPermission permission) =>
      permission.options.isEmpty ? s.aiPermOnComputer : null;

  /// A card the phone cannot draw: `big` was too large to send, any other kind is a newer computer's.
  /// Either way it is read on the computer.
  static String itemOnComputer(S s, MirrorUnknown item) =>
      item.kind == 'big' ? s.aiFromComputerOnly : s.aiItemOnComputer;

  /// The prompt limit in KB, for [S.aiTooLong].
  static const int kAiMaxPromptKb = 32;
}
