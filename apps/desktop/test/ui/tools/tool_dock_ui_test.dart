import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart' show FakeScenario;
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_dock.dart';
import 'package:shellx_desktop/src/tools/tool_dock_state.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/terminal/key_sequence.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_intents.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/tools/tool_area.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_local_sessions.dart';
import '../../support/tool_harness.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGA'
  'WjR9awAAAABJRU5ErkJggg==',
);

void main() {
  late ToolRig rig;

  setUp(() => rig = ToolRig());
  tearDown(() async {});

  /// What a sidebar row, the palette and Settings do (D4).
  Future<void> openTool(WidgetTester t, String id) async {
    Actions.invoke(t.element(find.byType(ToolArea)), OpenToolIntent(id));
    await t.pumpAndSettle();
  }

  /// ⌘⇧B (D10).
  Future<void> toggleTools(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
  }

  /// The name on the dock's bar: the tool on show.
  String? barName(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('tool.bar.name'))).data;

  /// A file dropped at [at], as the platform reports it through
  /// desktop_drop's channel (the plugin picks targets by their bounds, not by
  /// what is on top).
  Future<void> drop(WidgetTester t, Offset at, String path) async {
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

  testWidgets('the panes count as covered exactly while the window draws a '
      'zoomed dock or a loose panel over them; a dock beside them, or one a '
      'narrow window hides, covers nothing (V2-3 D3, D4, §8)', (t) async {
    await rig.pump(t);
    bool covered() => rig.container.read(toolPanesCoveredProvider);
    bool drawnOver() {
      if (find.byKey(const Key('tool.loose')).evaluate().isNotEmpty) {
        return true;
      }
      final dock = find.byKey(const ValueKey('tool.dockSlot'));
      return dock.evaluate().isNotEmpty &&
          t.getRect(dock) == t.getRect(find.byType(ToolArea));
    }

    bool panesOutOfReach() => t
        .widget<ExcludeFocus>(
          find
              .descendant(
                of: find.byKey(const ValueKey('tool.panesSlot')),
                matching: find.byType(ExcludeFocus),
              )
              .first,
        )
        .excluding;
    void agree(String why, {required bool expected}) {
      expect(drawnOver(), expected, reason: why);
      expect(covered(), expected, reason: why);
      expect(panesOutOfReach(), expected, reason: why);
    }

    agree('no dock', expected: false);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    agree('beside the panes', expected: false);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    agree('zoomed', expected: true);
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    agree('restored', expected: false);
    t.view.physicalSize = const Size(800, 800);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    agree('hidden by a narrow window', expected: false);
    rig.container
        .read(toolDockProvider.notifier)
        .setZoom(kDefaultWorkspaceId, true);
    await t.pumpAndSettle();
    agree('zoomed in a narrow window', expected: true);
    rig.container
        .read(toolDockProvider.notifier)
        .setZoom(kDefaultWorkspaceId, false);
    t.view.physicalSize = const Size(1100, 720);
    await t.pumpAndSettle();
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final other = rig.add(ws, 'localhost:2');
    await t.pumpAndSettle();
    await openTool(t, other.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    agree('a workspace shown without a tab', expected: true);
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

  testWidgets('⌘⇧B on a closed dock without chips reopens the tool viewed '
      'last: the chip a closed chip handed over to (D10)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'A');
    final b = rig.add(kDefaultWorkspaceId, 'localhost:2', name: 'B');
    await t.pumpAndSettle();
    await openTool(t, a.id);
    await openTool(t, b.id);
    // B's chip closes: A shows, then A closes too (the last chip: the dock
    // closes).
    await t.tap(find.byKey(Key('tool.chip.${b.id}.close')));
    await t.pumpAndSettle();
    expect(barName(t), 'A');
    await t.tap(find.byKey(const Key('tool.bar.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    await toggleTools(t);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
      a.id,
    );
    expect(barName(t), 'A');
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('⌘⇧B on a closed dock without chips reopens the tool viewed '
      'last: the restored one, not the workspace\'s first tool (D10, D14)', (
    t,
  ) async {
    await rig.pump(t);
    final first = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'First');
    final a = rig.add(kDefaultWorkspaceId, 'localhost:2', name: 'A');
    await t.pumpAndSettle();
    rig.container.read(toolDockProvider.notifier).restore({
      kDefaultWorkspaceId: ToolDockState(
        open: true,
        active: a.id,
        tools: [a.id],
      ),
    });
    await t.pumpAndSettle();
    expect(barName(t), 'A');
    await t.tap(find.byKey(const Key('tool.bar.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    await toggleTools(t);
    expect(
      rig.container.read(toolDockProvider).of(kDefaultWorkspaceId).active,
      a.id,
      reason: 'not ${first.id}, the first tool',
    );
    expect(barName(t), 'A');
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

  testWidgets('after a failed edit the bar says no "On {host}" and the '
      'panel\'s browser button opens the URL that failed; a page loaded '
      'elsewhere (SSO) still says "On {host}" (R18, D9, D13, D23)', (t) async {
    await rig.pump(t);
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:5173', name: 'Board');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    engine.emit(UrlChanged(Uri.parse('http://localhost:5173/')));
    engine.emit(const LoadFinished());
    await t.pump();
    final registry = rig.container.read(toolRegistryProvider.notifier);
    void edit(String url) =>
        registry.update(registry.byId(tool.id)!.copyWith(url: url));
    // Another port of the same host, refused: no "On localhost" beside the
    // panel.
    edit('localhost:5174');
    await t.pump();
    engine.emit(const LoadFailed(BrowserLoadErrorKind.refused));
    await t.pump();
    expect(find.byKey(const Key('tool.error.refused')), findsOneWidget);
    expect(find.byKey(const Key('tool.bar.away')), findsNothing);
    expect(find.byKey(const Key('tool.bar.backToTool')), findsNothing);
    // A host that is not found: the panel's browser button opens it, not
    // the page left behind.
    edit('http://board.example.com/');
    await t.pump();
    engine.emit(const LoadFailed(BrowserLoadErrorKind.dns));
    await t.pump();
    expect(find.byKey(const Key('tool.bar.away')), findsNothing);
    await t.tap(find.byKey(const Key('tool.error.browser')));
    await t.pump();
    expect(rig.harness.urlOpener.webLinks, [
      Uri.parse('http://board.example.com/'),
    ]);
    // A page that loaded elsewhere (an SSO round trip) still says so.
    engine.emit(const LoadStarted());
    engine.emit(UrlChanged(Uri.parse('https://sso.example.com/login')));
    engine.emit(const LoadFinished());
    await t.pump();
    expect(find.text('On sso.example.com'), findsOneWidget);
    expect(find.byKey(const Key('tool.bar.backToTool')), findsOneWidget);
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

  testWidgets('switching tool-embed to off closes every live page; on again, '
      'a tool shown loads again (D20, D5, R15)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:1', name: 'A');
    final b = rig.add(kDefaultWorkspaceId, 'localhost:2', name: 'B');
    await t.pumpAndSettle();
    await openTool(t, a.id);
    await openTool(t, b.id);
    final before = {...rig.engines};
    expect(rig.container.read(toolPagesProvider), {a.id, b.id});
    Future<void> embed(String mode) async {
      rig.fs.write(testConfigPaths().shellx, 'tool-embed = $mode\n');
      await loadConfig(rig.container);
      await t.pumpAndSettle();
    }

    await embed('off');
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsNothing);
    expect(before.values.every((e) => e.disposed), isTrue);
    expect(rig.container.read(toolPagesProvider), isEmpty);
    expect(rig.made, 2, reason: 'none made while off');
    await embed('on');
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    expect(barName(t), 'B');
    expect(rig.made, 3);
    expect(rig.engines[b.id], isNot(same(before[b.id])));
    expect(rig.engines[b.id]!.loads, [Uri.parse('http://localhost:2/')]);
    await t.tap(
      find.descendant(
        of: find.byKey(Key('tool.chip.${a.id}')),
        matching: find.text('A'),
      ),
    );
    await t.pumpAndSettle();
    expect(rig.made, 4);
    expect(rig.engines[a.id]!.loads, [Uri.parse('http://localhost:1/')]);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
    // A drop reaches the pane while it shows.
    await drop(
      t,
      t.getCenter(find.byKey(const ValueKey('tool.panesSlot'))),
      '/a',
    );
    expect(writes.join(), '/a ');
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await drop(t, t.getCenter(find.byKey(const Key('tool.loose'))), '/b');
    await t.pumpAndSettle();
    expect(writes.join(), '/a ');
    expect(rig.container.read(toolDockProvider).loose, ws);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a file dropped on a zoomed dock types nothing into the '
      'terminal under it; restored, the pane takes drops again (V2-3 D3)', (
    t,
  ) async {
    await rig.pump(t);
    final local =
        rig.container.read(localSessionsProvider) as FakeLocalSessions;
    final pane = rig.container.read(terminalTabsProvider).selected!;
    final writes = local.views[pane.focusedPaneId]!.writes;
    Offset panes() => t.getCenter(find.byKey(const ValueKey('tool.panesSlot')));
    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    // Beside the dock the pane takes a drop (the positive control).
    await drop(t, panes(), '/a');
    expect(writes.join(), '/a ');
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    final under = panes();
    expect(
      t.getRect(find.byKey(const ValueKey('tool.dockSlot'))).contains(under),
      isTrue,
      reason: 'on the zoomed dock, over the pane',
    );
    await drop(t, under, '/b');
    await t.pumpAndSettle();
    expect(writes.join(), '/a ');
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    await drop(t, panes(), '/c');
    expect(writes.join(), '/a /c ');
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('an image dropped over a zoomed dock or over the panel of a '
      'workspace shown without a tab attaches nothing to the AI composer '
      'under it (V2-3 D3, D4)', (t) async {
    await rig.pump(t, extra: FakeAiRuntimes(const FakeScenario()).overrides);
    openTestAiTab(rig.container, cwd: testAiCwd);
    await t.pumpAndSettle();
    final composer = find.byKey(const Key('ai.composer'));
    expect(composer, findsOneWidget);
    final ui = AiPaneScope.of(t.element(composer)).ui;
    ui.readImageFile = (_) async => _png;
    Future<void> dropImage(String path) async {
      await drop(t, t.getCenter(composer), path);
      for (var i = 0; i < 3; i++) {
        await t.pump();
      }
    }

    final tool = rig.add(kDefaultWorkspaceId, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    // Beside the dock the composer takes an image (the positive control).
    await dropImage('/shots/a.png');
    expect(ui.images.items, hasLength(1));
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    await dropImage('/shots/b.png');
    expect(ui.images.items, hasLength(1), reason: 'under the zoomed dock');
    await t.tap(find.byKey(const Key('tool.bar.expand')));
    await t.pumpAndSettle();
    final ws = rig.container
        .read(sidebarWorkspacesProvider.notifier)
        .createFor(name: 'B');
    final other = rig.add(ws, 'localhost:2');
    await t.pumpAndSettle();
    await openTool(t, other.id);
    expect(rig.container.read(toolDockProvider).loose, ws);
    await dropImage('/shots/c.png');
    expect(ui.images.items, hasLength(1), reason: 'under the loose panel');
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('closing the last tab of the shown workspace keeps its open '
      'dock on screen beside an empty area — the same page, no reload; with '
      'its dock closed the next tab shows, as before (§8, D4)', (t) async {
    await rig.pump(t);
    final first = rig.container.read(terminalTabsProvider).selectedId!;
    final side = rig.container.read(sidebarWorkspacesProvider.notifier);
    final tabs = rig.container.read(terminalTabsProvider.notifier);
    final ws = side.createFor(name: 'B');
    await side.openTabIn(ws);
    await t.pumpAndSettle();
    final b = rig.container.read(terminalTabsProvider).selectedId!;
    expect(rig.container.read(sidebarWorkspacesProvider).workspaceOf(b), ws);
    final tool = rig.add(ws, 'localhost:1');
    await t.pumpAndSettle();
    await openTool(t, tool.id);
    final engine = rig.engines[tool.id]!;
    expect(engine.loads, hasLength(1));
    tabs.close(b);
    await t.pumpAndSettle();
    expect(
      rig.container.read(terminalTabsProvider).selectedId,
      first,
      reason: "A2's successor, selected underneath",
    );
    expect(rig.container.read(toolDockProvider).loose, ws);
    expect(
      find.descendant(
        of: find.byKey(const Key('tool.loose')),
        matching: find.text('Open new tab'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('tool.dock.$ws')), findsOneWidget);
    expect(rig.made, 1);
    expect(engine.disposed, isFalse);
    expect(engine.builds, 1, reason: 'the same view');
    expect(engine.loads, hasLength(1));
    expect(engine.calls, isNot(contains('reload')));
    // A tab in B again, then its dock closed: A2's behaviour stays.
    await side.openTabIn(ws);
    await t.pumpAndSettle();
    final again = rig.container.read(terminalTabsProvider).selectedId!;
    expect(rig.container.read(toolDockProvider).loose, isNull);
    rig.container.read(toolDockProvider.notifier).close(ws);
    await t.pumpAndSettle();
    tabs.close(again);
    await t.pumpAndSettle();
    expect(rig.container.read(terminalTabsProvider).selectedId, first);
    expect(rig.container.read(toolDockProvider).loose, isNull);
    expect(find.byKey(const Key('tool.loose')), findsNothing);
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
