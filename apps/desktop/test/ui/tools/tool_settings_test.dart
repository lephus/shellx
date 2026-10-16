import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/browser/browser_engine.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_pages.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';
import 'package:shellx_desktop/src/ui/activation.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/config_workspace.dart';
import '../../support/tool_harness.dart';

Future<void> openProjects(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.projects')));
  await t.pumpAndSettle();
}

/// Taps "Clear tool data…"; its question is the test's to answer.
Future<ConfirmRequest> askToClear(WidgetTester t, ProviderContainer c) async {
  await t.ensureVisible(find.byKey(const Key('settings.tools.clear')));
  await t.pumpAndSettle();
  await t.tap(
    find.descendant(
      of: find.byKey(const Key('settings.tools.clear')),
      matching: find.byType(OutlinedButton),
    ),
  );
  await t.pumpAndSettle();
  return c.read(windowRouterProvider).confirm!;
}

/// A system-notification click on the open tab: the terminal gets the
/// keyboard, which closes Settings under whatever dialog or question is
/// open; those stay.
Future<void> clickNotification(WidgetTester t, ProviderContainer c) async {
  openTabFromNotification(c, c.read(terminalTabsProvider).selectedId!);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsNothing);
}

/// A data store whose clear fails the way a Windows folder delete can while
/// a just-closed page's WebView2 is still exiting: the exception's text
/// carries a path.
final class _FailingData implements BrowserDataStore {
  int clears = 0;

  @override
  Future<void> clearAll() async {
    clears++;
    throw const FileSystemException(
      'Deletion failed',
      r'C:\Users\someone\AppData\Local\ShellX\tools',
    );
  }
}

