import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

Future<dynamic> emptyWorkspace(WidgetTester t, {String config = ''}) async {
  final w = await pumpConfiguredWorkspace(t, config: config);
  final tabs = w.container.read(terminalTabsProvider);
  for (final tab in [...tabs.tabs]) {
    w.container.read(terminalTabsProvider.notifier).close(tab.id);
  }
  await t.pump();
  await t.pump();
  expect(find.byKey(const Key('pane.empty')), findsOneWidget);
  return w;
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('the empty state shows three hints with the real chords', (
    t,
  ) async {
    final w = await emptyWorkspace(t);
    expect(find.text('⌘T New tab'), findsOneWidget);
    expect(find.text('⌘⇧P Command palette'), findsOneWidget);
    expect(find.text('⌘, Settings'), findsOneWidget);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the hints follow a reload; an unbound action loses its hint', (
    t,
  ) async {
    final w = await emptyWorkspace(t);
    w.fs.write(
      testConfigPaths().shellx,
      'keybind = super+k=new_tab\nkeybind = super+comma=unbind\n',
    );
    await w.container.read(shellxConfigProvider.notifier).load(manual: true);
    await t.pump();
    await t.pump();
    expect(find.text('⌘K New tab'), findsOneWidget);
    expect(find.text('⌘⇧P Command palette'), findsOneWidget);
    expect(find.textContaining('Settings'), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Vietnamese hints', (t) async {
    final w = await pumpConfiguredWorkspace(t, locale: const Locale('vi'));
    for (final tab in [...w.container.read(terminalTabsProvider).tabs]) {
      w.container.read(terminalTabsProvider.notifier).close(tab.id);
    }
    await t.pump();
    await t.pump();
    expect(find.text('⌘T Tab mới'), findsOneWidget);
    expect(find.text('⌘⇧P Bảng lệnh'), findsOneWidget);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the notifications panel with no entries says what to expect', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyI);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      find.text('A glowing ring appears on a pane when an agent needs you.'),
      findsOneWidget,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
