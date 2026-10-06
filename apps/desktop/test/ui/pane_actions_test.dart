import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

TerminalTab only() => tabs().tabs.single;

Future<void> chord(
  WidgetTester t,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final m in modifiers) {
    await t.sendKeyDownEvent(m);
  }
  await t.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await t.sendKeyUpEvent(m);
  }
  await t.pump();
  await t.pump();
}

const meta = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;
const alt = LogicalKeyboardKey.altLeft;
const control = LogicalKeyboardKey.controlLeft;

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('⌘D splits right and announces; ⌘⌥← focuses back; ⌘W closes '
      'the focused pane, not the tab', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta], LogicalKeyboardKey.keyD);
    expect(only().paneOrder, [1, 100]);
    expect(
      t.takeAnnouncements().map((a) => a.message),
      contains('Split, pane 2 of 2'),
    );
    await chord(t, [meta, alt], LogicalKeyboardKey.arrowLeft);
    expect(only().focusedPaneId, 1);
    await chord(t, [meta], LogicalKeyboardKey.keyW);
    expect(only().paneOrder, [100]);
    expect(tabs().tabs, hasLength(1));
    expect(
      t.takeAnnouncements().map((a) => a.message),
      contains('Pane closed, 1 left'),
    );
  });

  testSidebar('⌘⇧D splits down; ⌘⇧↩ zooms; ⌘⌃= equalizes', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta, shift], LogicalKeyboardKey.keyD);
    expect((only().layout as PaneSplit).axis, SplitAxis.column);
    await chord(t, [meta, shift], LogicalKeyboardKey.enter);
    expect(only().zoomedPaneId, 100);
    await chord(t, [meta, shift], LogicalKeyboardKey.enter);
    expect(only().zoomedPaneId, isNull);
    await chord(t, [meta, control], LogicalKeyboardKey.arrowDown);
    expect((only().layout as PaneSplit).ratio, closeTo(0.55, 1e-9));
    await chord(t, [meta, control], LogicalKeyboardKey.equal);
    expect((only().layout as PaneSplit).ratio, 0.5);
  });

  testSidebar('⌘W on a pane running a command asks with the pane wording '
      '(D28)', (t) async {
    await pumpSidebar(t);
    await chord(t, [meta], LogicalKeyboardKey.keyD);
    local.replace(
      local.summary(100, origin: SessionOrigin.desktop, runningCommand: true),
    );
    await t.pump();
    await chord(t, [meta], LogicalKeyboardKey.keyW);
    // The harness has no dialog host: the request is what the dialog shows.
    final confirm = container.read(windowRouterProvider).confirm!;
    expect(confirm.body, 'The command running in this pane will be stopped.');
    confirm.complete(false);
    await t.pump();
    expect(only().paneOrder, [1, 100]);
  });

  testSidebar('terminal menu: split entries always, pane entries with two '
      'panes; Close pane closes the pane under the pointer (D21)', (t) async {
    await pumpSidebar(t);
    final area = t.getRect(find.byKey(const ValueKey('terminal.1')));
    await t.tapAt(area.center, buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.splitRight')), findsOneWidget);
    expect(find.byKey(const Key('menu.closePane')), findsNothing);
    await t.tap(find.byKey(const Key('menu.splitRight')));
    await t.pumpAndSettle();
    expect(only().paneOrder, [1, 100]);
    final left = t.getRect(find.byKey(const Key('pane.header.1')));
    await t.tapAt(
      left.bottomCenter + const Offset(0, 40),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    expect(only().focusedPaneId, 1);
    expect(find.byKey(const Key('menu.zoomPane')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.closePane')));
    await t.pumpAndSettle();
    expect(only().paneOrder, [100]);
  });

  testSidebar('row: pane count, label, row menu split, close hint only for '
      'one pane (D6, D19, D21)', (t) async {
    final semantics = t.ensureSemantics();
    await pumpSidebar(t);
    expect(find.byKey(const Key('row.paneCount.1')), findsNothing);
    await t.tap(row(1), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu.row.splitDown')));
    await t.pumpAndSettle();
    expect((only().layout as PaneSplit).axis, SplitAxis.column);
    expect(
      find.descendant(
        of: find.byKey(const Key('row.paneCount.1')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^zsh 2, 2 panes, ')), findsOneWidget);
    await t.tap(row(1), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.row.equalize')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('menu.closeTab')),
        matching: find.text('⌘W'),
      ),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets(
    'Windows: AltGr never fires split down; left Alt does (D20)',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (t) async {
      try {
        await pumpSidebar(t);
        await chord(t, [
          control,
          shift,
          LogicalKeyboardKey.altRight,
        ], LogicalKeyboardKey.keyD);
        expect(only().paneOrder, [1]);
        await chord(t, [control, shift, alt], LogicalKeyboardKey.keyD);
        expect((only().layout as PaneSplit).axis, SplitAxis.column);
        await chord(t, [
          control,
          LogicalKeyboardKey.altRight,
        ], LogicalKeyboardKey.arrowUp);
        expect(only().focusedPaneId, 100); // unchanged
        await chord(t, [control, alt], LogicalKeyboardKey.arrowUp);
        expect(only().focusedPaneId, 1);
      } finally {
        await t.pumpWidget(const SizedBox());
        container.dispose();
      }
    },
  );
}