void main() {
  late ToolRig rig;
  setUp(() => rig = ToolRig());

  testWidgets('a project card lists its tools: the phone switch, edit, '
      'open, and "Add tool" (D22)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    final b = rig.add(kDefaultWorkspaceId, 'https://x.dev', name: 'Docs');
    await t.pumpAndSettle();
    await openProjects(t);
    expect(find.byKey(Key('settings.tool.${a.id}')), findsOneWidget);
    expect(
      t
          .widget<Switch>(find.byKey(Key('settings.tool.${b.id}.phone')))
          .onChanged,
      isNull,
      reason: 'D15: https is not for phones',
    );
    // D15: the switch that is off says why; the one that is on says what it
    // does.
    expect(
      find.ancestor(
        of: find.byKey(Key('settings.tool.${b.id}.phone')),
        matching: find.byTooltip(
          'Only http tools on this computer can open on a phone.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(Key('settings.tool.${a.id}.phone')),
        matching: find.byTooltip('Allow on phone'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(Key('settings.tool.${a.id}.phone')));
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolRegistryProvider.notifier).byId(a.id)!.phone,
      isTrue,
    );
    // D23: Edit changes the name in the same dialog; Settings stays.
    await t.tap(find.byKey(Key('settings.tool.${a.id}.edit')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tool.dialog.name')), 'Kanban');
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    expect(
      rig.container.read(toolRegistryProvider.notifier).byId(a.id)!.name,
      'Kanban',
    );
    expect(
      find.descendant(
        of: find.byKey(Key('settings.tool.${a.id}')),
        matching: find.text('Kanban'),
      ),
      findsOneWidget,
      reason: 'the card shows the new name',
    );
    expect(find.byType(SettingsOverlay), findsOneWidget, reason: 'stays');
    await t.tap(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.addTool')),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tool.dialog.url')), 'localhost:9');
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    expect(rig.container.read(toolRegistryProvider), hasLength(3));
    expect(find.byType(SettingsOverlay), findsOneWidget, reason: 'stays');
    expect(
      find.byKey(const ValueKey('tool.dockSlot')),
      findsNothing,
      reason: 'R20: Settings adds without opening',
    );
    await t.tap(find.byKey(Key('settings.tool.${a.id}.open')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(find.byKey(const ValueKey('tool.dockSlot')), findsOneWidget);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('"Clear tool data…" asks, then clears the one store (D8, '
      'D22); the tool-embed row is there', (t) async {
    await rig.pump(t);
    await openProjects(t);
    final confirm = await askToClear(t, rig.container);
    expect(find.byKey(const ValueKey('row.tool-embed')), findsOneWidget);
    expect(
      confirm.title,
      'Sign every tool out and clear its cookies and storage?',
    );
    expect(rig.data.clears, 0, reason: 'D8: it asks first');
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(rig.data.clears, 1);
    // A "No" clears nothing.
    (await askToClear(t, rig.container)).complete(false);
    await t.pumpAndSettle();
    expect(rig.data.clears, 1);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a clear that fails throws nothing and logs only the error '
      'type, never its path (D24)', (t) async {
    // No tool, so no page: the rig is not needed, and it already overrides
    // the store (a second override of one provider is an assertion error).
    final store = _FailingData();
    final r = await pumpConfiguredWorkspace(
      t,
      extra: [toolDataStoreProvider.overrideWithValue(store)],
    );
    await openProjects(t);
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
    try {
      (await askToClear(t, r.container)).complete(true);
      await t.pumpAndSettle();
    } finally {
      debugPrint = old;
    }
    expect(store.clears, 1, reason: 'the clear was tried, and it failed');
    // An exception that got out would fail the test by itself.
    expect(lines, ['tool data not cleared (FileSystemException)']);
    await disposeWorkspace(t, r.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('"Clear" still clears when a notification click closed Settings '
      'under the question (D8, D22)', (t) async {
    await rig.pump(t);
    await openProjects(t);
    final confirm = await askToClear(t, rig.container);
    await clickNotification(t, rig.container);
    expect(
      rig.container.read(windowRouterProvider).confirm,
      same(confirm),
      reason: 'the question stays',
    );
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(rig.data.clears, 1);
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Edit, Add and Delete from Settings still finish when a '
      'notification click closed Settings under them (D22, D23)', (t) async {
    await rig.pump(t);
    final a = rig.add(kDefaultWorkspaceId, 'localhost:4000', name: 'Board');
    final b = rig.add(kDefaultWorkspaceId, 'localhost:5000', name: 'Docs');
    await t.pumpAndSettle();
    final tools = rig.container.read(toolRegistryProvider.notifier);

    // Edit: the dialog stays, and Save still renames.
    await openProjects(t);
    await t.tap(find.byKey(Key('settings.tool.${a.id}.edit')));
    await t.pumpAndSettle();
    await clickNotification(t, rig.container);
    expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
    await t.enterText(find.byKey(const Key('tool.dialog.name')), 'Kanban');
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    expect(tools.byId(a.id)!.name, 'Kanban');

    // Add: Save still adds the tool.
    await openProjects(t);
    await t.tap(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.addTool')),
    );
    await t.pumpAndSettle();
    await clickNotification(t, rig.container);
    expect(find.byKey(const Key('tool.dialog')), findsOneWidget);
    await t.enterText(find.byKey(const Key('tool.dialog.url')), 'localhost:9');
    await t.tap(find.byKey(const Key('tool.dialog.save')));
    await t.pumpAndSettle();
    expect(rig.container.read(toolRegistryProvider), hasLength(3));

    // Delete: the question stays, and "Yes" still deletes.
    await openProjects(t);
    await t.tap(find.byKey(Key('settings.tool.${b.id}.delete')));
    await t.pumpAndSettle();
    final confirm = rig.container.read(windowRouterProvider).confirm!;
    await clickNotification(t, rig.container);
    confirm.complete(true);
    await t.pumpAndSettle();
    expect(tools.byId(b.id), isNull);
    expect(rig.container.read(toolRegistryProvider), hasLength(2));
    await disposeWorkspace(t, rig.container);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
