import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show Key, Offset;
import 'package:xterm/xterm.dart' show TerminalView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/find_sessions.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/copy_mode_controller.dart';

import '../support/config_workspace.dart';

Future<void> pressMetaShift(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(key);
  await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump();
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pump();
}

/// [name] key with its character, as a keyboard sends a typed letter.
Future<void> type(WidgetTester t, LogicalKeyboardKey k, String ch) async {
  await t.sendKeyDownEvent(k, character: ch);
  await t.sendKeyUpEvent(k);
  await t.pump();
}

List<String?> mockClipboard(WidgetTester t) {
  final copied = <String?>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⌘⇧M shows the chip; every key is swallowed; Esc gives the '
      'keyboard back', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    final writes = rig.local.views[tab.focusedPaneId]!.writes;
    writes.clear();
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(find.byKey(const Key('copymode.chip')), findsOneWidget);
    expect(c.read(copyModeProvider), hasLength(1));
    await type(t, LogicalKeyboardKey.keyJ, 'j');
    await type(t, LogicalKeyboardKey.keyX, 'x');
    await key(t, LogicalKeyboardKey.arrowUp);
    await key(t, LogicalKeyboardKey.enter);
    expect(writes, isEmpty, reason: 'nothing reaches the program');
    // Enter yanked (nothing selected, a blank cell): the mode is over.
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(find.byKey(const Key('copymode.chip')), findsOneWidget);
    await key(t, LogicalKeyboardKey.escape);
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(writes.join(), isNotEmpty, reason: 'the program has its keys back');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘⇧M again leaves the mode', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(c.read(copyModeProvider), isEmpty);
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('exits when the pane exits', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(find.byKey(const Key('copymode.chip')), findsOneWidget);
    rig.local.views[tab.focusedPaneId]!.end(0);
    await t.pump();
    await t.pump();
    expect(c.read(copyModeProvider), isEmpty);
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('exits when the tab changes', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await c.read(terminalTabsProvider.notifier).openTab();
    await t.pumpAndSettle();
    expect(c.read(copyModeProvider), isEmpty);
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('v l l y copies "hel", leaves the mode and tells the user', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final copied = mockClipboard(t);
    final tab = c.read(terminalTabsProvider).selected!;
    tab.terminal!.write('hello');
    final lines = tab.terminal!.buffer.lines;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.digit0);
    await key(t, LogicalKeyboardKey.keyV);
    await key(t, LogicalKeyboardKey.keyL);
    await key(t, LogicalKeyboardKey.keyL);
    expect(tab.selection!.selection, isNotNull, reason: 'drawn as selection');
    await key(t, LogicalKeyboardKey.keyY);
    expect(copied, ['hel']);
    expect(c.read(copyModeProvider), isEmpty);
    expect(c.read(terminalTabsProvider).notice, isA<CopyModeCopiedNotice>());
    // No highlight, no selection, no anchor is left on the pane.
    expect(tab.selection!.selection, isNull);
    expect(tab.selection!.highlights, isEmpty);
    expect(lines[0].anchors, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the physical key wins over the character', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    final writes = rig.local.views[tab.focusedPaneId]!.writes;
    tab.terminal!.write('abcdef');
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.digit0);
    writes.clear();
    // The L key of a Korean layout: the character is "ㅣ".
    await simulateKeyDownEvent(
      const LogicalKeyboardKey(0x3163),
      physicalKey: PhysicalKeyboardKey.keyL,
      character: 'ㅣ',
    );
    await simulateKeyUpEvent(
      const LogicalKeyboardKey(0x3163),
      physicalKey: PhysicalKeyboardKey.keyL,
    );
    await t.pump();
    expect(c.read(copyModeProvider).values.single.state.col, 1);
    expect(writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('/ leaves the mode and opens the find bar', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.slash);
    await t.pump();
    expect(c.read(copyModeProvider), isEmpty);
    expect(c.read(findSessionsProvider), contains(tab.focusedPaneId));
    expect(
      c.read(findSessionsProvider)[tab.focusedPaneId]!.focusNode.hasFocus,
      isTrue,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a window chord still works inside the mode (⌘⇧M, and not a '
      'paste)', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    final writes = rig.local.views[tab.focusedPaneId]!.writes;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': 'pasted'}
          : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    writes.clear();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    expect(writes, isEmpty, reason: 'a paste is not for the program now');
    expect(c.read(copyModeProvider), hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('never logs what the terminal shows', (t) async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final copied = mockClipboard(t);
    final tab = c.read(terminalTabsProvider).selected!;
    tab.terminal!.write('secret-token');
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.digit0);
    await key(t, LogicalKeyboardKey.keyV);
    await key(t, LogicalKeyboardKey.keyE);
    await key(t, LogicalKeyboardKey.keyY);
    debugPrint = original;
    expect(copied, ['secret']);
    expect(logs.join().contains('secret'), isFalse);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('^ and \$ go by the character first, the physical key second', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    tab.terminal!.write('  abcdef');
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.digit0);
    // A layout that makes "$" on another key: the character decides.
    await simulateKeyDownEvent(
      LogicalKeyboardKey.dollar,
      physicalKey: PhysicalKeyboardKey.keyJ,
      character: r'$',
    );
    await simulateKeyUpEvent(
      LogicalKeyboardKey.dollar,
      physicalKey: PhysicalKeyboardKey.keyJ,
    );
    await t.pump();
    expect(c.read(copyModeProvider).values.single.state.col, 7);
    await simulateKeyDownEvent(
      LogicalKeyboardKey.caret,
      physicalKey: PhysicalKeyboardKey.keyJ,
      character: '^',
    );
    await simulateKeyUpEvent(
      LogicalKeyboardKey.caret,
      physicalKey: PhysicalKeyboardKey.keyJ,
    );
    await t.pump();
    expect(c.read(copyModeProvider).values.single.state.col, 2);
    // US layout: Shift+4 is still "$".
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit4);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(c.read(copyModeProvider).values.single.state.col, 7);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a paste from the menu ends copy mode first, then pastes', (
    t,
  ) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'echo hi'} : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(c.read(copyModeProvider), hasLength(1));
    await t.tapAt(
      t.getCenter(find.byType(TerminalView)),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('menu.paste')));
    await t.pumpAndSettle();
    expect(c.read(copyModeProvider), isEmpty);
    expect(rig.local.views[tab.focusedPaneId]!.writes.join(), 'echo hi');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a click in the pane ends copy mode (the mouse selects, y has '
      'no stale range)', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    expect(c.read(copyModeProvider), hasLength(1));
    await t.tapAt(
      t.getCenter(find.byType(TerminalView).first),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(c.read(copyModeProvider), isEmpty);
    expect(find.byKey(const Key('copymode.chip')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a file drop ends copy mode first, then arrives', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tab = c.read(terminalTabsProvider).selected!;
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    t.widgetList<DropTarget>(find.byType(DropTarget)).first.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile('/tmp/a')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await t.pump();
    await t.pump();
    expect(c.read(copyModeProvider), isEmpty);
    expect(rig.local.views[tab.focusedPaneId]!.writes.join(), '/tmp/a ');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the cursor covers a whole emoji and yanks it', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final copied = mockClipboard(t);
    final tab = c.read(terminalTabsProvider).selected!;
    tab.terminal!.write('a😀b');
    await pressMetaShift(t, LogicalKeyboardKey.keyM);
    await key(t, LogicalKeyboardKey.digit0);
    await key(t, LogicalKeyboardKey.keyL);
    final h = tab.selection!.highlights.single;
    expect((h.p1.x, h.p2.x), (1, 3), reason: 'both cells of the emoji');
    await key(t, LogicalKeyboardKey.keyV);
    await key(t, LogicalKeyboardKey.keyY);
    expect(copied, ['😀']);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
