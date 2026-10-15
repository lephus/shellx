import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/ai_fakes.dart';
import '../support/ai_phone_rig.dart';
import '../support/ai_tabs.dart';

/// V2-2b B17, B18 on the real window: history, resume, and a folder chosen on
/// the phone for a tab without one.
void main() {
  test("the agent's earlier sessions reach the phone; one opens in a new tab "
      'that reopens it, not selected (B17)', () async {
    final rig = PhoneHubRig(
      const FakeScenario(
        sessions: [
          {
            'sessionId': 'old-1',
            'cwd': '/w',
            'title': 'Nút đăng xuất',
            'updatedAt': '2026-10-13T09:30:00Z',
          },
        ],
      ),
    );
    final tab = openTestAiTab(rig.c, cwd: testAiCwd, select: true);
    final sid = rig.sidOf(tab);
    rig.say(AiAttach(sid: sid));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    rig.say(AiHistory(sid: sid, rid: 1));
    final page = AiHistoryPage.fromJson(
      decodeBody((await rig.answer(1)).body)!,
    );
    expect([for (final s in page.sessions) s.acp], ['old-1']);
    expect(page.current, 'sess-1');
    rig.say(const AiList());
    final folder = rig
        .listing()
        .folders
        .singleWhere((f) => f.path == testAiCwd)
        .key;
    final selected = rig.c.read(terminalTabsProvider).selectedId;
    rig.say(AiOpen(rid: 2, agent: 'claude', folder: folder, resume: 'old-1'));
    final opened = await rig.answer(2);
    expect(opened.ok, isTrue);
    final again = rig.c
        .read(terminalTabsProvider)
        .tabs
        .singleWhere((t) => t.ai != null && rig.sidOf(t) == opened.sid);
    expect(again.ai!.sessionId, 'old-1');
    expect(again.ai!.cwd, testAiCwd);
    expect(
      rig.c.read(terminalTabsProvider).selectedId,
      selected,
      reason: 'the computer keeps the tab it shows',
    );
    await rig.until(() => rig.fakes.launcher.channels.length == 2);
    await rig.until(
      () => rig.fakes.agent(1).received.contains('session/load:old-1'),
    );
  });

  test('a tab without a folder runs in one the computer offers; the phone '
      'waiting for it sees it start; a folder twice, or a key not offered, '
      'is refused (B18)', () async {
    final rig = PhoneHubRig(const FakeScenario());
    openTestAiTab(rig.c, cwd: testAiCwd, select: false); // offers its folder
    // A session id left in a tab that has no folder: the folder it gets starts
    // a new session, as the tab's own "Use this folder" does, never that one.
    final bare = openTestAiTab(
      rig.c,
      cwd: null,
      sessionId: 'stale-1',
      select: false,
    );
    final sid = rig.sidOf(bare);
    rig.say(const AiList());
    expect(
      rig.listing().sessions.singleWhere((s) => s.sid == sid).state,
      AiRemoteState.noFolder,
    );
    final folder = rig
        .listing()
        .folders
        .singleWhere((f) => f.path == testAiCwd)
        .key;
    rig.say(AiAttach(sid: sid)); // told why it cannot run, and waits
    rig.say(AiFolder(sid: sid, rid: 1, folder: folder));
    expect((await rig.answer(1)).ok, isTrue);
    final now = rig.c
        .read(terminalTabsProvider)
        .tabs
        .singleWhere((t) => t.id == bare.id);
    expect(now.ai!.cwd, testAiCwd);
    // Not `isNull`: the new session's id is written to the pane as soon as the
    // agent starts it (`AiRuntimes`), which the answer does not wait for.
    expect(now.ai!.sessionId, isNot('stale-1'));
    await rig.until(() => rig.fakes.launcher.channels.isNotEmpty);
    await rig.until(() => rig.stateOf(now).phase == AgentPhase.ready);
    final asked = rig.fakes.agent().received;
    expect(asked, contains('session/new'));
    expect(
      asked.where((e) => e.startsWith('session/load')),
      isEmpty,
      reason: 'a new session, not the one the tab was left with',
    );
    expect(
      rig.sent<AiSnapshot>().where((s) => s.sid == sid),
      hasLength(greaterThanOrEqualTo(2)),
      reason: 'the "cannot run" snapshot, then the live one',
    );
    rig.say(AiFolder(sid: sid, rid: 2, folder: folder));
    expect((await rig.answer(2)).code, 'refused', reason: 'it has one now');
    final other = openTestAiTab(rig.c, cwd: null, select: false);
    rig.say(
      AiFolder(
        sid: rig.sidOf(other),
        rid: 3,
        folder: 'path:/typed/on/the/phone',
      ),
    );
    expect((await rig.answer(3)).code, 'refused');
  });
}
