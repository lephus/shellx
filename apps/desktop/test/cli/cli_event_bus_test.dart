import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

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
}
