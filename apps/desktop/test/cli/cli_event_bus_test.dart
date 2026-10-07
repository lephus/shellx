import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

/// A sidebar that places tabs only when the test says so: the bus then
/// sees tabs before their workspace (as when its tab listener runs first).
final class _ManualSidebar extends SidebarWorkspaces {
  @override
  SidebarState build() => const SidebarState(
    workspaces: [Workspace(id: kDefaultWorkspaceId)],
    members: {kDefaultWorkspaceId: []},
  );

  void put(SidebarState s) => state = s;
}

ProviderContainer _manualContainer(FakeLocalSessions local) {
  final c = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      sidebarWorkspacesProvider.overrideWith(_ManualSidebar.new),
    ],
  );
  c.read(terminalTabsProvider);
  return c;
}

/// Past the 250 ms `pane.changed` window.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  late FakeLocalSessions local;

  setUp(() => local = FakeLocalSessions());

  test('tab, pane, workspace and notice events', () async {
    final c = cliContainer(local);
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab(); // 100
    await tabs.split(SplitAxis.row); // 101
    tabs.rename(100, 'build');
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final ws = side.createFor(name: 'api');
    side.moveTab(100, ws);
    local.notice(101, SessionNoticeKind.message, title: 'CI', body: 'ok');
    await pumpEventQueue();
    tabs.closePane(101);
    await settle();
    final kinds = got.map((e) => e['kind']).toList();
    expect(
      kinds,
      containsAllInOrder([
        'tab.opened',
        'pane.opened',
        'tab.renamed',
        'workspace.created',
        'tab.moved',
        'notice',
        'pane.closed',
      ]),
    );
    expect(got.firstWhere((e) => e['kind'] == 'tab.opened'), {
      'kind': 'tab.opened',
      'tab': 100,
      'workspace': kDefaultWorkspaceId,
    });
    expect(got.firstWhere((e) => e['kind'] == 'notice'), {
      'kind': 'notice',
      'pane': 101,
      'tab': 100,
      'type': 'message',
      'title': 'CI',
      'body': 'ok',
    });
    expect(got.firstWhere((e) => e['kind'] == 'pane.opened'), {
      'kind': 'pane.opened',
      'pane': 101,
      'tab': 100,
    });
    expect(got.firstWhere((e) => e['kind'] == 'tab.renamed'), {
      'kind': 'tab.renamed',
      'tab': 100,
      'title': 'build',
    });
    expect(got.firstWhere((e) => e['kind'] == 'workspace.created'), {
      'kind': 'workspace.created',
      'workspace': ws,
      'name': 'api',
    });
    expect(got.firstWhere((e) => e['kind'] == 'tab.moved'), {
      'kind': 'tab.moved',
      'tab': 100,
      'workspace': ws,
    });
    expect(got.firstWhere((e) => e['kind'] == 'pane.closed'), {
      'kind': 'pane.closed',
      'pane': 101,
      'tab': 100,
    });
    // The first pane of a new tab is reported by tab.opened only (D24).
    expect(got.where((e) => e['kind'] == 'pane.opened'), hasLength(1));
  });

  test('selection, focus, rename and delete of a workspace, exits, a '
      'closed tab', () async {
    final c = cliContainer(local);
    final tabs = c.read(terminalTabsProvider.notifier);
    final side = c.read(sidebarWorkspacesProvider.notifier);
    await tabs.openTab(); // 100
    await tabs.openTab(); // 101
    await tabs.split(SplitAxis.row); // 102 in tab 101, focused
    final ws = side.createFor(name: 'api');
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    tabs.select(100);
    tabs.focusPane(101);
    side.rename(ws, 'web');
    side.delete(ws);
    local.views[102]!.end(3);
    await settle();
    local.views[101]!.end(0); // exit 0: the pane goes (A3 D7)
    await settle();
    // The agent forgets an ended session.
    local.summaries.removeWhere((s) => s.id == 101);
    tabs.close(100);
    await settle();
    expect(
      got,
      containsAllInOrder([
        {'kind': 'tab.selected', 'tab': 100},
        // focusPane focuses, then selects its tab.
        {'kind': 'pane.focused', 'pane': 101, 'tab': 101},
        {'kind': 'tab.selected', 'tab': 101},
        {'kind': 'workspace.renamed', 'workspace': ws, 'name': 'web'},
        {'kind': 'workspace.deleted', 'workspace': ws},
        {'kind': 'pane.exited', 'pane': 102, 'tab': 101, 'exitCode': 3},
        {'kind': 'pane.exited', 'pane': 101, 'tab': 101, 'exitCode': 0},
        {'kind': 'pane.closed', 'pane': 101, 'tab': 101},
        {'kind': 'tab.closed', 'tab': 100},
      ]),
    );
  });

  test('pane.changed is coalesced to one event per 250 ms with the latest '
      'values', () async {
    final c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab();
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    local.setCwd(100, '/a');
    local.setCwd(100, '/b');
    await settle();
    final changed = got.where((e) => e['kind'] == 'pane.changed').toList();
    expect(changed, hasLength(1));
    expect(changed.single, {
      'kind': 'pane.changed',
      'pane': 100,
      'tab': 100,
      'title': 'zsh 1',
      'cwd': '/b',
      'branch': null,
      'ports': const <int>[],
      'running': false,
    });
    local.setCwd(100, '/b'); // nothing new
    await settle();
    expect(got.where((e) => e['kind'] == 'pane.changed'), hasLength(1));
  });

  test('pane.changed only for the pane that changed, also on the first '
      'change after subscribing', () async {
    final c = cliContainer(local);
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab(); // 100
    await tabs.openTab(); // 101
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    local.setCwd(101, '/x');
    await settle();
    expect(
      got.where((e) => e['kind'] == 'pane.changed').map((e) => e['pane']),
      [101],
    );
  });

  test('no history: a late listener gets only what happens after it '
      'came', () async {
    final c = cliContainer(local);
    final bus = c.read(cliEventBusProvider);
    final early = <Map<String, Object?>>[];
    bus.events.listen(early.add);
    await c.read(terminalTabsProvider.notifier).openTab();
    final late = <Map<String, Object?>>[];
    bus.events.listen(late.add);
    await pumpEventQueue();
    expect(early, isNotEmpty);
    expect(late, isEmpty);
  });

  group('a tab the sidebar has not placed yet (A7 Task 8 review)', () {
    late ProviderContainer c;
    late _ManualSidebar side;
    late List<Map<String, Object?>> got;

    setUp(() {
      c = _manualContainer(local);
      side = c.read(sidebarWorkspacesProvider.notifier) as _ManualSidebar;
      got = [];
      c.read(cliEventBusProvider).events.listen(got.add);
    });

    test('M1: its selection, focus and changes wait for tab.opened', () async {
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTab(); // 100, selected
      await tabs.split(SplitAxis.row); // 101, focused
      local.setCwd(100, '/a');
      await settle();
      expect(got, isEmpty);
      side.put(
        const SidebarState(
          workspaces: [Workspace(id: kDefaultWorkspaceId)],
          members: {
            kDefaultWorkspaceId: [100],
          },
        ),
      );
      await pumpEventQueue();
      final kinds = got.map((e) => e['kind']).toList();
      expect(kinds.first, 'tab.opened');
      expect(
        kinds,
        containsAll(['tab.selected', 'pane.opened', 'pane.focused']),
      );
      expect(kinds.where((k) => k == 'tab.opened'), hasLength(1));
    });

    test(
      'M2: workspace.created comes before the tab.opened it holds',
      () async {
        await c.read(terminalTabsProvider.notifier).openTab(); // 100
        side.put(
          const SidebarState(
            workspaces: [
              Workspace(id: kDefaultWorkspaceId),
              Workspace(id: 'w1', name: 'api'),
            ],
            members: {
              kDefaultWorkspaceId: [],
              'w1': [100],
            },
          ),
        );
        await pumpEventQueue();
        expect(got.map((e) => e['kind']), [
          'workspace.created',
          'tab.opened',
          'tab.selected', // held for tab.opened (M1)
        ]);
        expect(got[1]['workspace'], 'w1');
      },
    );

    test('M3: closed before it was placed: nothing at all', () async {
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTab(); // 100
      tabs.close(100);
      await settle();
      expect(got, isEmpty);
    });
  });

  test(
    'a reconnect is one pane.replaced, not a close and an open (D22, D4)',
    () async {
      local.notifyOnOpen = true; // as the real manager
      final c = cliContainer(local);
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTab(launch: SshLaunch(SshTarget.parse('devbox')!)); // 100
      final got = <Map<String, Object?>>[];
      c.read(cliEventBusProvider).events.listen(got.add);
      await pumpEventQueue();
      local.summaries.removeWhere((s) => s.id == 100); // an ended session
      local.views[100]!.end(255);
      await pumpEventQueue();
      final fresh = (await tabs.reconnect(100))!;
      await settle();
      final kinds = got.map((e) => e['kind']).toList();
      expect(kinds, contains('pane.replaced'));
      expect(kinds, isNot(contains('pane.closed')));
      expect(kinds, isNot(contains('pane.opened')));
      expect(kinds, isNot(contains('pane.focused')));
      expect(kinds, isNot(contains('tab.closed')));
      expect(kinds, isNot(contains('tab.opened')));
      expect(got.where((e) => e['kind'] == 'pane.replaced').single, {
        'kind': 'pane.replaced',
        'old': 100,
        'new': fresh,
        'tab': 100,
      });
      // Ordinary closes and opens afterwards are reported as before.
      got.clear();
      await tabs.openTab(); // 101
      await settle();
      expect(got.map((e) => e['kind']), contains('tab.opened'));
    },
  );

  test('two reconnects before one diff: still no pane.focused', () async {
    local.notifyOnOpen = true;
    final c = cliContainer(local);
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTab(launch: SshLaunch(SshTarget.parse('devbox')!)); // 100
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    await pumpEventQueue();
    var current = 100;
    for (var i = 0; i < 2; i++) {
      local.summaries.removeWhere((s) => s.id == current);
      local.views[current]!.end(255);
      await pumpEventQueue();
      current = (await tabs.reconnect(current))!;
    }
    await settle();
    final kinds = got.map((e) => e['kind']).toList();
    expect(kinds.where((k) => k == 'pane.replaced'), hasLength(2));
    expect(kinds, isNot(contains('pane.focused')));
    expect(kinds, isNot(contains('pane.closed')));
    expect(kinds, isNot(contains('pane.opened')));
  });
}
