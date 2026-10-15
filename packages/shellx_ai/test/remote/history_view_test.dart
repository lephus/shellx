import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:test/test.dart';

ListSessionsResult _page(List<SessionSummary> sessions, [String? next]) =>
    ListSessionsResult(sessions: sessions, nextCursor: next);

/// V2-2b B17: the body of `ai.history`.
void main() {
  test(
    'a page round-trips: its sessions, the next cursor, the current one',
    () {
      final body = encodeHistoryPage(
        _page([
          const SessionSummary(
            sessionId: 'old-1',
            cwd: '/p',
            title: '  Nút đăng xuất ',
            updatedAt: '2026-10-13T09:30:00Z',
          ),
          const SessionSummary(sessionId: 'sess-1', cwd: '/p', title: ' '),
        ], 'c2'),
        current: 'sess-1',
      );
      final page = AiHistoryPage.fromJson(decodeBody(body)!);
      expect(
        [for (final s in page.sessions) (s.acp, s.title, s.at)],
        [
          ('old-1', 'Nút đăng xuất', '2026-10-13T09:30:00Z'),
          ('sess-1', null, null),
        ],
      );
      expect((page.next, page.current), ('c2', 'sess-1'));
    },
  );

  test('at most 50 sessions, titles cut; what could not be sent back is left '
      'out (Review Focus 3)', () {
    final body = encodeHistoryPage(
      _page([
        SessionSummary(sessionId: 'x' * (kAiAcpIdBytes + 1), cwd: '/p'),
        const SessionSummary(sessionId: '', cwd: '/p'),
        for (var i = 0; i < 80; i++)
          SessionSummary(
            sessionId: 's$i',
            cwd: '/p',
            title: 'Đ' * 5000,
            updatedAt: '9' * 500,
          ),
      ], 'c' * (kAiHistoryCursorBytes + 1)),
      current: 'y' * (kAiAcpIdBytes + 1),
    );
    expect(body.length, lessThanOrEqualTo(kAiRecordBytes));
    final page = AiHistoryPage.fromJson(decodeBody(body)!);
    expect(page.sessions, hasLength(kAiHistoryPage));
    expect(page.sessions.first.acp, 's0');
    for (final s in page.sessions) {
      expect(s.title!.runes.length, lessThanOrEqualTo(kAiHistoryTitleChars));
      expect(s.at, isNull, reason: 'no date');
    }
    expect(
      page.sessions.first.title,
      '${'Đ' * 119}…',
      reason: 'cut to 120 characters, the last one the ellipsis',
    );
    expect(page.next, isNull, reason: 'a cursor too long to send back');
    expect(page.current, isNull);
  });

  test('a title is cut by characters, never inside a surrogate pair; one '
      'within the limit is kept whole', () {
    final body = encodeHistoryPage(
      _page([
        SessionSummary(sessionId: 'long', cwd: '/p', title: '😀' * 200),
        SessionSummary(sessionId: 'exact', cwd: '/p', title: 'ơ' * 120),
        SessionSummary(sessionId: 'over', cwd: '/p', title: 'ơ' * 121),
      ]),
    );
    final page = AiHistoryPage.fromJson(decodeBody(body)!);
    final titles = {for (final s in page.sessions) s.acp: s.title!};
    expect(titles['long'], '${'😀' * 119}…');
    expect(titles['long']!.runes.length, kAiHistoryTitleChars);
    expect(titles['exact'], 'ơ' * 120);
    expect(titles['over'], '${'ơ' * 119}…');
  });

  test('the worst page the limits allow (the longest ids, titles of '
      'four-byte characters, the longest dates and cursors) fits one body, '
      'no session left out for its size', () {
    final body = encodeHistoryPage(
      _page([
        for (var i = 10; i < 10 + kAiHistoryPage; i++)
          SessionSummary(
            sessionId: '${'a' * (kAiAcpIdBytes - 2)}$i',
            cwd: '/p',
            title: '😀' * 200,
            updatedAt: '2' * 64,
          ),
      ], 'c' * kAiHistoryCursorBytes),
      current: 'y' * kAiAcpIdBytes,
    );
    expect(body.length, lessThan(kAiRecordBytes));
    final page = AiHistoryPage.fromJson(decodeBody(body)!);
    expect(page.sessions, hasLength(kAiHistoryPage));
    expect(page.next, hasLength(kAiHistoryCursorBytes));
    expect(page.current, hasLength(kAiAcpIdBytes));
  });

  test('a body read tolerantly: entries without an id are skipped', () {
    final page = AiHistoryPage.fromJson({
      'sessions': [
        {'acp': 'a', 'title': 7},
        {'title': 'no id'},
        'not a map',
      ],
      'next': 3,
    });
    expect([for (final s in page.sessions) (s.acp, s.title)], [('a', null)]);
    expect(page.next, isNull);
    expect(const AiHistoryPage().toJson(), {'sessions': <Object?>[]});
  });

  test('toString shows nothing of a session', () {
    const session = AiPastSession(acp: 'old-1', title: 'Nút đăng xuất');
    expect(session.toString(), '…');
    expect(AiHistoryPage(sessions: const [session]).toString(), '…');
  });
}
