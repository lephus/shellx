import '../model/notices.dart';
import '../model/session_state.dart';
import '../model/timeline.dart';

/// The session's turns that have a restore point: the first, the last (the
/// running one counts), the last finished one; and whether a turn runs.
typedef AiTurns = ({int? first, int? last, int? lastFinished, bool running});

/// V2-1 §4.4: [s]'s turns that have a restore point. Moved here from the
/// desktop's Changes panel for V2-2b, whose phone header (`undo`) and changes
/// (B19) read it too; the panel re-exports it.
AiTurns aiTurnsOf(AiSessionState s) {
  int? first, last, lastFinished;
  for (final item in s.timeline.items) {
    if (item is TurnEndItem && item.checkpoint != null) {
      first ??= item.turn;
      last = item.turn;
      lastFinished = item.turn;
    }
  }
  final running = s.turn;
  if (running != null && running.checkpoint != null) {
    first ??= running.index;
    last = running.index;
  }
  return (
    first: first,
    last: last,
    lastFinished: lastFinished,
    running: running != null,
  );
}

/// Why undo is off right now: the latest "undo is off" card of the
/// conversation that is still open; null when undo works.
UndoUnavailable? aiUndoOffOf(AiSessionState s) {
  final items = s.timeline.items;
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (item is! NoticeItem || item.resolved) continue;
    final notice = item.notice;
    if (notice is UndoUnavailable) return notice;
  }
  return null;
}

/// V2-2b §4.2 (`undo` of the phone's header): no turn of [s] has a restore
/// point and the conversation says why — the Changes panel's own rule for
/// "undo is off".
bool aiUndoIsOff(AiSessionState s) =>
    aiTurnsOf(s).last == null && aiUndoOffOf(s) != null;
