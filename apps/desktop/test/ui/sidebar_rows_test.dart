import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'sidebar_test_harness.dart';

void main() {
  setUpSidebar();

  // The test font draws every glyph 1 em wide (11 px in `caption`), so
  // the 168 px line holds less than with a real font: branch and folder
  // go on one row, the ports on another.
  testSidebar('a row with context shows branch · ~/path · ports and is 46 '
      'high; a row without context stays 30 (UI-A2 §2.1)', (tester) async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '$testHome/work',
          gitBranch: 'main',
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop))
      ..add(
        local.summary(3, origin: SessionOrigin.desktop, ports: [5173, 3000]),
      );
    await pumpSidebar(tester);
    expect(tester.getSize(row(1)).height, ShellxSizes.rowWithContext);
    expect(tester.getSize(row(2)).height, ShellxSizes.row);
    expect(tester.getSize(row(3)).height, ShellxSizes.rowWithContext);
    Finder line(int id) => find.descendant(
      of: row(id),
      matching: find.byKey(const Key('row.contextLine')),
    );
    expect(
      find.descendant(of: line(1), matching: find.text('main')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line(1), matching: find.text(' · ')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line(1), matching: find.text('~/work')),
      findsOneWidget,
    );
    expect(line(2), findsNothing);
    // Two ports (122 px) exceed 60 % of 168: the smallest stays, +1.
    expect(find.byKey(const Key('port.3000')), findsOneWidget);
    expect(find.byKey(const Key('port.5173')), findsNothing);
    expect(
      find.descendant(of: line(3), matching: find.text('+1')),
      findsOneWidget,
    );
    expect(tester.getSize(find.byKey(const Key('port.3000'))).height, 24);
    // The line starts at the title's left edge (32 = 8 + 16 + 8).
    expect(
      tester.getTopLeft(line(1)).dx - tester.getTopLeft(row(1)).dx,
      ShellxSizes.contextInset,
    );
  });

  testSidebar('a large text scale grows the row (UI-A2 §1.3)', (tester) async {
    local.add(
      local.summary(1, origin: SessionOrigin.desktop, gitBranch: 'main'),
    );
    await pumpSidebar(tester, textScale: 2);
    expect(tester.getSize(row(1)).height, 18 * 2 + 14 * 2 + 14);
  });

  testSidebar('clicking a port opens http://localhost:PORT without '
      'selecting the tab; a failure shows a toast (UI-A2 §2.4)', (
    tester,
  ) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop, ports: [8080]));
    await pumpSidebar(tester);
    expect(tabs().selectedId, 1);
    await tester.tap(find.byKey(const Key('port.8080')));
    await tester.pumpAndSettle();
    expect(h.urlOpener.ports, [8080]);
    expect(tabs().selectedId, 1);
    h.urlOpener.fail = true;
    await tester.tap(find.byKey(const Key('port.8080')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the browser."), findsOneWidget);
  });

  testSidebar('double-click renames in place: Enter keeps, Esc cancels, '
      'blank restores the automatic title (C6)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'));
    await pumpSidebar(tester);
    await tester.tap(row(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row(1));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'api server');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'api server');
    expect(sidebar().renaming, isNull);

    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'nope');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'api server');

    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(field, '   ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'vim');
  });

  testSidebar('F2 in the list renames; ⌥↓ moves the selected tab down '
      '(UI-A2 §8)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    // Put the keyboard in the list (Ctrl+F6 from the terminal, UI-A1 §3.6).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2, 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row.renameField')), findsOneWidget);
  });

  testSidebar('row menu: rename, move up/down enabled by position, one '
      'entry per port, Move to → New workspace (UI-A2 §5)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop, ports: [3000]))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.renameTab')), findsOneWidget);
    expect(find.byKey(const Key('menu.automaticName')), findsNothing);
    expect(find.byKey(const Key('menu.port.3000')), findsOneWidget);
    final up = tester.widget<PopupMenuItem<Object>>(
      find.byKey(const Key('menu.moveUp')),
    );
    expect(up.enabled, isFalse);
    await tester.tap(find.byKey(const Key('menu.moveTo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.moveTo.new')));
    await tester.pumpAndSettle();
    final ws = sidebar().workspaces.last.id;
    expect(sidebar().tabsOf(ws), [1]);
    expect(sidebar().renaming, RenameWorkspace(ws));
  });

  testSidebar('the row label reads branch, folder and ports (UI-A2 §8)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        title: 'claude',
        cwd: '$testHome/work/shellx',
        gitBranch: 'main',
        ports: [3000, 5173],
      ),
    );
    await pumpSidebar(tester);
    expect(
      find.bySemanticsLabel(
        'claude, idle, branch main, folder ~/work/shellx, '
        'ports 3000, 5173, tab 1 of 1',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  TerminalWorkspacePageState page(WidgetTester tester) => tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

  Future<void> chord(
    WidgetTester tester,
    List<LogicalKeyboardKey> modifiers,
    LogicalKeyboardKey key,
  ) async {
    for (final m in modifiers) {
      await tester.sendKeyDownEvent(m);
    }
    await tester.sendKeyEvent(key);
    for (final m in modifiers.reversed) {
      await tester.sendKeyUpEvent(m);
    }
  }

  Future<void> focusList(WidgetTester tester) async {
    await chord(tester, [
      LogicalKeyboardKey.controlLeft,
    ], LogicalKeyboardKey.f6);
    await tester.pump();
    expect(page(tester).sidebarFocus.hasFocus, isTrue);
  }

  testSidebar('the name field opens selected and focused, labelled "Tab '
      'name"; after a double-click the keyboard goes back to the terminal, '
      'after F2 back to the list (UI-A2 §4)', (tester) async {
    final handle = tester.ensureSemantics();
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'));
    await pumpSidebar(tester);
    await tester.tap(row(1));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(row(1));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(
      editable.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Tab name'))),
      isSemantics(
        label: 'Tab name',
        value: 'vim',
        isTextField: true,
        isFocused: true,
      ),
    );
    expect(tester.getSize(field).height, ShellxSizes.renameField);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(page(tester).terminalFocus.hasFocus, isTrue);

    await focusList(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    // Keys typed into the field are the field's, not the list's.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(field, findsOneWidget);
    await tester.enterText(field, 'editor');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.label, 'editor');
    expect(page(tester).sidebarFocus.hasFocus, isTrue);
    handle.dispose();
  });

  testSidebar('clicking elsewhere commits the name and leaves the focus '
      'where it went (UI-A2 §4)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('row.renameField')), 'api');
    await tester.tap(row(2));
    await tester.pumpAndSettle();
    expect(tabs().tabs.first.label, 'api');
    expect(sidebar().renaming, isNull);
    expect(tabs().selectedId, 2);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testSidebar('⌘⇧N: the new workspace\'s name field takes the keyboard; '
      'Enter names it, Esc keeps "Workspace 2", and the terminal gets the '
      'keyboard back (D15, UI-A2 §4)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    final newWorkspace = [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ];
    await chord(tester, newWorkspace, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final ws = sidebar().workspaces.last.id;
    final field = find.descendant(
      of: find.byKey(ValueKey('ws.$ws')),
      matching: find.byKey(const Key('row.renameField')),
    );
    expect(field, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(field, 'Backend');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sidebar().workspace(ws)!.name, 'Backend');
    expect(sidebar().renaming, isNull);
    expect(field, findsNothing);
    expect(page(tester).terminalFocus.hasFocus, isTrue);

    await chord(tester, newWorkspace, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final ws3 = sidebar().workspaces.last.id;
    await tester.enterText(
      find.descendant(
        of: find.byKey(ValueKey('ws.$ws3')),
        matching: find.byKey(const Key('row.renameField')),
      ),
      'nope',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // "Workspace 2" is free again: the first one is "Backend" now.
    expect(sidebar().workspace(ws3)!.name, 'Workspace 2');
    expect(sidebar().renaming, isNull);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testSidebar('Use automatic name, port entries and dividers; moving by '
      'the menu (UI-A2 §5.1)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'))
      ..add(
        local.summary(2, origin: SessionOrigin.desktop, ports: [5173, 3000]),
      );
    await pumpSidebar(tester);
    container.read(terminalTabsProvider.notifier).rename(2, 'web');
    await tester.pump();
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.automaticName')), findsOneWidget);
    // rename | automatic ─ move to, up, down ─ ports ─ close
    expect(find.byType(PopupMenuDivider), findsNWidgets(3));
    expect(
      tester.getTopLeft(find.byKey(const Key('menu.port.3000'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('menu.port.5173'))).dy),
    );
    final down = tester.widget<PopupMenuItem<Object>>(
      find.byKey(const Key('menu.moveDown')),
    );
    expect(down.enabled, isFalse);
    await tester.tap(find.byKey(const Key('menu.moveUp')));
    await tester.pumpAndSettle();
    expect(sidebar().tabsOf(kDefaultWorkspaceId), [2, 1]);

    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.automaticName')));
    await tester.pumpAndSettle();
    expect(tabs().tabs.last.customTitle, isNull);

    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuDivider), findsNWidgets(2)); // no ports
    await tester.tap(find.byKey(const Key('menu.renameTab')));
    await tester.pumpAndSettle();
    expect(sidebar().renaming, const RenameTab(1));
  });

  testSidebar('Enter on the untouched automatic name keeps it automatic; '
      'two clicks far apart are no double-click (C6)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'));
    await pumpSidebar(tester);
    final left = tester.getTopLeft(row(1)) + const Offset(20, 15);
    await tester.tapAt(left);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(left + const Offset(kDoubleTapSlop + 20, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row.renameField')), findsNothing);

    await tester.tapAt(left);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(left + const Offset(4, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('row.renameField')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs().tabs.single.customTitle, isNull);
    expect(sidebar().renaming, isNull);
  });

  testSidebar('⌘W while another tab\'s name field is open commits the '
      'name first (UI-A2 §4)', (tester) async {
    local
      ..add(local.summary(1, origin: SessionOrigin.desktop))
      ..add(local.summary(2, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    expect(tabs().selectedId, 1);
    workspaces().startRename(const RenameTab(2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('row.renameField')), 'api');
    await chord(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(local.closed, [1]);
    expect(tabs().tabs.single.label, 'api');
    expect(sidebar().renaming, isNull);
    expect(find.byKey(const Key('row.renameField')), findsNothing);
  });

  testSidebar('a name field closed from outside (⌘⇧N) keeps what was '
      'typed', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('row.renameField')), 'api');
    await chord(tester, [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    expect(tabs().tabs.first.label, 'api');
    expect(sidebar().renaming, RenameWorkspace(sidebar().workspaces.last.id));
  });
}
