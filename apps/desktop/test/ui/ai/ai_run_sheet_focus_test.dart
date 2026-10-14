import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:xterm/xterm.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import 'ai_run_sheet_test.dart' show SheetPtys;

/// V2-1 D8: who has the keyboard around the run sheet — a sign-in or an
/// install is a terminal program, and it needs the keys.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A signed-out agent with one terminal sign-in; the sheet's PTYs.
  Future<(ProviderContainer, SheetPtys, TerminalTab)> pane(
    WidgetTester t,
  ) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
        ],
      ),
    );
    final ptys = SheetPtys();
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [...fakes.overrides, aiPtyFactoryProvider.overrideWithValue(ptys)],
    );
    final tab = openTestAiTab(w.container, cwd: testAiCwd);
    w.container.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (w.container, ptys, tab);
  }

  Finder signIn() => find.byKey(const ValueKey('ai.login.login'));

  /// The sheet's terminal keyboard focus.
  FocusNode sheetFocus(WidgetTester t) => t
      .widget<TerminalView>(
        find.descendant(
          of: find.byKey(const Key('ai.runSheet')),
          matching: find.byType(TerminalView),
        ),
      )
      .focusNode!;

  FocusNode composerFocus(WidgetTester t) =>
      t.widget<TextField>(find.byKey(const Key('ai.composer'))).focusNode!;

  testWidgets('a sign-in started with the keyboard hands the keyboard to the '
      'sheet: the next Enter is the terminal\'s, not the button\'s', (t) async {
    final (c, ptys, _) = await pane(t);
    // Tab to the "Log in" button and press Enter on it.
    final button = Focus.of(
      t.element(find.descendant(of: signIn(), matching: find.byType(Text))),
    );
    button.requestFocus();
    await t.pump();
    expect(button.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(1));
    expect(find.byKey(const Key('ai.runSheet')), findsOneWidget);
    expect(sheetFocus(t).hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(
      ptys.spawned,
      hasLength(1),
      reason: 'the second Enter must not press "Log in" again',
    );
    expect(ptys.spawned.single.pty.writtenText, contains('\r'));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a sign-in started with the mouse has the keyboard too, '
      'although the composer had it', (t) async {
    final (c, ptys, _) = await pane(t);
    expect(composerFocus(t).hasPrimaryFocus, isTrue);
    await t.tap(signIn());
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(1));
    expect(sheetFocus(t).hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('in a split tab the window asking for its keyboard leaves it '
      'with the sheet (the sign-in can be typed into)', (t) async {
    final (c, ptys, ai) = await pane(t);
    // A shell under the AI pane, then the AI pane focused again.
    await t.tap(find.byKey(const Key('ai.terminal')));
    await t.pumpAndSettle();
    c.read(terminalTabsProvider.notifier).focusPane(ai.ai!.id);
    await t.pumpAndSettle();
    await t.tap(signIn());
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(1));
    // The user clicks into the sheet's terminal.
    sheetFocus(t).requestFocus();
    await t.pump();
    expect(sheetFocus(t).hasPrimaryFocus, isTrue);
    // Anything that gives the window's terminal focus back to this pane (a
    // notification click, closing a panel, the window coming back).
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(sheetFocus(t).hasPrimaryFocus, isTrue);
    expect(composerFocus(t).hasPrimaryFocus, isFalse);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('when the sheet goes — the program ended, or Close — the '
      'keyboard is the composer\'s, not nobody\'s', (t) async {
    final (c, ptys, _) = await pane(t);
    // Ended: exit 0 closes the sheet.
    await t.tap(signIn());
    await t.pumpAndSettle();
    sheetFocus(t).requestFocus();
    await t.pump();
    ptys.spawned.single.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(composerFocus(t).hasPrimaryFocus, isTrue);
    // Closed by hand while the program still runs.
    await t.tap(signIn());
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(2));
    sheetFocus(t).requestFocus();
    await t.pump();
    await t.tap(find.byKey(const Key('ai.runSheet.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(ptys.spawned.last.pty.killed, isTrue);
    expect(composerFocus(t).hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('"Try again" pressed from the keyboard gives the keyboard back '
      'to the terminal (its button goes away)', (t) async {
    final (c, ptys, _) = await pane(t);
    await t.tap(signIn());
    await t.pumpAndSettle();
    ptys.spawned.single.pty.exit(1);
    await t.pumpAndSettle();
    final retry = Focus.of(
      t.element(
        find.descendant(
          of: find.byKey(const Key('ai.runSheet.retry')),
          matching: find.byType(Text),
        ),
      ),
    );
    retry.requestFocus();
    await t.pump();
    expect(retry.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(2));
    expect(find.byKey(const Key('ai.runSheet.retry')), findsNothing);
    expect(sheetFocus(t).hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a pane that is not the focused one does not take the '
      'keyboard when its sheet goes', (t) async {
    final (c, ptys, ai) = await pane(t);
    await t.tap(find.byKey(const Key('ai.terminal')));
    await t.pumpAndSettle();
    final tabs = c.read(terminalTabsProvider.notifier);
    tabs.focusPane(ai.ai!.id);
    await t.pumpAndSettle();
    await t.tap(signIn());
    await t.pumpAndSettle();
    // The user goes to the shell pane; the sign-in ends meanwhile.
    final shell = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id)
        .panes
        .keys
        .single;
    tabs.focusPane(shell);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    ptys.spawned.single.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(composerFocus(t).hasPrimaryFocus, isFalse);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
