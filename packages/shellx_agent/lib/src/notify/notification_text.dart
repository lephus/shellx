import 'command_tracker.dart';

/// Notification wording (push spec §4.2): Vietnamese when the computer's
/// language is `vi`, English otherwise.
final class NotificationText {
  NotificationText(String locale)
    : vietnamese = locale.trim().toLowerCase().startsWith('vi');

  final bool vietnamese;

  /// "Phiên 2" / "Session 2" (a ShellX session).
  String shellSession(int index) =>
      vietnamese ? 'Phiên $index' : 'Session $index';

  /// `<app> — <window title>`, or the app name when the title is empty
  /// (a shared desktop terminal).
  String desktopSession(String app, String title) =>
      title.trim().isEmpty ? app : '$app — $title';

  /// `<machine> · <session>`; either part may be empty.
  String title(String machine, String session) {
    final m = machine.trim();
    final s = session.trim();
    if (m.isEmpty) return s.isEmpty ? 'ShellX' : s;
    return s.isEmpty ? m : '$m · $s';
  }

  /// `✓ <command> · <time>` or `✗ <command> · mã <n> · <time>`.
  String commandBody(CompletedCommand command) {
    final line = _singleLine(command.commandLine);
    final name = line.isEmpty ? (vietnamese ? 'Lệnh' : 'Command') : line;
    final time = duration(command.duration);
    if (command.exitCode == 0) return '✓ $name · $time';
    final code = vietnamese ? 'mã' : 'exit';
    return '✗ $name · $code ${command.exitCode} · $time';
  }

  /// V2-2 D11: "Cần bạn trả lời: Sửa src/main.ts" / "Needs your answer: …"
  /// (just the first part without [detail]).
  String aiNeedsInput(String? detail) {
    final d = _singleLine(detail);
    final head = vietnamese ? 'Cần bạn trả lời' : 'Needs your answer';
    return d.isEmpty ? head : '$head: $d';
  }

  /// V2-2 D11: "Xong lượt 3 · 4 phút 2 giây" / "Finished turn 3 · 4 min 2 s".
  String aiDone(int turn, Duration elapsed) => vietnamese
      ? 'Xong lượt $turn · ${duration(elapsed)}'
      : 'Finished turn $turn · ${duration(elapsed)}';

  /// "45 giây", "3 phút 12 giây", "1 giờ 4 phút" (en: "45 s", "3 min
  /// 12 s", "1 h 4 min"). Whole seconds; a zero part is left out.
  String duration(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final (hu, mu, su) = vietnamese
        ? ('giờ', 'phút', 'giây')
        : ('h', 'min', 's');
    if (h > 0) return m == 0 ? '$h $hu' : '$h $hu $m $mu';
    if (m > 0) return s == 0 ? '$m $mu' : '$m $mu $s $su';
    return '$s $su';
  }

  /// Control characters (a multi-line command) become one space, with the
  /// whitespace around them.
  static String _singleLine(String? text) {
    if (text == null) return '';
    return text.replaceAll(RegExp(r'\s*[\x00-\x1f\x7f]+\s*'), ' ').trim();
  }
}
