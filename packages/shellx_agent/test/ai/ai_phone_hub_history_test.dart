import 'package:shellx_acp/shellx_acp.dart';
// The agent's own `SessionSummary` is a terminal session's, not ACP's.
import 'package:shellx_agent/shellx_agent.dart' hide SessionSummary;
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// Pane [paneId] with an agent that offers `session/list` and runs `sess-1`.
AiSessionState _listing(FakeAiSource source, int paneId) => source.add(paneId)
  ..setAgent(
    InitializeResult.fromJson({
      'protocolVersion': 1,
      'agentCapabilities': {
        'sessionCapabilities': {'list': <String, Object?>{}},
      },
    }),
  )
  ..setSession('sess-1');

SessionSummary _past(int i, {String? title}) => SessionSummary(
  sessionId: 'old-$i',
  cwd: '/p',
  title: title ?? 'Phiên $i',
  updatedAt: '2026-10-13T09:30:00Z',
);

AiHistoryPage _page(AiResult r) => AiHistoryPage.fromJson(decodeBody(r.body)!);

/// [m] from the phone, and the answer once the hub has worked it out.
Future<AiResult> _ask(HubRig rig, AiMessage m) async {
  rig.hub.handle(_phone, m);
  await pumpEventQueue();
  return rig.last<AiResult>(_phone);
}

