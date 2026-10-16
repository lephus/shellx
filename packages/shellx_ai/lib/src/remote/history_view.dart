import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';

import 'wire.dart';

/// V2-2b B17: the most sessions one `ai.history` page carries.
const int kAiHistoryPage = 50;

/// The longest title of an earlier session a page carries, in characters
/// (Unicode code points, not bytes); a longer one is cut and ends with "…".
const int kAiHistoryTitleChars = 120;

/// The longest agent session id a phone is given — and so the longest it
/// sends back in `ai.open {resume}`.
const int kAiAcpIdBytes = 200;

/// The longest cursor of a next page a phone is given — and so the longest it
/// sends back in `ai.history {cursor}`.
const int kAiHistoryCursorBytes = 1024;

/// An `updatedAt` longer than this is no date: it is left out.
const int _atBytes = 64;

/// One earlier session of the agent in the session's folder
/// (`session/list`, V2-1 D15).
final class AiPastSession with Redacted {
  const AiPastSession({required this.acp, this.title, this.at});

  /// The agent's session id: what `ai.open {resume}` sends back.
  final String acp;

  /// Its title, cut; null when the agent gave none.
  final String? title;

  /// When it last changed (ISO 8601, as the agent said it).
  final String? at;

  Map<String, Object?> toJson() => {'acp': acp, 'title': ?title, 'at': ?at};

  /// Null without an `acp`.
  static AiPastSession? fromJson(Map<String, Object?> j) {
    final acp = jString(j, 'acp');
    if (acp == null || acp.isEmpty) return null;
    return AiPastSession(
      acp: acp,
      title: jString(j, 'title'),
      at: jString(j, 'at'),
    );
  }
}

/// V2-2b B17: what `ai.history` answers — a page of [sessions], the cursor
/// of the [next] page (null: this was the last), and the agent's id of the
/// session that asked ([current]: open already, not offered again).
final class AiHistoryPage with Redacted {
  const AiHistoryPage({this.sessions = const [], this.next, this.current});

  final List<AiPastSession> sessions;
  final String? next;
  final String? current;

  Map<String, Object?> toJson() => {
    'sessions': [for (final s in sessions) s.toJson()],
    'next': ?next,
    'current': ?current,
  };

  static AiHistoryPage fromJson(Map<String, Object?> j) => AiHistoryPage(
    sessions: [
      for (final s in jMaps(j, 'sessions')) ?AiPastSession.fromJson(s),
    ],
    next: jString(j, 'next'),
    current: jString(j, 'current'),
  );
}

/// [s] cut to [kAiHistoryTitleChars] characters, with "…" when it was cut: by
/// code points, so it never splits a surrogate pair.
String _title(String s) {
  final runes = s.runes;
  if (runes.length <= kAiHistoryTitleChars) return s;
  return '${String.fromCharCodes(runes.take(kAiHistoryTitleChars - 1))}…';
}

/// [result] (the agent's `session/list` page) as the body of `ai.history`:
/// at most [kAiHistoryPage] sessions, titles cut to [kAiHistoryTitleChars]
/// characters. A session id, a cursor or a [current] id too long to be sent
/// back is left out, and so is an `updatedAt` that is no date. These limits
/// keep a page below one body (V2-2 D4): about 40 KB at the most, unless the
/// text holds control characters, which JSON escapes at up to six bytes each.
/// Should a page still be over [kAiRecordBytes], its last sessions go, and its
/// next page with them, which would skip them.
Uint8List encodeHistoryPage(ListSessionsResult result, {String? current}) {
  String? sendable(String? id, int max) =>
      id == null || id.isEmpty || utf8Length(id) > max ? null : id;
  final sessions = <AiPastSession>[];
  for (final s in result.sessions) {
    if (sessions.length == kAiHistoryPage) break;
    final acp = sendable(s.sessionId, kAiAcpIdBytes);
    if (acp == null) continue;
    final title = s.title?.trim();
    sessions.add(
      AiPastSession(
        acp: acp,
        title: title == null || title.isEmpty ? null : _title(title),
        at: sendable(s.updatedAt, _atBytes),
      ),
    );
  }
  var page = AiHistoryPage(
    sessions: sessions,
    next: sendable(result.nextCursor, kAiHistoryCursorBytes),
    current: sendable(current, kAiAcpIdBytes),
  );
  var body = encodeBody(page.toJson());
  while (body.length > kAiRecordBytes && page.sessions.isNotEmpty) {
    page = AiHistoryPage(
      sessions: page.sessions.sublist(0, page.sessions.length - 1),
      current: page.current,
    );
    body = encodeBody(page.toJson());
  }
  return body;
}
