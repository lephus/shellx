import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late ProviderContainer c;
  late FakeLocalSessions local;
  late UiCommandHandler h;

  Future<Map<String, Object?>> call(
    String t, [
    Map<String, Object?> f = const {},
  ]) => h.handle(MuxMessage(t, q: 1, fields: f));

  Matcher fails(String code) =>
      throwsA(isA<CliFailure>().having((e) => e.code, 'code', code));

  TerminalTabsState tabs() => c.read(terminalTabsProvider);
  SidebarState side() => c.read(sidebarWorkspacesProvider);

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    h = c.read(uiCommandHandlerProvider);
    await c.read(terminalTabsProvider.notifier).openTab(); // user's tab 100
  });

  test('ls: workspaces → tabs → panes with ids and context (D13)', () async {
    local.replace(
      local.summary(
        100,
        origin: SessionOrigin.desktop,
        title: 'vim',
        cwd: '/w',
        gitBranch: 'main',
        ports: [3000],
      ),
    );
    final ls = await call('ui.ls');
    final ws = (ls['workspaces']! as List).single as Map;
    expect(ws['id'], 'default');
    expect(ws['name'], 'Default');
    expect(ws['current'], isTrue);
    expect(ws['collapsed'], isFalse);
    final tab = (ws['tabs']! as List).single as Map;
    expect(tab['id'], 100);
    expect(tab['title'], 'vim');
    expect(tab['custom'], isFalse);
    expect(tab['selected'], isTrue);
    expect(tab['unread'], 0);
    expect(tab['running'], isFalse);
    expect(tab['agent'], isFalse);
    final pane = (tab['panes']! as List).single as Map;
    expect(
      [
        pane['id'],
        pane['kind'],
        pane['focused'],
        pane['cwd'],
        pane['branch'],
        pane['ports'],
        pane['zoomed'],
        pane['exited'],
      ],
      [
        100,
        'terminal',
        true,
        '/w',
        'main',
        [3000],
        false,
        false,
      ],
    );
    expect(ls['selectedTab'], 100);
    expect(ls['focusedPane'], 100);
    await call('ui.tab.new');
    final again = await call('ui.ls');
    final listed = ((again['workspaces']! as List).single as Map)['tabs']!;
    expect(
      [for (final t in listed as List) (t as Map)['agent']],
      [false, true],
    );
  });

  test('new tab: not selected by default, in the named workspace, cwd '
      'passed (D14)', () async {
    final ws = c
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'api');
    final r = await call('ui.tab.new', {'workspace': 'api', 'cwd': '/w'});
    expect(r, {'tab': 101, 'pane': 101});
    expect(tabs().selectedId, 100);
    expect(side().workspaceOf(101), ws);
    expect(side().currentId, kDefaultWorkspaceId);
    expect(local.openCwds.last, '/w');
    expect(local.openTabIds.last, isNull);
    expect(c.read(agentMarksProvider).tabs.keys, contains(101));
    expect(c.read(agentMarksProvider).panes.keys, contains(101));
    final f = await call('ui.tab.new', {'focus': true});
    expect(tabs().selectedId, f['tab']);
    await expectLater(
      call('ui.tab.new', {'workspace': 'nope'}),
      fails('not_found'),
    );
    await expectLater(call('ui.tab.new', {'cwd': 7}), fails('bad_request'));
  });

  test('split: any tab, right/down, keeps focus and selection unless '
      'asked, passes tabId (D15)', () async {
    await call('ui.tab.new'); // tab 101, not selected
    final r = await call('ui.pane.split', {'pane': 101, 'direction': 'down'});
    expect(r, {'pane': 102, 'tab': 101});
    final tab = tabs().tabOfSession(102)!;
    expect(tab.id, 101);
    expect(tab.focusedPaneId, 101); // D15: no focus change
    expect(tabs().selectedId, 100); // nor selection
    expect(local.openTabIds.last, 101);
    expect(c.read(agentMarksProvider).panes.keys, contains(102));
    final f = await call('ui.pane.split', {'pane': '@focused', 'focus': true});
    final pane = f['pane']! as int;
    expect(tabs().tabOfSession(pane)!.id, 100);
    expect(tabs().selected!.focusedPaneId, pane);
    await expectLater(
      call('ui.pane.split', {'pane': 101, 'direction': 'up'}),
      fails('bad_request'),
    );
    await expectLater(call('ui.pane.split', {'pane': 999}), fails('not_found'));
    await expectLater(call('ui.pane.split'), fails('bad_request'));
  });

  test('a split from the command line asks the target pane cwd; --cwd '
      'wins', () async {
    local.replace(local.summary(100, origin: SessionOrigin.desktop, cwd: '/p'));
    await call('ui.pane.split', {'pane': 100});
    expect(local.openCwds.last, '/p');
    await call('ui.pane.split', {'pane': 100, 'cwd': '/q'});
    expect(local.openCwds.last, '/q');
  });

  test('waits for an open in flight (D33)', () async {
    local.openGate = Completer<void>();
    final userOpen = c.read(terminalTabsProvider.notifier).openTab();
    final cli = call('ui.tab.new');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(local.opens, hasLength(2)); // the user's tab and the user's open
    local.openGate!.complete();
    await userOpen;
    expect((await cli)['tab'], 102);
    expect(tabs().selectedId, 101); // the user's tab, not the agent's
  });

  test('busy once the open in flight outlasts the wait (D33)', () async {
    final other = FakeLocalSessions();
    final c2 = cliContainer(
      other,
      overrides: [
        uiCommandHandlerProvider.overrideWith(
          (ref) => UiCommandHandler(
            ref,
            openWait: const Duration(milliseconds: 150),
          ),
        ),
      ],
    );
    other.openGate = Completer<void>();
    final userOpen = c2.read(terminalTabsProvider.notifier).openTab();
    final handler = c2.read(uiCommandHandlerProvider);
    await expectLater(
      handler.handle(const MuxMessage('ui.tab.new', q: 1)),
      fails('busy'),
    );
    await expectLater(
      handler.handle(const MuxMessage('ui.workspace.new', q: 2)),
      fails('busy'),
    );
    expect(c2.read(sidebarWorkspacesProvider).workspaces, hasLength(1));
    other.openGate!.complete();
    await userOpen;
  });

  test(
    'session limit and spawn failure become their codes, no toast',
    () async {
      local.openError = const SessionLimitException(32);
      await expectLater(call('ui.tab.new'), fails('session_limit'));
      local.openError = const SpawnFailedException('No such file or directory');
      await expectLater(
        call('ui.pane.split', {'pane': 100}),
        fails('spawn_failed'),
      );
      expect(tabs().notice, isNull);
      expect(tabs().opening, isFalse);
    },
  );

  test('no room → no_room and no toast (D15)', () async {
    c.read(terminalTabsProvider.notifier).reportPaneMetrics(tinyPaneMetrics());
    await expectLater(call('ui.pane.split', {'pane': 100}), fails('no_room'));
    expect(tabs().notice, isNull);
    expect(local.opens, hasLength(1));
  });

  test('focus selects and focuses; a tab target expands its workspace '
      '(D17)', () async {
    await call('ui.tab.new'); // 101
    await call('ui.pane.split', {'pane': 101}); // 102, unfocused
    final ws = c
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'web');
    c.read(sidebarWorkspacesProvider.notifier).moveTab(101, ws);
    c.read(sidebarWorkspacesProvider.notifier).setCollapsed(ws, true);
    var raised = 0;
    h.onRaise = () async => raised++;
    await call('ui.focus', {'pane': 102});
    var s = tabs();
    expect(s.selectedId, 101);
    expect(s.selected!.focusedPaneId, 102);
    expect(side().workspace(ws)!.collapsed, isFalse);
    expect(raised, 0);
    await call('ui.focus', {'tab': 100, 'raise': true});
    s = tabs();
    expect(s.selectedId, 100);
    expect(raised, 1);
    await expectLater(call('ui.focus', {'tab': 102}), fails('not_found'));
    await expectLater(call('ui.focus'), fails('bad_request'));
  });

  test('close: running command refused without force; pane vs tab '
      '(D18)', () async {
    await call('ui.pane.split', {'pane': 100}); // 101
    local.setRunning(101, true);
    await expectLater(
      call('ui.close', {'pane': 101}),
      fails('running_command'),
    );
    await expectLater(call('ui.close', {'tab': 100}), fails('running_command'));
    expect(local.closed, isEmpty);
    expect(tabs().notice, isNull);
    await call('ui.close', {'pane': 101, 'force': true});
    expect(local.closed, contains(101));
    expect(tabs().tabOfSession(100)!.paneCount, 1);
    await call('ui.close', {'tab': 100});
    expect(tabs().tabs, isEmpty);
    await expectLater(call('ui.close', {'tab': 100}), fails('not_found'));
  });

  test('rename tab and workspaces; move a tab (D22)', () async {
    await call('ui.tab.rename', {'tab': 100, 'name': '  build  '});
    expect(tabs().selected!.customTitle, 'build');
    await call('ui.tab.rename', {'tab': 100, 'name': ''});
    expect(tabs().selected!.customTitle, isNull);
    final w = await call('ui.workspace.new', {'name': 'web'});
    final wsId = w['workspace']! as String;
    expect(side().currentId, kDefaultWorkspaceId); // no focus
    expect(tabs().selectedId, 100);
    expect(side().renaming, isNull);
    expect(side().tabsOf(wsId), [w['tab']]);
    await call('ui.workspace.rename', {'workspace': 'web', 'name': 'frontend'});
    expect(
      c.read(sidebarWorkspacesProvider.notifier).displayName(wsId),
      'frontend',
    );
    await expectLater(
      call('ui.workspace.rename', {'workspace': 'frontend', 'name': ' '}),
      fails('bad_request'),
    );
    await call('ui.workspace.move', {'tab': 100, 'workspace': 'w:$wsId'});
    expect(side().workspaceOf(100), wsId);
    expect(side().tabsOf(wsId).last, 100);
    final named = await call('ui.workspace.new');
    expect(
      c
          .read(sidebarWorkspacesProvider.notifier)
          .displayName(named['workspace']! as String),
      'Workspace 2',
    );
    final focused = await call('ui.workspace.new', {'focus': true});
    expect(tabs().selectedId, focused['tab']);
    expect(side().currentId, focused['workspace']);
  });

  test('unknown ui type; browser commands wait for A6', () async {
    await expectLater(call('ui.nope'), fails('unknown_type'));
    await expectLater(call('ui.browser.list'), fails('unknown_type'));
  });

  group('A7 Task 6 review', () {
    SidebarWorkspaces sidebar() => c.read(sidebarWorkspacesProvider.notifier);

    /// Every list of tabs the current (Default) workspace showed.
    List<List<int>> watchDefault() {
      final seen = <List<int>>[];
      c.listen<SidebarState>(
        sidebarWorkspacesProvider,
        (_, s) => seen.add(s.tabsOf(kDefaultWorkspaceId)),
      );
      return seen;
    }

    test('I1: --workspace places the tab straight there; collapsed '
        'workspaces stay collapsed', () async {
      final ws = sidebar().createFor(name: 'api');
      sidebar().setCollapsed(kDefaultWorkspaceId, true);
      sidebar().setCollapsed(ws, true);
      final seen = watchDefault();
      final r = await call('ui.tab.new', {'workspace': 'api'});
      expect(side().tabsOf(ws), [r['tab']]);
      expect(side().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
      expect(side().workspace(ws)!.collapsed, isTrue);
      expect(seen.any((ids) => ids.contains(r['tab'])), isFalse);
      expect(side().currentId, kDefaultWorkspaceId);
    });

    test('I1: workspace new never passes through the current workspace; '
        'the current one stays collapsed', () async {
      sidebar().setCollapsed(kDefaultWorkspaceId, true);
      final seen = watchDefault();
      final w = await call('ui.workspace.new', {'name': 'web'});
      expect(side().tabsOf(w['workspace']! as String), [w['tab']]);
      expect(side().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
      expect(seen.any((ids) => ids.contains(w['tab'])), isFalse);
    });

    test(
      'I1: a workspace whose tab could not open is removed, silently',
      () async {
        local.openError = const SessionLimitException(32);
        await expectLater(
          call('ui.workspace.new', {'name': 'web'}),
          fails('session_limit'),
        );
        expect(side().workspaces.map((w) => w.id), [kDefaultWorkspaceId]);
        expect(tabs().notice, isNull);
      },
    );

    test('M4: the workspace is resolved again after the wait; deleted '
        'meanwhile → not_found, nothing opened', () async {
      final ws = sidebar().createFor(name: 'api');
      local.openGate = Completer<void>();
      final user = c.read(terminalTabsProvider.notifier).openTab();
      final cli = call('ui.tab.new', {'workspace': 'api'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      sidebar().delete(ws);
      local.openGate!.complete();
      await user;
      await expectLater(cli, fails('not_found'));
      expect(local.opens, hasLength(2)); // setUp's and the user's
    });

    test('M3: a client that leaves during the D33 wait stops it; nothing '
        'opens after', () async {
      local.openGate = Completer<void>();
      final user = c.read(terminalTabsProvider.notifier).openTab();
      final left = Completer<void>();
      final cli = h.handle(
        const MuxMessage('ui.tab.new', q: 1),
        cancelled: left.future,
      );
      final ws = h.handle(
        const MuxMessage('ui.workspace.new', q: 2),
        cancelled: left.future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      left.complete();
      // At once, not after the 10 s D33 wait.
      const soon = Duration(milliseconds: 500);
      await expectLater(cli.timeout(soon), fails('cancelled'));
      await expectLater(ws.timeout(soon), fails('cancelled'));
      expect(side().workspaces, hasLength(1));
      local.openGate!.complete();
      await user;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(local.opens, hasLength(2));
    });

    test('a client that already left opens nothing (Task 7 review M3, '
        'M5)', () async {
      bool gone() => true;
      await expectLater(
        h.handle(const MuxMessage('ui.tab.new', q: 1), isGone: gone),
        fails('cancelled'),
      );
      await expectLater(
        h.handle(const MuxMessage('ui.workspace.new', q: 2), isGone: gone),
        fails('cancelled'),
      );
      expect(local.opens, hasLength(1)); // setUp's
      expect(side().workspaces, hasLength(1));
    });

    test('workspace new reports the workspace the tab really is in', () async {
      local.openGate = Completer<void>();
      final user = c.read(terminalTabsProvider.notifier).openTab();
      final cli = call('ui.workspace.new', {'name': 'web'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // The new workspace goes while its tab waits for the user's open.
      sidebar().delete(side().workspaces.last.id);
      local.openGate!.complete();
      await user;
      final r = await cli;
      expect(r['workspace'], side().workspaceOf(r['tab']! as int));
      expect(r['workspace'], kDefaultWorkspaceId);
    });

    test('M2: closing a tab marks nothing; closing a pane marks only its '
        'tab', () async {
      await call('ui.pane.split', {'pane': 100}); // 101
      c.read(agentMarksProvider.notifier).state = const AgentMarksState();
      await call('ui.close', {'pane': 101});
      expect(c.read(agentMarksProvider).tabs.keys, [100]);
      expect(c.read(agentMarksProvider).panes, isEmpty);
      await call('ui.tab.new'); // 102
      c.read(agentMarksProvider.notifier).state = const AgentMarksState();
      await call('ui.close', {'tab': 102});
      expect(c.read(agentMarksProvider).tabs, isEmpty);
      await call('ui.close', {'pane': 100}); // the last pane: the tab goes
      expect(c.read(agentMarksProvider).tabs, isEmpty);
    });

    test('M7: close @focused closes the focused pane', () async {
      await call('ui.pane.split', {'pane': 100, 'focus': true}); // 101
      await call('ui.close', {'pane': '@focused'});
      expect(local.closed, [101]);
      expect(tabs().selected!.paneOrder, [100]);
    });

    test('M7: focus on an exited pane selects and focuses it', () async {
      await call('ui.tab.new'); // 101
      await call('ui.pane.split', {'pane': 101}); // 102
      local.views[102]!.end(3);
      await pumpEventQueue();
      expect(tabs().tabOfSession(102)!.panes[102]!.exited, isTrue);
      await call('ui.focus', {'pane': 102});
      expect(tabs().selectedId, 101);
      expect(tabs().selected!.focusedPaneId, 102);
    });

    test('M7: new tab with --focus and --workspace makes that workspace '
        'current', () async {
      final ws = sidebar().createFor(name: 'api');
      final r = await call('ui.tab.new', {'workspace': 'api', 'focus': true});
      expect(tabs().selectedId, r['tab']);
      expect(side().workspaceOf(r['tab']! as int), ws);
      expect(side().currentId, ws);
    });
  });

  group('A11 D26: a new tab opens where the caller lives', () {
    late String w2;

    setUp(() async {
      w2 = c.read(sidebarWorkspacesProvider.notifier).createFor(name: 'api');
      // Tab 101 sits in `api`; the user's selected tab 100 stays in Default.
      await call('ui.tab.new', {'workspace': 'api'});
      expect(side().workspaceOf(101), w2);
      expect(tabs().selectedId, 100);
    });

    test('fromTab: the new tab goes to that tab\'s workspace and nothing is '
        'selected', () async {
      final r = await call('ui.tab.new', {'fromTab': 101});
      expect(side().workspaceOf(r['tab']! as int), w2);
      expect(tabs().selectedId, 100, reason: 'focus false by default');
      expect(side().currentId, kDefaultWorkspaceId);
    });

    test('fromPane wins over a stale fromTab: the pane moved to another '
        'tab', () async {
      final notifier = c.read(terminalTabsProvider.notifier);
      notifier.select(101);
      await notifier.split(SplitAxis.row); // pane 102 in tab 101
      expect(notifier.joinPane(102, 100), isTrue); // now in tab 100 (Default)
      expect(tabs().tabOfSession(102)!.id, 100);
      notifier.select(100);
      final r = await call('ui.tab.new', {'fromPane': 102, 'fromTab': 101});
      expect(
        side().workspaceOf(r['tab']! as int),
        kDefaultWorkspaceId,
        reason: 'the pane lives in Default now, whatever the old env says',
      );
    });

    test('a pane that is gone falls back to fromTab, then to the current '
        'workspace', () async {
      final a = await call('ui.tab.new', {'fromPane': 999, 'fromTab': 101});
      expect(side().workspaceOf(a['tab']! as int), w2);
      final b = await call('ui.tab.new', {'fromPane': 999, 'fromTab': 888});
      expect(side().workspaceOf(b['tab']! as int), kDefaultWorkspaceId);
      final closed = await call('ui.tab.new', {'fromTab': 101});
      c.read(terminalTabsProvider.notifier).close(closed['tab']! as int);
      final d = await call('ui.tab.new', {'fromTab': closed['tab']});
      expect(side().workspaceOf(d['tab']! as int), kDefaultWorkspaceId);
    });

    test('an explicit workspace wins over fromTab and fromPane', () async {
      final r = await call('ui.tab.new', {
        'workspace': 'Default',
        'fromTab': 101,
        'fromPane': 101,
      });
      expect(side().workspaceOf(r['tab']! as int), kDefaultWorkspaceId);
    });

    test('odd values are ignored, never an error', () async {
      final r = await call('ui.tab.new', {'fromTab': 'x', 'fromPane': 1.5});
      expect(side().workspaceOf(r['tab']! as int), kDefaultWorkspaceId);
    });

    test('the caller\'s workspace stays collapsed and unselected', () async {
      c.read(sidebarWorkspacesProvider.notifier).setCollapsed(w2, true);
      final r = await call('ui.tab.new', {'fromTab': 101, 'focus': false});
      expect(side().workspaceOf(r['tab']! as int), w2);
      expect(tabs().selectedId, 100);
    });
  });
}
