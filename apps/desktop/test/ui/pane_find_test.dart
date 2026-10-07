import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/find_sessions.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Future<void> pressMeta(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyEvent(key);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
}

void main() {
  testWidgets(
    '⌘F opens the bar in the focused pane, focused, grid unchanged',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      tab.terminal.write('alpha\r\nbeta error\r\ngamma error');
      final before = (tab.terminal.viewWidth, tab.terminal.viewHeight);
      final resizes = rig.local.views[tab.focusedPaneId]!.resizes.length;
      await pressMeta(t, LogicalKeyboardKey.keyF);
      await t.pump();
      expect(find.byKey(const Key('find.bar')), findsOneWidget);
      expect(
        c.read(findSessionsProvider)[tab.focusedPaneId]!.focusNode.hasFocus,
        isTrue,
      );
      expect((tab.terminal.viewWidth, tab.terminal.viewHeight), before);
      expect(rig.local.views[tab.focusedPaneId]!.resizes.length, resizes);
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'typing finds; ⌘G steps; Esc closes and the terminal has the keyboard',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      tab.terminal.write('one error\r\ntwo error\r\nthree error');
      await pressMeta(t, LogicalKeyboardKey.keyF);
      await t.enterText(find.byKey(const Key('find.field')), 'error');
      await t.pump();
      final session = c.read(findSessionsProvider)[tab.focusedPaneId]!;
      expect(session.matches, hasLength(3));
      expect(session.current, 2);
      await pressMeta(t, LogicalKeyboardKey.keyG);
      expect(session.current, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('find.bar')), findsNothing);
      expect(c.read(findSessionsProvider), isEmpty);
      expect(tab.selection.highlights, isEmpty);
      // The keyboard is back in the terminal (A10 D23 F2).
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'terminal');
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '⌘V in the bar pastes into the bar, not the terminal',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'needle'}
            : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pressMeta(t, LogicalKeyboardKey.keyF);
      await pressMeta(t, LogicalKeyboardKey.keyV);
      await t.pump();
      expect(rig.local.views[tab.focusedPaneId]!.writes, isEmpty);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('find.field')))
            .controller!
            .text,
        'needle',
      );
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'closing the pane closes its bar; no anchors stay',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      tab.terminal.write('x x x');
      await pressMeta(t, LogicalKeyboardKey.keyF);
      await t.enterText(find.byKey(const Key('find.field')), 'x');
      await t.pump();
      final terminal = tab.terminal;
      expect(terminal.buffer.lines[0].anchors, isNotEmpty);
      c.read(terminalTabsProvider.notifier).close(tab.id);
      await t.pump();
      expect(c.read(findSessionsProvider), isEmpty);
      expect(terminal.buffer.lines[0].anchors, isEmpty);
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'the menu has Find… with its shortcut',
    (t) async {
      final rig = await pumpConfiguredWorkspace(t);
      final c = rig.container;
      final tab = c.read(terminalTabsProvider).selected!;
      // Right click on the terminal.
      await t.tapAt(
        t.getCenter(find.byKey(ValueKey('terminal.${tab.id}'))),
        buttons: kSecondaryButton,
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('menu.find')), findsOneWidget);
      expect(find.text('Find…'), findsOneWidget);
      expect(find.text('⌘F'), findsOneWidget);
      await t.tapAt(const Offset(2, 2));
      await t.pumpAndSettle();
      await disposeWorkspace(t, c);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
