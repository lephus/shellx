import 'package:shellx_mobile/features/notifications/domain/push_messaging.dart';

/// V2-2b B10: a tap on "Cho phép" or "Từ chối" of an AI permission push, as the answer it stands for. Only the
/// two answers the desktop put in the push (B7: the first "allow once" that turns on no mode acting without
/// asking, and the first "reject once") can ever come out of it, never another option.
final class PushAnswer {
  const PushAnswer._({
    required this.agentId,
    required this.sid,
    required this.permission,
    required this.option,
    required this.allow,
    required this.task,
  });

  /// The computer that asked (`agent_id`, added by the relay).
  final String agentId;

  /// The AI session (`ai_session`).
  final String sid;

  /// The permission request (`perm`): a number the window never uses twice in a run (B3).
  final int permission;

  /// The option id to send: the push's `allow` or `reject`.
  final String option;

  /// The user tapped "Cho phép" (else "Từ chối").
  final bool allow;

  /// What the request does ("Sửa src/main.ts"), read from the push's body (R6); null when it says nothing.
  final String? task;

  /// The heads the desktop puts before the request in the body (`NotificationText.aiNeedsInput`), followed by
  /// ": " and the request, or alone when the request has no title.
  static const List<String> _heads = ['Cần bạn trả lời', 'Needs your answer'];

  static final RegExp _digits = RegExp(r'^[0-9]{1,15}$');

  /// The answer [message] carries, or null: not a button of an AI permission push (a tap on its body, a
  /// command's push), or data that is not exactly what the desktop sends — then nothing is answered.
  static PushAnswer? of(PushMessage message) {
    final action = message.action;
    if (action != 'allow' && action != 'reject') return null;
    final data = message.data;
    if (data['kind'] != 'ai') return null;
    final agentId = message.agentId;
    final sid = message.aiSession;
    final perm = data['perm'];
    final allow = data['allow'];
    final reject = data['reject'];
    if (agentId == null || sid == null || perm == null || !_digits.hasMatch(perm)) return null;
    // Both answers come together, or the push has no buttons at all (B7).
    if (allow == null || allow.isEmpty || reject == null || reject.isEmpty) return null;
    return PushAnswer._(
      agentId: agentId,
      sid: sid,
      permission: int.parse(perm),
      option: action == 'allow' ? allow : reject,
      allow: action == 'allow',
      task: taskOf(message.body),
    );
  }

  /// R6: the request a push's [body] names, without the head ("Cần bạn trả lời: Sửa src/main.ts" → "Sửa
  /// src/main.ts"); the whole body when it has another head; null when it is empty.
  static String? taskOf(String? body) {
    final text = body?.trim() ?? '';
    for (final head in _heads) {
      if (text == head) return null;
      if (text.startsWith('$head:')) {
        final task = text.substring(head.length + 1).trim();
        return task.isEmpty ? null : task;
      }
    }
    return text.isEmpty ? null : text;
  }

  /// Never the request or the ids.
  @override
  String toString() => 'PushAnswer(…)';
}
