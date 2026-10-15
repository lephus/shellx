import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/tools/tool_area.dart';

import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

void main() {
  late ToolRig rig;

  setUp(() => rig = ToolRig());
  tearDown(() async {});

  /// What a sidebar row, the palette and Settings do (D4).
  Future<void> openTool(WidgetTester t, String id) async {
    Actions.invoke(t.element(find.byType(ToolArea)), OpenToolIntent(id));
    await t.pumpAndSettle();
  }

  testWidgets('opening a tool shows the dock beside the panes; the page '
      'loads its URL and gets the keyboard (D3, D4)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173', name: 'Board');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.bar.name')), findsOneWidget);
    expect(find.text('localhost:5173 · On this computer'), findsOneWidget);
    final engine = rig.engines[tool.id]!;
    expect(engine.loads, [Uri.parse('http://localhost:5173/')]);
    expect(engine.calls, contains('focus'));
    final dock = t.getRect(find.byKey(const ValueKey('tool.dockSlot')));
    expect(dock.width, 396, reason: '45 % of the 879 px content area');
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Review Focus 1: switching tabs, opening the palette and '
      'resizing keep the same page — one engine, one view, one load', (
    t,
  ) async {
    await rig.pump(t);
    await rig.container.read(terminalTabsProvider.notifier).openTab();
    await t.pumpAndSettle();
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    final tabs = rig.container.read(terminalTabsProvider).tabs;
    rig.container.read(terminalTabsProvider.notifier).select(tabs.first.id);
    await t.pumpAndSettle();
    rig.container.read(terminalTabsProvider.notifier).select(tabs.last.id);
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    t.view.physicalSize = const Size(1300, 800);
    await t.pumpAndSettle();
    expect(rig.made, 1);
    expect(engine.builds, 1);
    expect(engine.loads, hasLength(1));
    expect(engine.calls, isNot(contains('reload')));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('chips from two tools; × on the last chip closes the dock '
      '(D5, D10)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'A');
    final b = rig.add(kDefaultWorkspaceId, 'localhost:2', name: 'B');
    await t.pumpAndSettle();
    await openTool(t, a.id);
    expect(find.byKey(Key('tool.chip.${a.id}')), findsNothing);
    await openTool(t, b.id);
    expect(find.byKey(Key('tool.chip.${a.id}')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(Key('tool.chip.${a.id}')),
        matching: find.text('A'),
      ),
    );
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
      a.id,
    );
    expect(rig.engines[b.id]!.disposed, isFalse, reason: 'D5: kept');
    await t.tap(find.byKey(Key('tool.chip.${a.id}.close')));
    await t.pumpAndSettle();
    expect(rig.engines[a.id]!.disposed, isTrue);
    await t.tap(find.byKey(const Key('tool.bar.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Expand covers the content area; Restore and Esc bring it '
      'back (D3)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('tool.dockSlot'))).width, 879);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    expect(t.getRect(find.byKey(const ValueKey('tool.dockSlot'))).width, 396);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).zoom,
      isFalse,
    );
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('⌘⇧B closes and reopens the dock; ⌘W in the dock closes the '
      'tool on show (D10)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(key);
      if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
    }

    await chord(LogicalKeyboardKey.keyB, shift: true);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(rig.engines[tool.id]!.disposed, isFalse, reason: 'D5');
    await chord(LogicalKeyboardKey.keyB, shift: true);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(rig.engines[tool.id]!.loads, hasLength(1), reason: 'RF1');
    await chord(LogicalKeyboardKey.keyW);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(rig.engines[tool.id]!.disposed, isTrue);
    expect(rig.container.read(terminalTabsProvider).tabs, hasLength(1));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    '⌘⇧B with no tool asks for one (D10)',
    (t) async {
      await rig.pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('tool.dialog.url')),
        'localhost:4000',
      );
      await t.tap(find.byKey(const Key('tool.dialog.save')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('the bar follows the page: stop while loading, the refused '
      'panel, ATS, away and back (D13, D17, Review Focus 3)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(find.byKey(const Key('tool.bar.stop')), findsOneWidget);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
    await t.pump();
    expect(find.byKey(const Key('tool.error.refused')), findsOneWidget);
    expect(
      find.textContaining('Nothing is running at localhost:5173'),
      findsOneWidget,
    );
    await t.pump(const Duration(seconds: 1));
    expect(engine.loads, hasLength(2), reason: 'the 1 s retry');
    engine.emit(const LoadStarted());
    engine.emit(const LoadFinished());
    await t.pump();
    expect(find.byKey(const Key('tool.error.refused')), findsNothing);
    expect(find.byKey(const Key('tool.bar.reload')), findsOneWidget);
    engine.emit(const LoadFailed(BrowserLoadErrorKind.ats));
    await t.pump();
    expect(find.byKey(const Key('tool.error.ats')), findsOneWidget);
    expect(find.byKey(const Key('tool.error.reload')), findsNothing);
    engine.emit(const LoadStarted());
    engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
    engine.emit(const LoadFinished());
    await t.pump();
    expect(find.text('On sso.example.com'), findsOneWidget);
    await t.tap(find.byKey(const Key('tool.bar.backToTool')));
    await t.pump();
    expect(engine.loads.last, Uri.parse('http://localhost:5173/'));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'a forwarded ⌘T runs New tab (D10)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      expect(rig.engines[tool.id]!.forwarded, contains('super+t'));
      rig.engines[tool.id]!.emit(const ShortcutForwarded('super+t'));
      await t.pumpAndSettle();
      expect(rig.container.read(terminalTabsProvider).tabs, hasLength(2));
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a download shows its line with the browser button (D9)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      rig.engines[tool.id]!.emit(
        DownloadBlocked(url: Uri.parse('http://localhost:1/a.zip')),
      );
      await t.pump();
      await t.tap(find.byKey(const Key('tool.download.browser')));
      await t.pump();
      expect(rig.harness.urlOpener.webLinks, [
        Uri.parse('http://localhost:1/a.zip'),
      ]);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'tool-embed = off: opening a tool opens the browser (D20)',
    (t) async {
      await rig.pump(t, config: 'tool-embed = off\n');
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
      expect(rig.harness.urlOpener.webLinks, [
        Uri.parse('http://localhost:1/'),
      ]);
      expect(rig.made, 0);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Windows-like engine: a menu over the window hides the page '
      'behind a stand-in (D7)', (t) async {
    rig = ToolRig(coversFlutter: true);
    await rig.pump(t, config: 'tool-embed = on\n');
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'Board');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(engine.visible, isNot(false));
    await t.tap(find.byKey(const Key('tool.bar.more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.covered')), findsOneWidget);
    expect(find.text('Board — hidden while a menu is open'), findsOneWidget);
    expect(engine.visible, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('tool.covered')), findsNothing);
    expect(engine.visible, isTrue);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a tool of a workspace without a tab: its dock beside an '
      'empty area; ⌘T opens a tab there (D4)', (t) async {
    await rig.pump(t);
    final side = rig.container.read(sidebarWorkspacesProvider.notifier);
    final ws = side.createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.loose')), findsOneWidget);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, isNull);
    final selected = rig.container.read(terminalTabsProvider).selectedId!;
    expect(
      rig.container.read(sidebarWorkspacesProvider).workspaceOf(selected),
      ws,
    );
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'the palette lists "Open tool: {name}" and opens it (D4)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'Board');
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyP);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Open tool');
      await t.pumpAndSettle();
      await t.tap(find.text('Open tool: Board'));
      await t.pumpAndSettle();
      expect(
        rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
        tool.id,
      );
      expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a click on the row of the tab still selected under a '
      'workspace shown without a tab ends it: the panes show again; until '
      'then no pane or tab command reaches that tab (R14, D4)', (t) async {
    await rig.pump(t, config: 'command = Lint = npm run lint\n');
    final tabs = rig.container.read(terminalTabsProvider.notifier);
    final first = rig.container.read(terminalTabsProvider).selectedId!;
    await tabs.openTab();
    await t.pumpAndSettle();
    await tabs.split(SplitAxis.row);
    await t.pumpAndSettle();
    final under = rig.container.read(terminalTabsProvider).selectedId!;
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    // The selected tab's pane and tab commands, each one applicable here
    // (a split tab, another tab, another workspace).
    final commands = <Intent>[
      const SwapPaneIntent(PaneDirection.left),
      JoinPaneIntent(tabId: first),
      MoveTabToWorkspaceIntent(ws),
      const TogglePinTabIntent(),
      const CloseWholeTabIntent(),
    ];
    bool enabled(Intent intent) => Actions.find<Intent>(
      t.element(find.byType(ToolArea)),
      intent: intent,
    ).isEnabled(intent);
    Future<void> palette() async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyP);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'Move');
      await t.pumpAndSettle();
    }

    Future<void> closePalette() async {
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    }

    expect(commands.where(enabled), hasLength(commands.length));
    await palette();
    expect(find.text('Move tab to B'), findsOneWidget);
    await closePalette();

    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.loose')), findsOneWidget);
    expect(rig.container.read(terminalTabsProvider).selectedId, under);
    // R14: nothing of the covered tab is reachable meanwhile.
    expect(commands.where(enabled), isEmpty);
    await palette();
    expect(find.text('Move tab to B'), findsNothing);
    expect(find.textContaining('Move pane to tab'), findsNothing);
    await closePalette();
    // D35: a user command runs nothing out of sight; it answers as with no
    // live terminal.
    final covered = rig.container.read(terminalTabsProvider).selected!;
    Actions.invoke(
      t.element(find.byType(ToolArea)),
      const RunUserCommandIntent('Lint'),
    );
    await t.pump();
    await t.pump();
    expect(
      rig.container.read(terminalTabsProvider).notice,
      isA<NoTerminalForCommandNotice>(),
    );
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    expect(local.views[covered.focusedPaneId]!.writes, isEmpty);
    // The same tab again: no selection change for the dock to hear.
    await t.tap(find.byKey(ValueKey('tab.$under')));
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, isNull);
    expect(find.byKey(const Key('tool.loose')), findsNothing);
    expect(find.byKey(ValueKey('tool.dock.$ws')), findsNothing);
    expect(
      t.getRect(find.byKey(const ValueKey('tool.panesSlot'))).width,
      879,
      reason: 'the whole content area is the panes again',
    );
    expect(rig.engines[tool.id]!.disposed, isFalse, reason: 'D5: kept');
    expect(commands.where(enabled), hasLength(commands.length));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a jump to the tab still selected under a workspace shown '
      'without a tab (a notification, ⌘⇧U) ends it: the panes show (R14, '
      'D4)', (t) async {
    await rig.pump(t);
    final under = rig.container.read(terminalTabsProvider).selectedId!;
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const Key('tool.loose')), findsOneWidget);
    expect(
      rig.container.read(tabAttentionProvider.notifier).jumpTo(under),
      isTrue,
    );
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, isNull);
    expect(find.byKey(const Key('tool.loose')), findsNothing);
    expect(t.getRect(find.byKey(const ValueKey('tool.panesSlot'))).width, 879);
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(page.terminalFocus.hasFocus, isTrue);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a window too narrow for the dock beside the panes opens it '
      'expanded; Restore hides it again and the panes show (§8)', (t) async {
    await rig.pump(t);
    t.view.physicalSize = const Size(800, 800);
    await t.pumpAndSettle();
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('tool.dockSlot'))),
      t.getRect(find.byType(ToolArea)),
      reason: 'the whole 579 px content area',
    );
    final engine = rig.engines[tool.id]!;
    expect(engine.loads, [Uri.parse('http://localhost:1/')]);
    expect(engine.calls, contains('focus'));
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(t.getRect(find.byKey(const ValueKey('tool.panesSlot'))).width, 579);
    expect(engine.disposed, isFalse, reason: 'D5: kept');
    // D10: hidden by the width, the dock reads as closed: ⌘⇧B shows it
    // again, expanded and with the keyboard; ⌘⇧B again closes it.
    Future<void> toggleTools() async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
    }

    await toggleTools();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('tool.dockSlot'))),
      t.getRect(find.byType(ToolArea)),
    );
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    expect(page.toolDockFocus.hasPrimaryFocus, isTrue);
    await toggleTools();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).open,
      isFalse,
    );
    expect(engine.loads, hasLength(1));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a file dropped on the panel of a workspace shown without a '
      'tab types nothing into the covered terminal, and the workspace stays '
      'shown (R14)', (t) async {
    await rig.pump(t);
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final pane = rig.container.read(terminalTabsProvider).selected!;
    final writes = local.views[pane.focusedPaneId]!.writes;
    // As the platform reports a drop through desktop_drop's channel.
    Future<void> drop(Offset at, String path) async {
      const channel = MethodChannel('desktop_drop');
      Future<void> send(String method, Object arguments) =>
          t.binding.defaultBinaryMessenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, arguments)),
            (_) {},
          );
      await send('entered', [at.dx, at.dy]);
      await send('performOperation', [path]);
      await t.pump();
      await t.pump();
    }

    // A drop reaches the pane while it shows.
    await drop(t.getCenter(find.byKey(const ValueKey('tool.panesSlot'))), '/a');
    expect(writes.join(), '/a ');
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await drop(t.getCenter(find.byKey(const Key('tool.loose'))), '/b');
    await t.pumpAndSettle();
    expect(writes.join(), '/a ');
    expect(rig.container.read(toolDockProvider).loose, ws);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Review Focus 1: another workspace\'s tab and back keep the '
      'same page — one engine, one load, no reload (§10)', (t) async {
    await rig.pump(t);
    final a = rig.container.read(terminalTabsProvider).selectedId!;
    final side = rig.container.read(sidebarWorkspacesProvider.notifier);
    final ws = side.createFor(name: 'B');
    await side.openTabIn(ws);
    await t.pumpAndSettle();
    final b = rig.container.read(terminalTabsProvider).selectedId!;
    expect(rig.container.read(sidebarWorkspacesProvider).workspaceOf(b), ws);
    final tabs = rig.container.read(terminalTabsProvider.notifier);
    tabs.select(a);
    await t.pumpAndSettle();
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    tabs.select(b);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    tabs.select(a);
    await t.pumpAndSettle();
    expect(rig.made, 1);
    expect(engine.disposed, isFalse);
    expect(engine.loads, hasLength(1));
    expect(engine.calls, isNot(contains('reload')));
    expect(find.byKey(Key('browser.fakeView.${tool.id}')), findsOneWidget);
    expect(
      rig.container.read(toolPagesProvider.notifier).existing(tool.id)!.shown,
      isTrue,
    );
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'a new URL from "Edit tool…" loads in the same page (D23)',
    (t) async {
      await rig.pump(t);
      final tool = rig.add(
        kDefaultWorkspaceId,
        'localhost:5173',
        name: 'Board',
      );
      await t.pumpAndSettle();
      await openTool(t, tool.id);
      final engine = rig.engines[tool.id]!;
      await t.tap(find.byKey(const Key('tool.bar.more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tool.menu.edit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('tool.dialog.url')),
        'localhost:5174',
      );
      await t.tap(find.byKey(const Key('tool.dialog.save')));
      await t.pumpAndSettle();
      expect(rig.made, 1);
      expect(engine.disposed, isFalse);
      expect(engine.loads, [
        Uri.parse('http://localhost:5173/'),
        Uri.parse('http://localhost:5174/'),
      ]);
      expect(find.text('localhost:5174 · On this computer'), findsOneWidget);
      await disposeWorkspace(t, rig.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('a forwarded first step arms the sequence and gives the '
      'keyboard back to the dock; the second step runs the action (R8, '
      'D10)', (t) async {
    await rig.pump(t, config: 'keybind = ctrl+a>c=new_tab\n');
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(engine.forwarded, contains('ctrl+a'));
    final dock = t
        .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
        .toolDockFocus;
    expect(dock.hasPrimaryFocus, isTrue);
    final before = engine.calls.length;
    engine.emit(const ShortcutForwarded('ctrl+a'));
    await t.pump();
    expect(rig.container.read(keySequenceProvider), parseKeyChord('ctrl+a'));
    expect(engine.calls.skip(before), ['release']);
    expect(dock.hasPrimaryFocus, isTrue, reason: 'the wait is not cancelled');
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.pumpAndSettle();
    expect(rig.container.read(keySequenceProvider), isNull);
    expect(rig.container.read(terminalTabsProvider).tabs, hasLength(2));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('with no tab at all, "Open new tab" gets the keyboard: the '
      'empty pane\'s once ⌘⇧B closes the dock; the loose panel\'s own by F6 '
      'and from the dock, where Enter opens a tab in that workspace (D4, '
      'D10, D18)', (t) async {
    await rig.pump(t);
    rig.container
        .read(terminalTabsProvider.notifier)
        .close(rig.container.read(terminalTabsProvider).tabs.single.id);
    await t.pumpAndSettle();
    final page = t.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    bool focusIn(Finder finder) {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused != null &&
          find
              .descendant(
                of: finder,
                matching: find.byElementPredicate((e) => identical(e, focused)),
              )
              .evaluate()
              .isNotEmpty;
    }

    await openTool(t, tool.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(rig.container.read(toolDockProvider).loose, isNull);
    expect(page.emptyFocus.hasPrimaryFocus, isTrue);

    // The dock again. F6 goes to the content region, the loose panel;
    // ⌘⌥→ enters the dock, ⌘⌥← leaves it for the loose panel again.
    await openTool(t, tool.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    expect(page.toolDockFocus.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.f6);
    await t.pumpAndSettle();
    expect(focusIn(find.byKey(const Key('tool.loose'))), isTrue);
    Future<void> focusPane(LogicalKeyboardKey arrow) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyEvent(arrow);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
    }

    await focusPane(LogicalKeyboardKey.arrowRight);
    expect(page.toolDockFocus.hasPrimaryFocus, isTrue);
    await focusPane(LogicalKeyboardKey.arrowLeft);
    expect(focusIn(find.byKey(const Key('tool.loose'))), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    final selected = rig.container.read(terminalTabsProvider).selectedId!;
    expect(
      rig.container.read(sidebarWorkspacesProvider).workspaceOf(selected),
      ws,
    );
    expect(rig.container.read(toolDockProvider).loose, isNull);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