/// V2-2b B17, B18: session history, resume, and a folder from the phone.
void main() {
  test('the listing offers history and folders', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, const AiList());
    final r = rig.last<AiListResult>(_phone);
    final listing = AiListing.fromJson(
      decodeBody(r.body)!,
      available: r.available,
    );
    expect(
      listing.features,
      containsAll([AiFeature.history, AiFeature.folder]),
    );
  });

  test("the agent's earlier sessions, a page at a time; the asking session "
      'is current', () async {
    final rig = HubRig();
    _listing(rig.source, -1);
    final control = rig.source.controls[-1]!;
    control.history = ListSessionsResult(
      sessions: [
        _past(1),
        const SessionSummary(sessionId: 'sess-1', cwd: '/p'),
      ],
      nextCursor: 'c2',
    );
    final first = await _ask(rig, const AiHistory(sid: 'ep.-1', rid: 1));
    expect(first.ok, isTrue);
    final page = _page(first);
    expect([for (final s in page.sessions) s.acp], ['old-1', 'sess-1']);
    expect((page.next, page.current), ('c2', 'sess-1'));
    await _ask(rig, const AiHistory(sid: 'ep.-1', rid: 2, cursor: 'c2'));
    expect(control.cursors, [null, 'c2']);
  });

  test('a long agent page comes in pages of 50, then its own next page; '
      'every page fits one message (Review Focus 3)', () async {
    final rig = HubRig();
    _listing(rig.source, -1);
    final control = rig.source.controls[-1]!;
    control.history = ListSessionsResult(
      sessions: [for (var i = 0; i < 120; i++) _past(i, title: 'Đ' * 5000)],
      nextCursor: 'agent-2',
    );
    final pages = <AiHistoryPage>[];
    String? cursor;
    for (var rid = 1; rid <= 3; rid++) {
      final r = await _ask(
        rig,
        AiHistory(sid: 'ep.-1', rid: rid, cursor: cursor),
      );
      expect(r.ok, isTrue);
      expect(r.body!.length, lessThanOrEqualTo(kAiMaxBodyBytes));
      expect(encodeBatch([r]).length, lessThan(kMaxSealedBatchBytes));
      pages.add(_page(r));
      cursor = pages.last.next;
    }
    expect([for (final p in pages) p.sessions.length], [50, 50, 20]);
    expect(
      [
        for (final p in pages)
          for (final s in p.sessions) s.acp,
      ],
      [for (var i = 0; i < 120; i++) 'old-$i'],
    );
    expect(pages.last.next, 'agent-2');
    expect(control.cursors, [null], reason: 'the rest came from the hub');
    for (final s in pages.first.sessions) {
      expect(s.title!.runes.length, lessThanOrEqualTo(kAiHistoryTitleChars));
    }
  });

  test('not running: not_ready; no session/list, nothing from the agent or '
      'a cursor that cannot be one: refused; another run: not_found', () async {
    final rig = HubRig();
    final s = _listing(rig.source, -1);
    final control = rig.source.controls[-1]!;
    s.setPhase(AgentPhase.stopped);
    final notReady = await _ask(rig, const AiHistory(sid: 'ep.-1', rid: 1));
    expect(notReady.code, 'not_ready');
    s.setPhase(AgentPhase.ready);
    final silent = await _ask(rig, const AiHistory(sid: 'ep.-1', rid: 2));
    expect(silent.code, 'refused', reason: 'the agent said nothing');
    for (final (rid, cursor) in [
      (3, 'c' * (kAiHistoryCursorBytes + 1)),
      (4, ''),
    ]) {
      final r = await _ask(
        rig,
        AiHistory(sid: 'ep.-1', rid: rid, cursor: cursor),
      );
      expect(r.code, 'refused');
    }
    expect(control.cursors, [null], reason: 'only rid 2 reached the agent');
    rig.source.add(-2); // an agent without session/list
    final noList = await _ask(rig, const AiHistory(sid: 'ep.-2', rid: 5));
    expect(noList.code, 'refused');
    final gone = await _ask(rig, const AiHistory(sid: 'xx.-1', rid: 6));
    expect(gone.code, 'not_found');
  });

  test("pins _ask passing a refusal's body through: a window that refuses "
      'keeps its code and the exact bytes it gave', () async {
    final rig = HubRig();
    _listing(rig.source, -1);
    final body = encodeBody({
      'files': ['lib/a.dart', 'lib/b.dart'],
    });
    rig.source.controls[-1]!.failWith = AiRefused('confirm', body: body);
    final r = await _ask(rig, const AiHistory(sid: 'ep.-1', rid: 1));
    expect(r.ok, isFalse);
    expect(r.code, 'confirm');
    expect(r.body, body);
  });

  test('resume: a new tab that reopens the earlier session; a resume that '
      'cannot be one, or a folder not offered, is refused', () async {
    final rig = HubRig()..source.opened = -5;
    final opened = await _ask(
      rig,
      const AiOpen(rid: 1, agent: 'claude', folder: 'ws:a', resume: 'old-1'),
    );
    expect((opened.ok, opened.sid), (true, 'ep.-5'));
    expect(rig.source.openedWith, [('claude', 'ws:a')]);
    expect(rig.source.resumed, ['old-1']);
    for (final (rid, resume, folder) in [
      (2, '', 'ws:a'),
      (3, 'x' * (kAiAcpIdBytes + 1), 'ws:a'),
      (4, 'old-1', 'path:/typed/on/the/phone'),
    ]) {
      final r = await _ask(
        rig,
        AiOpen(rid: rid, agent: 'claude', folder: folder, resume: resume),
      );
      expect(r.code, 'refused', reason: 'rid $rid');
    }
    expect(rig.source.resumed, ['old-1'], reason: 'nothing else reached it');
  });

  test('a tab without a folder runs in one the window offers; the phone '
      'waiting for it gets the session (B18)', () async {
    final rig = HubRig();
    rig.source.add(-3, runs: false, unavailable: AiRemoteState.noFolder);
    rig.hub.handle(_phone, const AiAttach(sid: 'ep.-3'));
    MirrorHead head(AiSnapshot s) =>
        MirrorHead.fromJson(jMap(decodeBody(s.body)!, 'head')!);
    expect(
      head(rig.last<AiSnapshot>(_phone)).unavailable,
      AiRemoteState.noFolder,
    );
    final r = await _ask(
      rig,
      const AiFolder(sid: 'ep.-3', rid: 1, folder: 'ws:a'),
    );
    expect(r.ok, isTrue);
    expect(rig.source.folderChosen, [(-3, 'ws:a')]);
    expect(rig.source.controls[-3], isNotNull, reason: 'its runtime made');
    final live = head(rig.last<AiSnapshot>(_phone));
    expect(live.unavailable, isNull);
    expect(live.phase, 'ready');
  });

  test('a folder only for a tab without one, only a key the window offers, '
      'never past a window that says no', () async {
    final rig = HubRig();
    rig.source
      ..add(-1)
      ..add(-3, runs: false, unavailable: AiRemoteState.noFolder);
    Future<String?> code(AiFolder f) async => (await _ask(rig, f)).code;
    expect(
      await code(const AiFolder(sid: 'ep.-1', rid: 1, folder: 'ws:a')),
      'refused',
      reason: 'it has one',
    );
    expect(
      await code(
        const AiFolder(sid: 'ep.-3', rid: 2, folder: 'path:/typed/by/hand'),
      ),
      'refused',
    );
    rig.source.refuseFolder = true;
    expect(
      await code(const AiFolder(sid: 'ep.-3', rid: 3, folder: 'ws:a')),
      'refused',
    );
    rig.source
      ..refuseFolder = false
      ..failing.add('folder');
    expect(
      await code(const AiFolder(sid: 'ep.-3', rid: 4, folder: 'ws:a')),
      'refused',
      reason: 'a window that fails: one answer, nothing escapes',
    );
    expect(
      await code(const AiFolder(sid: 'ep.-8', rid: 5, folder: 'ws:a')),
      'not_found',
    );
    expect(
      await code(const AiFolder(sid: 'xx.-3', rid: 6, folder: 'ws:a')),
      'not_found',
    );
    expect(
      rig.source.folderChosen,
      [(-3, 'ws:a')],
      reason:
          'only a key the window offers, for a tab without a folder, '
          'reached it',
    );
  });
}
