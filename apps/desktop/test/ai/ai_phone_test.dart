import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart' show AgentNeedsInstall;
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_phone.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/memory_config_fs.dart';

const _phone = '33333333-3333-4333-8333-333333333333';

/// A second source over the same window, for what the hub does not show.
final _source = Provider<DesktopAiSource>((ref) {
  final source = DesktopAiSource(ref);
  ref.onDispose(source.dispose);
  return source;
});

/// V2-2 D2, D9, D11, D15: the window's AI sessions for phones, over the
/// real tab list and real runtimes on fake agents.
void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;
  late AiPhoneHub hub;
  final out = <OutboundMessage>[];
  final pushes = <AiPush>[];

  void boot(
    FakeScenario scenario, {
    List<Override>? runtimes,
    List<Override> more = const [],
  }) {
    out.clear();
    pushes.clear();
    fakes = FakeAiRuntimes(scenario);
    // cliContainer is a ProviderContainer.test: disposed at the end of the test.
    c = cliContainer(
      FakeLocalSessions(),
      overrides: [
        ...(runtimes ?? fakes.overrides),
        aiPushSinkProvider.overrideWithValue(pushes.add),
        ...more,
      ],
    );
    hub = c.read(aiPhoneHubProvider);
    hub.outbound.listen(out.add);
  }

  List<T> sent<T>() => out.map((o) => o.message).whereType<T>().toList();

  AiListing listing() {
    final r = sent<AiListResult>().last;
    return AiListing.fromJson(decodeBody(r.body)!, available: r.available);
  }

  AiSessionState stateOf(TerminalTab tab) =>
      c.read(aiRuntimesProvider.notifier).existing(tab.ai!.id)!.state;

  Future<void> until(bool Function() test) async {
    for (var i = 0; i < 400 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(test(), isTrue, reason: 'condition not reached');
  }

  test(
    'the AI tabs are the listing; a phone attaching starts a restored tab (D15)',
    () async {
      boot(const FakeScenario());
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      openTestAiTab(c, cwd: null, select: false);
      hub.handle(_phone, const AiList());
      expect(listing().sessions.map((s) => s.state), [
        AiRemoteState.stopped,
        AiRemoteState.noFolder,
      ]);
      expect(fakes.launcher.channels, isEmpty);
      hub.handle(_phone, AiAttach(sid: hub.sidOf(ai.ai!.id)));
      await until(() => fakes.launcher.channels.isNotEmpty);
      expect(sent<AiSnapshot>(), hasLength(1));
    },
  );

  test(
    'a prompt and a permission answered from the phone reach the agent',
    () async {
      boot(
        FakeScenario(
          turns: [
            [
              FakeSteps.permission('c1', 'Edit a.ts'),
              FakeSteps.text('done'),
              FakeSteps.stop('end_turn'),
            ],
          ],
        ),
      );
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final sid = hub.sidOf(ai.ai!.id);
      hub.handle(_phone, AiAttach(sid: sid));
      await until(() => stateOf(ai).phase == AgentPhase.ready);
      hub.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'Sửa a.ts'));
      await until(() => stateOf(ai).currentPermission != null);
      final p = stateOf(ai).currentPermission!;
      hub.handle(
        _phone,
        AiAnswer(sid: sid, rid: 2, permission: p.id, option: 'allow-once'),
      );
      await until(() => stateOf(ai).turn == null);
      final results = {for (final r in sent<AiResult>()) r.rid: r.ok};
      expect(results, {1: true, 2: true});
      expect(
        stateOf(ai).timeline.items.whereType<AgentTextItem>().single.text,
        'done',
      );
    },
  );

  test('pushes only while nobody shows the session (D11)', () async {
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.permission('c1', 'Edit a.ts'), FakeSteps.stop('end_turn')],
          [FakeSteps.permission('c2', 'Edit b.ts'), FakeSteps.stop('end_turn')],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: true);
    final runtime = c.read(aiRuntimesProvider.notifier).runtimeFor(ai.ai!.id)!;
    await runtime.start();
    // The window shows the pane: no push.
    c.read(windowRouterProvider.notifier).showTerminal();
    c.read(windowFocusProvider.notifier).set(true);
    unawaited(runtime.send([const TextBlock('a')]));
    await until(() => runtime.state.currentPermission != null);
    expect(pushes, isEmpty);
    runtime.answerPermission(runtime.state.currentPermission!.id, 'allow-once');
    await runtime.whenIdle();
    // The window lost the focus: the next request is pushed.
    c.read(windowFocusProvider.notifier).set(false);
    unawaited(runtime.send([const TextBlock('b')]));
    await until(() => runtime.state.currentPermission != null);
    expect(pushes.single.kind, AiPushKind.needsInput);
    expect(pushes.single.detail, 'Edit b.ts');
  });

  test(
    'a new session from the phone: in the workspace, not selected, its agent started (D9)',
    () async {
      boot(const FakeScenario());
      final ws = c.read(sidebarWorkspacesProvider).workspaces.first.id;
      c.read(sidebarWorkspacesProvider.notifier).setRoot(ws, testAiCwd);
      final mine = openTestAiTab(
        c,
        cwd: testAiCwd,
        select: true,
      ); // the user's tab
      final selectedBefore = c.read(terminalTabsProvider).selectedId;
      expect(selectedBefore, mine.id);
      hub.handle(_phone, const AiList());
      final folder = listing().folders.firstWhere((f) => f.key == 'ws:$ws');
      hub.handle(_phone, AiOpen(rid: 7, agent: 'claude', folder: folder.key));
      await until(() => sent<AiResult>().isNotEmpty);
      final result = sent<AiResult>().single;
      expect(result.ok, isTrue);
      final tab = c
          .read(terminalTabsProvider)
          .tabs
          .firstWhere((t) => t.ai != null && hub.sidOf(t.ai!.id) == result.sid);
      expect(tab.ai!.cwd, testAiCwd);
      expect(c.read(terminalTabsProvider).selectedId, selectedBefore);
      await until(() => fakes.launcher.channels.isNotEmpty);
      hub.handle(
        _phone,
        const AiOpen(rid: 8, agent: 'claude', folder: 'path:/not/offered'),
      );
      await until(() => sent<AiResult>().length == 2);
      expect(sent<AiResult>().last.code, 'refused');
    },
  );

  // ------------------------------------------------- beyond the brief --

  /// The phone's copy of [sid], from every body it was sent.
  AiMirror mirror(String sid) {
    final m = AiMirror();
    for (final message in out.map((o) => o.message)) {
      switch (message) {
        case AiSnapshot(sid: final s, :final body) when s == sid:
          m.apply(decodeBody(body)!, snapshot: true);
        case AiUpdate(sid: final s, :final body) when s == sid:
          m.apply(decodeBody(body)!, snapshot: false);
        default:
          break;
      }
    }
    return m;
  }

  AiResult result(int rid) => sent<AiResult>().lastWhere((r) => r.rid == rid);

  group('the source', () {
    test('a runtime the window makes is watched at once: the phone sees it '
        'start with nothing else changed (AiRuntimes.made)', () async {
      boot(const FakeScenario(sessionId: 'sess-7'));
      // A restored tab: its session id is the agent's, its title stays.
      final ai = openTestAiTab(
        c,
        cwd: testAiCwd,
        sessionId: 'sess-7',
        select: false,
      );
      hub.handle(_phone, const AiList());
      expect(listing().sessions.single.state, AiRemoteState.stopped);
      // What opening the tab set off is over (the sidebar placed it, the
      // hub's next list went): the hub hears of nothing else from here.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      List<Object?> listened() => [
        c.read(terminalTabsProvider),
        c.read(sidebarWorkspacesProvider),
        c.read(aiAgentsProvider),
        c.read(aiReadinessProvider),
        c.read(aiDefaultAgentProvider),
      ];
      final before = listened();
      // What the pane does once it is shown (V2-1b B11): made, then started.
      final runtime = c
          .read(aiRuntimesProvider.notifier)
          .runtimeFor(ai.ai!.id)!;
      await runtime.start();
      await until(() => listing().sessions.single.state == AiRemoteState.idle);
      final after = listened();
      for (var i = 0; i < before.length; i++) {
        expect(after[i], same(before[i]), reason: 'only `made` told the hub');
      }
    });

    test('a runtime replaced (another folder): the phone starts over on the '
        'new one, without being told the session closed', () async {
      boot(const FakeScenario());
      final other = Directory.systemTemp.createTempSync('shellx-ai-phone-');
      addTearDown(() => other.deleteSync(recursive: true));
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final pane = ai.ai!.id;
      final sid = hub.sidOf(pane);
      hub.handle(_phone, AiAttach(sid: sid));
      await until(() => stateOf(ai).phase == AgentPhase.ready);
      final runtimes = c.read(aiRuntimesProvider.notifier);
      final first = runtimes.existing(pane);
      // The pane's folder card (V2-1 D5): the old runtime goes, the tab gets
      // the folder, the pane makes the next runtime.
      runtimes.forget(pane);
      c
          .read(terminalTabsProvider.notifier)
          .updateAiPane(pane, (p) => p.copyWith(cwd: other.path));
      expect(runtimes.runtimeFor(pane), isNot(same(first)));
      await until(() => mirror(sid).head?.cwd == other.path);
      expect(sent<AiClosed>(), isEmpty);
    });

    test('an agent removed while a phone mirrors its session: the phone and '
        'the list say why it cannot run (V2-1 D21)', () async {
      boot(const FakeScenario());
      final agent = await c
          .read(aiCustomAgentsProvider.notifier)
          .add(name: 'Mine', command: '/opt/mine');
      final ai = openTestAiTab(
        c,
        agentId: agent.id,
        agentName: 'Mine',
        cwd: testAiCwd,
        select: false,
      );
      final sid = hub.sidOf(ai.ai!.id);
      hub.handle(_phone, const AiList());
      hub.handle(_phone, AiAttach(sid: sid));
      await until(() => stateOf(ai).phase == AgentPhase.ready);
      await c.read(aiCustomAgentsProvider.notifier).remove(agent.id);
      await until(
        () => mirror(sid).head?.unavailable == AiRemoteState.agentOff,
      );
      expect(c.read(aiRuntimesProvider.notifier).existing(ai.ai!.id), isNull);
      await until(
        () => listing().sessions.single.state == AiRemoteState.agentOff,
      );
    });

    test('Claude switched off on the computer while only a phone shows its '
        'session: the agent stops, the phone is told why (V2-1 D21)', () async {
      final fs = MemoryConfigFs();
      boot(const FakeScenario(), more: configOverrides(fs));
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final sid = hub.sidOf(ai.ai!.id);
      hub.handle(_phone, AiAttach(sid: sid));
      await until(() => stateOf(ai).phase == AgentPhase.ready);
      fs.write(testConfigPaths().shellx, 'ai-agent-claude = off\n');
      await loadConfig(c);
      await until(
        () => mirror(sid).head?.unavailable == AiRemoteState.agentOff,
      );
      expect(fakes.launcher.channels.single.stopCalls, 1);
    });

    test('a tab that cannot run says why, in the list and to a phone that '
        'opens it: no folder, or its agent off or unknown (D14)', () {
      boot(const FakeScenario());
      final noFolder = openTestAiTab(c, cwd: null, select: false);
      final unknown = openTestAiTab(
        c,
        agentId: 'gone',
        agentName: 'Gone',
        cwd: testAiCwd,
        select: false,
      );
      hub.handle(_phone, const AiList());
      expect(listing().sessions.map((s) => s.state), [
        AiRemoteState.noFolder,
        AiRemoteState.agentOff,
      ]);
      for (final (tab, why) in [
        (noFolder, AiRemoteState.noFolder),
        (unknown, AiRemoteState.agentOff),
      ]) {
        final sid = hub.sidOf(tab.ai!.id);
        hub.handle(_phone, AiAttach(sid: sid));
        expect(mirror(sid).head!.unavailable, why);
      }
      expect(fakes.made, isEmpty, reason: 'no runtime for either');
    });

    test('a live runtime is listed with its state from the moment it is '
        'made, never as unavailable or without one', () async {
      boot(const FakeScenario());
      final source = c.read(_source);
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final pane = ai.ai!.id;
      final atMade = <AiSessionEntry>[];
      c
          .read(aiRuntimesProvider.notifier)
          .made
          .listen((_) => atMade.add(source.sessions.single));
      final atChange = <AiSessionEntry>[];
      source.changes.listen((_) => atChange.add(source.sessions.single));
      final control = source.control(pane, start: true)!;
      expect(atMade.single.state, same(control.state));
      expect(atMade.single.unavailable, isNull);
      await until(() => control.state.phase == AgentPhase.ready);
      await pumpEventQueue();
      expect(atChange, isNotEmpty);
      for (final e in [...atChange, source.sessions.single]) {
        expect(e.state, same(control.state));
        expect(e.unavailable, isNull);
      }
      // Whatever the tab says meanwhile (here: no folder any more), a runtime
      // that lives is listed live, to the phone too.
      c
          .read(terminalTabsProvider.notifier)
          .updateAiPane(pane, (p) => p.copyWith(cwd: null));
      await pumpEventQueue();
      expect(source.sessions.single.state, same(control.state));
      expect(source.sessions.single.unavailable, isNull);
      hub.handle(_phone, const AiList());
      expect(listing().sessions.single.state, AiRemoteState.idle);
    });

    test('the list follows the computer\'s agents: their readiness once '
        'known, the default agent once chosen (D9)', () async {
      boot(const FakeScenario());
      hub.handle(_phone, const AiList());
      AiAgentChoice claude() =>
          listing().agents.singleWhere((a) => a.id == kClaudeAgentId);
      expect(claude().ready, isTrue, reason: 'not known yet counts as ready');
      expect(listing().defaultAgent, kClaudeAgentId);
      fakes.readiness = const AgentNeedsInstall(null);
      await c.read(aiReadinessProvider.notifier).refresh();
      await until(() => !claude().ready);
      await c.read(aiDefaultAgentChoiceProvider.notifier).set('codex');
      await until(() => listing().defaultAgent == 'codex');
    });

    test('control never throws: a runtime that cannot be made is none to '
        'control, and the phone still gets an answer', () async {
      boot(
        const FakeScenario(),
        runtimes: [
          aiRuntimeFactoryProvider.overrideWithValue(
            (_) => throw StateError('no AI host'),
          ),
          aiReadinessSourceProvider.overrideWithValue(
            (_) async => FakeAiRuntimes.ready,
          ),
        ],
      );
      final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
      final sid = hub.sidOf(ai.ai!.id);
      expect(c.read(_source).control(ai.ai!.id, start: true), isNull);
      hub.handle(_phone, AiAttach(sid: sid));
      hub.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'hi'));
      await pumpEventQueue();
      expect(out.map((o) => o.message.type), [
        'ai.snapshot',
        'ai.result',
      ], reason: 'one answer each, never silence');
      expect(mirror(sid).head!.unavailable, isNotNull);
      expect(result(1).code, 'not_found');
    });

    test('a session id is never used again in a run, not even once its tab '
        'closed; another run names its sessions apart', () {
      boot(const FakeScenario());
      final a = openTestAiTab(c, cwd: testAiCwd, select: false);
      final sidA = hub.sidOf(a.ai!.id);
      c.read(terminalTabsProvider.notifier).close(a.id);
      final b = openTestAiTab(c, cwd: testAiCwd, select: false);
      final sidB = hub.sidOf(b.ai!.id);
      expect(sidB, isNot(sidA));
      hub.handle(_phone, const AiList());
      expect(listing().sessions.map((s) => s.sid), [sidB]);
      hub.handle(_phone, AiAttach(sid: sidA));
      expect(
        (sent<AiClosed>().single.sid, sent<AiClosed>().single.reason),
        (sidA, 'gone'),
      );
      final next = cliContainer(
        FakeLocalSessions(),
        overrides: FakeAiRuntimes(const FakeScenario()).overrides,
      );
      final first = openTestAiTab(next, cwd: testAiCwd, select: false);
      expect(first.ai!.id, a.ai!.id, reason: 'pane ids start over');
      expect(next.read(aiPhoneHubProvider).sidOf(first.ai!.id), isNot(sidA));
    });

    test('a path folder opens next to the tab that offered it, not in the '
        'workspace the computer shows (D9)', () async {
      boot(const FakeScenario());
      // The user looks at a tab of Default; an AI tab of Shop has a folder.
      openTestAiTab(c, cwd: null, select: true);
      final shop = c
          .read(sidebarWorkspacesProvider.notifier)
          .createFor(name: 'Shop');
      final there = openTestAiTab(
        c,
        cwd: testAiCwd,
        workspace: shop,
        select: false,
      );
      expect(c.read(sidebarWorkspacesProvider).workspaceOf(there.id), shop);
      expect(
        c.read(sidebarWorkspacesProvider).currentId,
        isNot(shop),
        reason: 'the workspace the computer shows is another',
      );
      hub.handle(_phone, const AiList());
      final folder = listing().folders.singleWhere(
        (f) => f.key == 'path:$testAiCwd',
      );
      hub.handle(_phone, AiOpen(rid: 1, agent: 'claude', folder: folder.key));
      await until(() => sent<AiResult>().isNotEmpty);
      final opened = c
          .read(terminalTabsProvider)
          .tabs
          .singleWhere(
            (t) => t.ai != null && hub.sidOf(t.ai!.id) == result(1).sid,
          );
      expect(c.read(sidebarWorkspacesProvider).workspaceOf(opened.id), shop);
    });
  });

  test('an answer that turns on a mode acting without asking is refused from '
      'a phone: it is given on the computer, after its question (V2-1 R6, '
      'V2-2 D13)', () async {
    boot(
      FakeScenario(
        turns: [
          [
            FakeSteps.permission(
              'c1',
              'Ready to code?',
              kind: 'switch_mode',
              options: const [
                {
                  'optionId': 'bypassPermissions',
                  'name': 'Yes, and bypass permissions',
                  'kind': 'allow_always',
                },
                {
                  'optionId': 'default',
                  'name': 'Yes, and manually approve edits',
                  'kind': 'allow_once',
                },
                {
                  'optionId': 'plan',
                  'name': 'No, keep planning',
                  'kind': 'reject_once',
                },
              ],
            ),
            FakeSteps.stop('end_turn'),
          ],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final sid = hub.sidOf(ai.ai!.id);
    hub.handle(_phone, AiAttach(sid: sid));
    await until(() => stateOf(ai).phase == AgentPhase.ready);
    hub.handle(_phone, AiPrompt(sid: sid, rid: 1, text: 'plan it'));
    await until(() => stateOf(ai).currentPermission != null);
    final p = stateOf(ai).currentPermission!;
    hub.handle(
      _phone,
      AiAnswer(sid: sid, rid: 2, permission: p.id, option: 'bypassPermissions'),
    );
    expect((result(2).ok, result(2).code), (false, 'on_computer'));
    expect(stateOf(ai).currentPermission?.id, p.id, reason: 'still asked');
    hub.handle(
      _phone,
      AiAnswer(sid: sid, rid: 3, permission: p.id, option: 'default'),
    );
    await until(() => stateOf(ai).turn == null);
    expect(result(3).ok, isTrue);
  });
}
