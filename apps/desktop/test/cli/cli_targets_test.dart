import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_targets.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late ProviderContainer c;

  Matcher fails(String code) =>
      throwsA(isA<CliFailure>().having((f) => f.code, 'code', code));

  setUp(() async {
    c = cliContainer(FakeLocalSessions());
    await c.read(terminalTabsProvider.notifier).openTab();
    await c.read(terminalTabsProvider.notifier).split(SplitAxis.row);
  });

  test('wire forms (D12)', () {
    expect(parseTarget(12, null), isA<PaneRef>().having((t) => t.id, 'id', 12));
    expect(parseTarget(null, 7), isA<TabRef>().having((t) => t.id, 'id', 7));
    expect(parseTarget('@focused', null), isA<FocusedRef>());
    expect(parseTarget(null, '@focused'), isA<FocusedRef>());
    expect(
      parseTarget('p12', null),
      isA<PaneRef>().having((t) => t.id, 'id', 12),
    );
    expect(
      parseTarget('p-3', null),
      isA<PaneRef>().having((t) => t.id, 'id', -3),
    );
    expect(parseTarget(null, 't7'), isA<TabRef>().having((t) => t.id, 'id', 7));
    expect(
      parseTarget('p0', null),
      isA<PaneRef>().having((t) => t.id, 'id', 0),
    );
    for (final bad in [
      (null, null),
      (1, 2),
      ('x', null),
      (1.5, null),
      ('t7', null),
      (null, 'p7'),
      ('p', null),
      ('p1x', null),
      // Canonical forms only (A7 Task 8 review M6).
      ('p01', null),
      ('p-0', null),
      ('p-01', null),
      (null, 't007'),
      (null, 't0'),
      ('p+1', null),
      ('p1234567890123456', null),
    ]) {
      expect(() => parseTarget(bad.$1, bad.$2), fails('bad_request'));
    }
  });

  test('panes and tabs resolve; focused = focused pane of the selected '
      'tab', () {
    final s = c.read(terminalTabsProvider);
    final tab = s.selected!;
    expect(tab.paneOrder, [100, 101]);
    expect(resolvePane(s, const FocusedRef()), tab.focusedPaneId);
    expect(resolveTab(s, const FocusedRef()), tab.id);
    expect(resolveTab(s, PaneRef(tab.paneOrder.last)), tab.id);
    expect(resolvePane(s, PaneRef(tab.paneOrder.first)), tab.paneOrder.first);
    expect(resolvePane(s, TabRef(tab.id)), tab.focusedPaneId);
    expect(() => resolvePane(s, const PaneRef(4242)), fails('not_found'));
    expect(() => resolveTab(s, const TabRef(4242)), fails('not_found'));
    expect(() => resolveTab(s, const PaneRef(4242)), fails('not_found'));
    // A pane id is not a tab id (A3 D1).
    expect(() => resolveTab(s, const TabRef(101)), fails('not_found'));
  });

  test('workspace by id (w: optional) or case-insensitive name; duplicates '
      'are ambiguous', () {
    final side = c.read(sidebarWorkspacesProvider.notifier);
    final a = side.createFor(name: 'API');
    side.createFor(name: 'web');
    side.createFor(name: 'Web');
    final s = c.read(sidebarWorkspacesProvider);
    String name(String id) => side.displayName(id);
    expect(resolveWorkspace(s, a, name), a);
    expect(resolveWorkspace(s, 'w:$a', name), a);
    expect(resolveWorkspace(s, 'api', name), a);
    expect(resolveWorkspace(s, 'default', name), kDefaultWorkspaceId);
    expect(resolveWorkspace(s, 'DEFAULT', name), kDefaultWorkspaceId);
    expect(() => resolveWorkspace(s, 'web', name), fails('ambiguous'));
    expect(() => resolveWorkspace(s, 'nope', name), fails('not_found'));
  });
}
