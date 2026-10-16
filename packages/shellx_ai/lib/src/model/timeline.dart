import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';
import 'notices.dart';

/// One entry of the conversation. Items are mutable; [rev] goes up on each
/// change so a view redraws only what changed.
sealed class TimelineItem with Redacted {
  TimelineItem(this.turn);

  /// The turn the item belongs to (0 = before the first prompt).
  final int turn;
  int rev = 0;
}

/// V2-2b B24: who wrote a prompt — the user at the computer, or the user
/// on a paired phone (the window's phone hub sends it).
enum PromptSource { computer, phone }

final class UserItem extends TimelineItem {
  UserItem(
    super.turn,
    List<ContentBlock> blocks, {
    this.messageId,
    this.source = PromptSource.computer,
  }) : blocks = [...blocks];

  final List<ContentBlock> blocks;
  final String? messageId;

  /// Where the prompt was written (B24). A conversation replayed by
  /// `session/load` does not say: its prompts read as the computer's.
  final PromptSource source;

  String get text => blockText(blocks);
}

/// Text that arrives in chunks and is merged (spec D9).
sealed class StreamedTextItem extends TimelineItem {
  StreamedTextItem(super.turn, {this.messageId});

  final String? messageId;
  final _text = StringBuffer();

  String get text => _text.toString();

  void append(String s) {
    _text.write(s);
    rev++;
  }
}

/// Agent text (`agent_message_chunk`).
final class AgentTextItem extends StreamedTextItem {
  AgentTextItem(super.turn, {super.messageId});
}

/// A thought (`agent_thought_chunk`), folded by default (spec §4.2).
final class ThoughtItem extends StreamedTextItem {
  ThoughtItem(super.turn, {super.messageId});
}

/// How a tool call ended.
enum ToolEnd {
  completed,
  failed,

  /// The turn was cancelled or the agent stopped while it ran.
  stopped,
}

/// One tool call card, updated in place by `toolCallId` (spec D9, §4.2).
final class ToolItem extends TimelineItem {
  ToolItem(super.turn, this.toolCallId, this.fields, {required this.startedAt});

  final String toolCallId;
  ToolCallFields fields;
  final DateTime startedAt;
  DateTime? endedAt;
  ToolEnd? end;

  /// A permission request for this call is waiting.
  bool awaitingPermission = false;

  /// What the user picked ("Bạn chọn: Cho phép (Yes)").
  PermissionOption? permissionAnswer;

  /// The turn was cancelled while the request was open.
  bool permissionCancelled = false;
}

/// A question from the agent (spec D22).
final class AskItem extends TimelineItem {
  AskItem(super.turn, this.id, this.request, {this.autoDeclined = false});

  final int id;
  final ElicitationRequest request;

  /// Declined without asking: the form uses a type ShellX cannot show.
  final bool autoDeclined;
  ElicitationResponse? response;

  /// A URL question the agent reported done (`elicitation/complete`).
  bool completed = false;
}

enum TurnOutcome {
  /// The agent ended the turn (any stop reason but `cancelled`).
  finished,
  cancelled,

  /// The agent process ended during the turn.
  interrupted,

  /// `session/prompt` answered an error.
  failed,
}

/// The summary card at the end of a turn (spec §4.2).
final class TurnEndItem extends TimelineItem {
  TurnEndItem(
    super.turn, {
    required this.outcome,
    required this.elapsed,
    this.stopReason,
    this.error,
    this.checkpoint,
    this.afterTree,
    this.changes,
  });

  final TurnOutcome outcome;
  final Duration elapsed;
  final StopReason? stopReason;

  /// The agent's error message: shown, never logged.
  final String? error;

  /// The project before the turn; null when undo was off.
  final Checkpoint? checkpoint;

  /// The project right after the turn ("đã sửa sau lượt" compares to it).
  final String? afterTree;

  /// What the turn changed (checkpoint → after); null without checkpoint.
  final List<FileChange>? changes;
}

final class NoticeItem extends TimelineItem {
  NoticeItem(super.turn, this.notice);

  final AiNotice notice;

  /// The problem went away; the card may fold.
  bool resolved = false;
}

/// The conversation of one session (spec D9).
final class Timeline with Redacted {
  final List<TimelineItem> items = [];
  final Map<String, ToolItem> _tools = {};

  /// The current turn; a prompt or a replayed user message starts the next.
  int turn = 0;

  ToolItem? tool(String toolCallId) => _tools[toolCallId];

  void add(TimelineItem item) => items.add(item);

  UserItem startTurn(
    List<ContentBlock> prompt, {
    String? messageId,
    PromptSource source = PromptSource.computer,
  }) {
    turn++;
    final item = UserItem(turn, prompt, messageId: messageId, source: source);
    items.add(item);
    return item;
  }

  /// Applies a message, thought or tool update; false for other kinds.
  bool apply(SessionUpdate update, DateTime at) {
    switch (update) {
      case UserMessageChunk(:final content, :final messageId):
        final last = items.isEmpty ? null : items.last;
        if (last is UserItem &&
            last.turn == turn &&
            last.messageId == messageId) {
          last.blocks.add(content);
          last.rev++;
        } else {
          startTurn([content], messageId: messageId);
        }
        return true;
      case AgentMessageChunk(:final content, :final messageId):
        _appendText(content, messageId, thought: false);
        return true;
      case AgentThoughtChunk(:final content, :final messageId):
        _appendText(content, messageId, thought: true);
        return true;
      case ToolCallStarted(:final toolCallId, :final fields):
      case ToolCallUpdated(:final toolCallId, :final fields):
        toolFor(toolCallId, fields, at);
        return true;
      default:
        return false;
    }
  }

  /// The card of [toolCallId] with [fields] merged in; a new card goes at
  /// the end of the timeline.
  ToolItem toolFor(String toolCallId, ToolCallFields fields, DateTime at) {
    var item = _tools[toolCallId];
    if (item == null) {
      item = ToolItem(turn, toolCallId, fields, startedAt: at);
      _tools[toolCallId] = item;
      items.add(item);
    } else {
      item.fields = item.fields.merge(fields);
    }
    switch (fields.status) {
      case ToolCallStatus.completed:
        item.end = ToolEnd.completed;
        item.endedAt ??= at;
      case ToolCallStatus.failed:
        item.end = ToolEnd.failed;
        item.endedAt ??= at;
      default:
        break;
    }
    item.rev++;
    return item;
  }

  /// Marks every call that has not ended as stopped.
  void stopOpenTools(DateTime at) {
    for (final t in _tools.values) {
      if (t.end != null) continue;
      t
        ..end = ToolEnd.stopped
        ..endedAt = at
        ..awaitingPermission = false
        ..rev += 1;
    }
  }

  void _appendText(
    ContentBlock content,
    String? messageId, {
    required bool thought,
  }) {
    final text = switch (content) {
      TextBlock(:final text) => text,
      ResourceLinkBlock(:final name, :final uri) => '[$name]($uri)',
      _ => '',
    };
    if (text.isEmpty) return;
    final last = items.isEmpty ? null : items.last;
    if (thought) {
      if (last is ThoughtItem &&
          last.turn == turn &&
          last.messageId == messageId) {
        last.append(text);
      } else {
        items.add(ThoughtItem(turn, messageId: messageId)..append(text));
      }
    } else if (last is AgentTextItem &&
        last.turn == turn &&
        last.messageId == messageId) {
      last.append(text);
    } else {
      items.add(AgentTextItem(turn, messageId: messageId)..append(text));
    }
  }
}
