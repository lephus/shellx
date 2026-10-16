import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/inline_name_field.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_workspace.dart';

Future<void> rowMenu(WidgetTester t, int tabId) async {
  await t.tapAt(
    t.getCenter(find.byKey(ValueKey('tab.$tabId'))),
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('the row menu pins a tab: the pin icon shows, the tab leads', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    final ids = c.read(terminalTabsProvider).tabs.map((x) => x.id).toList();
    expect(find.byKey(Key('tab.pin.${ids.last}')), findsNothing);

    await rowMenu(t, ids.last);
    await t.tap(find.byKey(const Key('menu.pinTab')));
    await t.pumpAndSettle();

    expect(find.byKey(Key('tab.pin.${ids.last}')), findsOneWidget);
    expect(c.read(sidebarWorkspacesProvider).tabsOf(kDefaultWorkspaceId), [
      ids.last,
      ids.first,
    ]);
    await rowMenu(t, ids.last);
    expect(find.text('Unpin tab'), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.pinTab')));
    await t.pumpAndSettle();
    expect(find.byKey(Key('tab.pin.${ids.last}')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Set description opens the field; Enter shows the line', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final id = c.read(terminalTabsProvider).selected!.id;
    await rowMenu(t, id);
    await t.tap(find.byKey(const Key('menu.setDescription')));
    await t.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is InlineNameField && w.label == 'Tab description',
      ),
      findsOneWidget,
      reason: 'the field is labelled',
    );
    await t.enterText(
      find.byKey(const Key('row.renameField')),
      'waiting for CI',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();

    expect(find.byKey(Key('tab.desc.$id')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(Key('tab.desc.$id'))).data,
      'waiting for CI',
    );
    expect(
      c.read(terminalTabsProvider).selected!.meta.description,
      'waiting for CI',
    );
    expect(c.read(sidebarWorkspacesProvider).renaming, isNull);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Esc leaves the description as it was', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final id = c.read(terminalTabsProvider).selected!.id;
    c
        .read(terminalTabsProvider.notifier)
        .setMeta(id, (m) => m.copyWith(description: 'keep'));
    await t.pumpAndSettle();
    await rowMenu(t, id);
    await t.tap(find.byKey(const Key('menu.setDescription')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('row.renameField')), 'changed');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).selected!.meta.description, 'keep');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the status menu sets a dot whose label is the status text', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final id = c.read(terminalTabsProvider).selected!.id;
    expect(find.byKey(Key('tab.status.$id')), findsNothing);
    await rowMenu(t, id);
    await t.tap(find.byKey(const Key('menu.status')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu.status.blocked')));
    await t.pumpAndSettle();

    expect(find.byKey(Key('tab.status.$id')), findsOneWidget);
    final label = t
        .widgetList<Semantics>(
          find.ancestor(
            of: find.byKey(Key('tab.status.$id')),
            matching: find.byType(Semantics),
          ),
        )
        .map((s) => s.properties.label)
        .whereType<String>();
    expect(label, contains('Status: Blocked'));
    expect(
      c.read(terminalTabsProvider).selected!.meta.status,
      TabStatus.blocked,
    );
    // The current one is checked when the menu opens again.
    await rowMenu(t, id);
    await t.tap(find.byKey(const Key('menu.status')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('menu.status.blocked')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await disposeWorkspace(t, c);
  }, variant: mac);

  group('closing a pinned tab asks (D18)', () {
    testWidgets('Cmd+W on a pinned tab shows the confirm', (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTabFor(select: true);
      await t.pumpAndSettle();
      final id = c.read(terminalTabsProvider).selected!.id;
      tabs.setMeta(id, (m) => m.copyWith(pinned: true));
      await t.pumpAndSettle();

      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyW);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pump();
      await t.pump();

      final request = c.read(windowRouterProvider).confirm;
      expect(request, isNotNull);
      expect(request!.title, 'Close pinned tab?');
      request.complete(false);
      await t.pumpAndSettle();
      expect(c.read(terminalTabsProvider).tabs.any((x) => x.id == id), isTrue);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('confirm-close-surface = false closes it without asking', (
      t,
    ) async {
      final rig = await pumpConfiguredWorkspace(
        t,
        config: 'confirm-close-surface = false\n',
      );
      final c = rig.container;
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTabFor(select: true);
      await t.pumpAndSettle();
      final id = c.read(terminalTabsProvider).selected!.id;
      tabs.setMeta(id, (m) => m.copyWith(pinned: true));
      await t.pumpAndSettle();

      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyW);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();

      expect(c.read(windowRouterProvider).confirm, isNull);
      expect(c.read(terminalTabsProvider).tabs.any((x) => x.id == id), isFalse);
      await disposeWorkspace(t, c);
    }, variant: mac);
  });

  testWidgets('the toggle_pin_tab palette entry pins the selected tab', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    await t.pump();
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('a9.palette')),
        matching: find.byType(TextField),
      ),
      'Pin or unpin tab',
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).selected!.meta.pinned, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
