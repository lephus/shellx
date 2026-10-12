import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../support/config_workspace.dart';

const _cmd = LogicalKeyboardKey.metaLeft;

Future<void> openProjects(WidgetTester t) async {
  await t.sendKeyDownEvent(_cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(_cmd);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.projects')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the sidebar gear button opens Settings without a shortcut', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    expect(find.byType(SettingsOverlay), findsNothing);
    await t.tap(find.byKey(const Key('sidebar.settings')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsOneWidget);
    await disposeWorkspace(t, w.container);
  });

  testWidgets('the Projects page lists the Default project and its intro', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    await openProjects(t);
    expect(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.name')),
      findsOneWidget,
    );
    // Default cannot be deleted: no delete button on it.
    expect(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.delete')),
      findsNothing,
    );
    expect(find.text('New project'), findsWidgets);
    await disposeWorkspace(t, w.container);
  });

  testWidgets('New project adds a group; it can be deleted from here', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    await openProjects(t);
    expect(w.container.read(sidebarWorkspacesProvider).workspaces.length, 1);

    await t.tap(find.widgetWithText(OutlinedButton, 'New project'));
    await t.pumpAndSettle();
    final state = w.container.read(sidebarWorkspacesProvider);
    expect(state.workspaces.length, 2);
    final id = state.workspaces.last.id;
    expect(find.byKey(Key('settings.project.$id.name')), findsOneWidget);

    await t.tap(find.byKey(Key('settings.project.$id.delete')));
    await t.pumpAndSettle();
    expect(w.container.read(sidebarWorkspacesProvider).workspaces.length, 1);
    await disposeWorkspace(t, w.container);
  });

  testWidgets('typing a folder sets the project root and persists it', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    await openProjects(t);
    await t.enterText(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.root')),
      '/Users/me/app',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(
      w.container
          .read(sidebarWorkspacesProvider)
          .workspace(kDefaultWorkspaceId)!
          .root,
      '/Users/me/app',
    );
    await disposeWorkspace(t, w.container);
  });

  testWidgets('a folder edit still in a focused field is kept when the '
      'overlay is closed with Esc', (t) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    await openProjects(t);
    await t.enterText(
      find.byKey(const Key('settings.project.$kDefaultWorkspaceId.root')),
      '/Users/me/escaped',
    );
    // No Enter, no focus change: close the overlay while editing.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(
      w.container
          .read(sidebarWorkspacesProvider)
          .workspace(kDefaultWorkspaceId)!
          .root,
      '/Users/me/escaped',
    );
    await disposeWorkspace(t, w.container);
  });
}
