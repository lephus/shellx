import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/terminal/workspace_header.dart';
import 'package:shellx_desktop/src/ui/tools/tool_sidebar_group.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  testWidgets('each workspace\'s tools sit under it in a foldable group; '
      '"· on phone too"; the row on show is lit (D21)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    rig.container
        .read(toolRegistryProvider.notifier)
        .update(a.copyWith(phone: true));
    final ws2 = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'Shop');
    final b = rig.add(ws2, 'https://grafana.example.com', name: 'Grafana');
    await t.pumpAndSettle();
    expect(find.byKey(Key('sidebar.tool.${a.id}')), findsOneWidget);
    expect(find.byKey(Key('sidebar.tool.${b.id}')), findsOneWidget);
    expect(find.text('localhost:4000 · on phone too'), findsOneWidget);
    expect(find.text('grafana.example.com:443'), findsOneWidget);
    await t.tap(find.byKey(const Key('sidebar.tools.$kDefaultWorkspaceId')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('sidebar.tool.${a.id}')), findsNothing);
    await t.tap(find.byKey(const Key('sidebar.tools.$kDefaultWorkspaceId')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('sidebar.tool.${a.id}')));
    await t.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(Key('sidebar.tool.${a.id}')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('right-click: Delete asks, then the tool, its chip and its '
      'page go (D21, D23)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('sidebar.tool.${a.id}')));
    await t.pumpAndSettle();
    await t.tap(
      find.byKey(Key('sidebar.tool.${a.id}')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tool.row.menu.delete')));
    await t.pumpAndSettle();
    final confirm = rig.container.read(windowRouterProvider).confirm!;
    expect(
      confirm.title,
      'Delete the tool "Board"? Its page closes. Its web data stays.',
    );
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(rig.container.read(toolRegistryProvider), isEmpty);
    expect(rig.engines[a.id]!.disposed, isTrue);
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).open,
      isFalse,
    );
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('"Add tool" sits beside "New AI session" at the foot: the AI '
      'button keeps room for its whole label and "Add tool" is a small icon '
      'button with a tooltip and a label (D21, D18)', (t) async {
    final semantics = t.ensureSemantics();
    await rig.pump(t);
    final aiButton = find.byKey(const Key('sidebar.newAi'));
    final addButton = find.byKey(const Key('sidebar.addTool'));
    final ai = t.getRect(aiButton);
    final add = t.getRect(addButton);
    expect(add.top, ai.top);
    expect(add.left, greaterThan(ai.left));
    expect(
      add.left,
      greaterThanOrEqualTo(ai.right),
      reason: 'beside, not over',
    );
    // The sidebar is 220 px, so its footer row is 204: "New AI session"
    // needs about 152 px of button with the system font, and "Add tool" is
    // an icon on the right.
    expect(ai.width, greaterThanOrEqualTo(150));
    expect(add.width, lessThanOrEqualTo(48));
    expect(
      find.ancestor(of: addButton, matching: find.byTooltip('Add tool')),
      findsOneWidget,
    );
    expect(
      t.getSemantics(addButton),
      isSemantics(label: 'Add tool', isButton: true),
    );
    semantics.dispose();
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('criterion 1: "Add tool", a suggestion, Add — the dock is '
      'open on the page in three clicks (D12, D21)', (t) async {
    await rig.pump(t);
    rig.probe.ports[7] = {5173};
    rig.probe.table[7] = (parent: 1, name: 'vite');
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final session = rig.container.read(terminalTabsProvider).tabs.single.id;
    local.replace(local.summary(session, ports: [5173]));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sidebar.addTool')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('tool.suggestion.5173')));
    await t.pump();
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    final tool = rig.container.read(toolRegistryProvider).single;
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(rig.engines[tool.id]!.loads, [Uri.parse('http://localhost:5173/')]);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('tools that open in the browser show ↗ on their row (D20)', (
    t,
  ) async {
    await rig.pump(t, config: 'tool-embed = off\n');
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('sidebar.tool.browserMark')), findsOneWidget);
    await t.tap(find.byKey(Key('sidebar.tool.${tool.id}')));
    await t.pumpAndSettle();
    expect(rig.harness.urlOpener.webLinks, [Uri.parse('http://localhost:1/')]);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('the list\'s arrows end a workspace shown without a tab when '
      'they choose a tab, even the one already selected — not on a header; '
      'tool rows are no arrow-key stop (R14, R11)', (t) async {
    await rig.pump(t);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    final underneath = rig.container.read(terminalTabsProvider).selectedId!;
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('sidebar.tool.${tool.id}')));
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, ws);
    expect(rig.container.read(terminalTabsProvider).selectedId, underneath);

    // The list's keyboard, its cursor on the tab selected underneath.
    page.sidebarFocus.requestFocus();
    await t.pump();
    final cursorOnB = find.byWidgetPredicate(
      (w) => w is WorkspaceHeader && w.focused && w.workspaceId == ws,
    );

    // ↓ onto the other workspace's header chooses no tab.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(cursorOnB, findsOneWidget);
    expect(rig.container.read(toolDockProvider).loose, ws);
    // ↓ again: its tool row is no stop, so the cursor stays on the header.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(cursorOnB, findsOneWidget);
    expect(rig.container.read(toolDockProvider).loose, ws);
    // ↑ chooses the tab selected underneath. Selecting it again changes
    // nothing in the tabs, so the dock's own listener never sees it.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(cursorOnB, findsNothing);
    expect(rig.container.read(terminalTabsProvider).selectedId, underneath);
    expect(rig.container.read(toolDockProvider).loose, isNull);
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a tool row is 36 px at 1x and tall enough for both of its '
      'lines at any text size (D18)', (t) async {
    await rig.pump(t);
    rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    await t.pumpAndSettle();
    // 1x: the 24 px header, then 36 px per tool, none when folded.
    expect(
      ToolSidebarGroup.heightFor(TextScaler.noScaling, count: 2, folded: false),
      24 + 2 * 36,
    );
    expect(
      ToolSidebarGroup.heightFor(TextScaler.noScaling, count: 2, folded: true),
      24,
    );
    final group = find.byType(ToolSidebarGroup);
    expect(t.getSize(group).height, 24 + 36);
    // 2.25x is Windows' largest text size; the sidebar lays the group out
    // with the height it reports.
    addTearDown(t.platformDispatcher.clearAllTestValues);
    for (final scale in [2.25, 3.0]) {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'at $scale x');
      expect(
        t.getSize(group).height,
        ToolSidebarGroup.heightFor(
          TextScaler.linear(scale),
          count: 1,
          folded: false,
        ),
      );
    }
    await disposeWorkspace(t, rig.container);
  });

  testWidgets('a list with no tab and a tool is no Tab stop; the tool\'s row '
      'is still a button the keyboard reaches (UI §3.6, D18)', (t) async {
    await rig.pump(t);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    final tabs = rig.container.read(terminalTabsProvider.notifier);
    tabs.close(rig.container.read(terminalTabsProvider).tabs.single.id);
    await t.pumpAndSettle();
    expect(
      page.sidebarFocus.canRequestFocus,
      isFalse,
      reason: 'no row to walk',
    );
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    await t.pumpAndSettle();
    final row = find.byKey(Key('sidebar.tool.${tool.id}'));
    expect(row, findsOneWidget);
    expect(page.sidebarFocus.canRequestFocus, isFalse);
    expect(page.sidebarFocus.skipTraversal, isTrue);
    // The row is a button of its own: it takes the keyboard, and Enter
    // opens the tool.
    bool dockOpen() =>
        rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).open;
    expect(dockOpen(), isFalse);
    Focus.of(
      t.element(find.descendant(of: row, matching: find.byType(Icon)).first),
    ).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(dockOpen(), isTrue);
    await disposeWorkspace(t, rig.container);
  });
}
