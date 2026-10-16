import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:xterm/xterm.dart';

import '../support/config_workspace.dart';

/// A10 D23: the focus invariants F1–F7. Each is one test; a red one is a
/// bug to fix, not a test to loosen.
String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> chord(
  WidgetTester t,
  List<LogicalKeyboardKey> held,
  LogicalKeyboardKey key,
) async {
  for (final k in held) {
    await t.sendKeyDownEvent(k);
  }
  await t.sendKeyEvent(key);
  for (final k in held.reversed) {
    await t.sendKeyUpEvent(k);
  }
  await t.pump();
  await t.pump();
}

const cmd = LogicalKeyboardKey.metaLeft;
const shift = LogicalKeyboardKey.shiftLeft;

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('F1: only the selected tab\'s focused pane owns the focus node', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tabs = w.container.read(terminalTabsProvider.notifier);
    await tabs.openTab(); // tab 2, selected
    await t.pumpAndSettle();
    final views = t
        .widgetList<TerminalView>(
          find.byType(TerminalView, skipOffstage: false),
        )
        .toList();
    expect(views, hasLength(2));
    expect(views.where((v) => v.focusNode != null), hasLength(1));
    final selected = w.container.read(terminalTabsProvider).selected!;
    expect(
      views.singleWhere((v) => v.focusNode != null).terminal,
      same(selected.terminal),
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F1: a pane hidden by a zoom has no focus node either', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tabs = w.container.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pump();
    tabs.toggleZoom();
    await t.pump();
    final tab = w.container.read(terminalTabsProvider).selected!;
    final owner = t
        .widgetList<TerminalView>(find.byType(TerminalView))
        .where((v) => v.focusNode != null)
        .toList();
    expect(owner, hasLength(1));
    expect(owner.single.terminal, same(tab.terminal));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F2: the command palette closing gives the keyboard back', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd, shift], LogicalKeyboardKey.keyP);
    expect(focusLabel(), isNot('terminal'));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F2: the notifications panel closing gives the keyboard back', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd, shift], LogicalKeyboardKey.keyI);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F2: the find bar closing gives the keyboard back', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd], LogicalKeyboardKey.keyF);
    expect(focusLabel(), 'find');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F2: hovering a file over the pane does not move the keyboard', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd], LogicalKeyboardKey.keyF);
    expect(focusLabel(), 'find');
    final details = DropEventDetails(
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );
    final target = t.widgetList<DropTarget>(find.byType(DropTarget)).first;
    target.onDragEntered!(details);
    await t.pump();
    expect(focusLabel(), 'find');
    target.onDragExited!(details);
    await t.pump();
    expect(focusLabel(), 'find');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets(
    'F2: a drop (D16: focuses that pane) leaves the keyboard in the terminal',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      expect(focusLabel(), 'terminal');
      t.widgetList<DropTarget>(find.byType(DropTarget)).first.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile('/tmp/a')],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await t.pump();
      await t.pump();
      expect(focusLabel(), 'terminal');
      await disposeWorkspace(t, w.container);
    },
    variant: mac,
  );

  testWidgets('F3: the window coming back puts the keyboard in the terminal', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    w.container.read(windowFocusProvider.notifier).set(true);
    await t.pump();
    // Whatever held it went away while the window was in the background.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    expect(focusLabel(), isNot('terminal'));
    w.container.read(windowFocusProvider.notifier).set(false);
    w.container.read(windowFocusProvider.notifier).set(true);
    await t.pump();
    await t.pump();
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F3: coming back leaves a field the user is typing in alone', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd], LogicalKeyboardKey.keyF);
    expect(focusLabel(), 'find');
    w.container.read(windowFocusProvider.notifier).set(false);
    w.container.read(windowFocusProvider.notifier).set(true);
    await t.pump();
    await t.pump();
    expect(focusLabel(), 'find');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  /// A10 review: the window coming back never takes the keyboard from an
  /// overlay the user is in.
  Future<void> reactivation(
    WidgetTester t,
    ProviderContainer container,
    String why,
  ) async {
    final before = focusLabel();
    expect(before, isNot('terminal'), reason: why);
    container.read(windowFocusProvider.notifier).set(false);
    // The overlay's own focus went away while the window was inactive.
    FocusManager.instance.primaryFocus?.unfocus();
    container.read(windowFocusProvider.notifier).set(true);
    await t.pump();
    await t.pump();
    expect(focusLabel(), isNot('terminal'), reason: why);
  }

  testWidgets('F3: coming back leaves the command palette alone', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd, shift], LogicalKeyboardKey.keyP);
    await reactivation(t, w.container, 'palette');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F3: coming back leaves the notifications panel alone', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    await chord(t, [cmd, shift], LogicalKeyboardKey.keyI);
    await reactivation(t, w.container, 'panel');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  for (final kind in [
    ConfigUiRequest.shortcuts,
    ConfigUiRequest.problems,
    ConfigUiRequest.settings,
  ]) {
    testWidgets('F3: coming back leaves the ${kind.name} sheet alone', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      w.container.read(configUiRequestProvider.notifier).request(kind);
      await t.pumpAndSettle();
      await reactivation(t, w.container, kind.name);
      await disposeWorkspace(t, w.container);
    }, variant: mac);
  }

  testWidgets('F4: a click on the other pane focuses it first time', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tabs = w.container.read(terminalTabsProvider.notifier);
    await tabs.split(SplitAxis.row);
    await t.pump();
    final tab = w.container.read(terminalTabsProvider).selected!;
    final other = tab.paneOrder.firstWhere((id) => id != tab.focusedPaneId);
    final view = t
        .widgetList<TerminalView>(find.byType(TerminalView))
        .firstWhere((v) => identical(v.terminal, tab.panes[other]!.terminal));
    await t.tapAt(
      t.getCenter(find.byWidget(view)),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump(const Duration(milliseconds: 400)); // xterm's double-tap timer
    expect(
      w.container.read(terminalTabsProvider).selected!.focusedPaneId,
      other,
    );
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F5: a click on a sidebar row puts the keyboard in that tab', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    final tabs = w.container.read(terminalTabsProvider.notifier);
    await tabs.openTab();
    await t.pumpAndSettle();
    final first = w.container.read(terminalTabsProvider).tabs.first;
    await t.tap(find.byKey(ValueKey('tab.${first.id}')));
    await t.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).selectedId, first.id);
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('F7: the first terminal has the keyboard without a keystroke', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(t);
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('N1: a background tab\'s title follows its session; an unread '
      'notice names the pane that sent it, not the one in front', (t) async {
    final w = await pumpConfiguredWorkspace(t);
    final tabs = w.container.read(terminalTabsProvider.notifier);
    w.container.read(tabAttentionProvider);
    final first = w.container.read(terminalTabsProvider).selected!;
    await tabs.openTab();
    await t.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).selectedId, isNot(first.id));
    w.local.replace(
      w.local.summary(first.focusedPaneId, title: 'vim notes.md'),
    );
    w.local.notice(
      first.focusedPaneId,
      SessionNoticeKind.message,
      body: 'done',
    );
    await t.pump();
    await t.pump();
    final tab = w.container
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == first.id);
    expect(tab.panes[first.focusedPaneId]!.title, 'vim notes.md');
    expect(w.container.read(tabAttentionProvider).unreadPanes(first.id), {
      first.focusedPaneId,
    });
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
