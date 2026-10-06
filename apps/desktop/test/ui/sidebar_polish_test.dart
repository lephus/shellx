import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/ui/terminal/session_sidebar.dart';
import 'package:shellx_desktop/src/ui/terminal/session_tab_row.dart';
import 'package:shellx_desktop/src/ui/terminal/sidebar_drag.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_overlays.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/terminal/workspace_header.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'sidebar_test_harness.dart';

// The A2 final visual QA wave (V1–V12): what a user sees, pinned.

Finder header(String id) => find.byKey(ValueKey('ws.$id'));

/// Default [1, 2] and "Workspace 2" [100] (selected).
Future<String> twoWorkspaces(WidgetTester tester) async {
  local
    ..add(local.summary(1, origin: SessionOrigin.desktop))
    ..add(local.summary(2, origin: SessionOrigin.desktop));
  await pumpSidebar(tester);
  await workspaces().create();
  workspaces().endRename();
  tester
      .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
      .focusTerminal();
  await tester.pumpAndSettle();
  return sidebar().workspaces.last.id;
}

Finder inHeader(String id, Key key) =>
    find.descendant(of: header(id), matching: find.byKey(key));

bool addShown(WidgetTester tester, String ws) => tester
    .widget<Visibility>(
      find
          .ancestor(
            of: inHeader(ws, const Key('header.add')),
            matching: find.byType(Visibility),
          )
          .first,
    )
    .visible;

bool countShown(WidgetTester tester, String ws) => tester
    .widget<Visibility>(
      find
          .ancestor(
            of: inHeader(ws, const Key('header.count')),
            matching: find.byType(Visibility),
          )
          .first,
    )
    .visible;

void main() {
  setUpSidebar();

  group('dragGhostTopLeft (V1)', () {
    const bounds = Rect.fromLTWH(0, 40, 220, 400);
    const chip = Size(120, 30);

    test('12 right of and 10 below the pointer', () {
      expect(
        dragGhostTopLeft(
          const DragGhostPlacement(pointer: Offset(40, 100), bounds: bounds),
          chip,
        ),
        const Offset(52, 110),
      );
    });

    test('kept inside the list horizontally', () {
      expect(
        dragGhostTopLeft(
          const DragGhostPlacement(pointer: Offset(200, 100), bounds: bounds),
          chip,
        ).dx,
        220 - 6 - 120,
      );
      expect(
        dragGhostTopLeft(
          const DragGhostPlacement(pointer: Offset(-50, 100), bounds: bounds),
          chip,
        ).dx,
        6,
      );
    });

    test('moved below what it would cover, or above it at the list end', () {
      const line = Rect.fromLTWH(6, 120, 208, 2);
      final below = dragGhostTopLeft(
        const DragGhostPlacement(
          pointer: Offset(40, 100),
          bounds: bounds,
          avoid: line,
        ),
        chip,
      );
      expect(below.dy, 122 + 4);
      const low = Rect.fromLTWH(6, 420, 208, 2);
      final above = dragGhostTopLeft(
        const DragGhostPlacement(
          pointer: Offset(40, 405),
          bounds: bounds,
          avoid: low,
        ),
        chip,
      );
      expect(above.dy, 420 - 4 - 30);
    });
  });

  test('kept inside the list vertically too (polish 1)', () {
    const bounds = Rect.fromLTWH(0, 40, 220, 400);
    const chip = Size(120, 30);
    expect(
      dragGhostTopLeft(
        const DragGhostPlacement(pointer: Offset(40, 430), bounds: bounds),
        chip,
      ).dy,
      440 - 30,
    );
    expect(
      dragGhostTopLeft(
        const DragGhostPlacement(pointer: Offset(40, 0), bounds: bounds),
        chip,
      ).dy,
      40,
    );
  });

  testSidebar('the header menu opens beside the sidebar, not over the name '
      '(polish 7)', (tester) async {
    final ws = await twoWorkspaces(tester);
    await tester.tap(header(ws), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('menu.ws.newTab'))).dx,
      greaterThanOrEqualTo(ShellxSizes.sidebarWidth),
    );
  });

  testSidebar('the workspace name field keeps clear of the chevron '
      '(polish 4)', (tester) async {
    final ws = await twoWorkspaces(tester);
    workspaces().startRename(RenameWorkspace(ws));
    await tester.pumpAndSettle();
    final field = inHeader(ws, const Key('row.renameField'));
    final chevron = find.descendant(
      of: header(ws),
      matching: find.byIcon(Icons.chevron_right),
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(of: field, matching: find.byType(InputDecorator)),
          )
          .dx,
      greaterThanOrEqualTo(tester.getTopRight(chevron).dx),
    );
  });

  testSidebar('the pinned header leaves the scrollbar gutter free '
      '(polish 3)', (tester) async {
    for (var id = 1; id <= 12; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    await workspaces().create();
    workspaces().endRename();
    tester.view.physicalSize = const Size(640, 400);
    await tester.pumpAndSettle();
    tester
        .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage))
        .sidebarScroll
        .jumpTo(120);
    await tester.pump();
    final band = find.byKey(const Key('sidebar.stickyBand'));
    expect(
      tester.getTopRight(band).dx,
      ShellxSizes.sidebarWidth - ShellxSizes.listMarginH,
    );
  });

  testSidebar('the drag chip is compact, opaque, beside the pointer, and '
      'never over the drop line (V1)', (tester) async {
    final ws = await twoWorkspaces(tester);
    final from = tester.getCenter(row(1));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 8));
    await tester.pump();
    // The lower half of row 2: the line goes in the gap below it.
    final target = tester.getRect(row(2));
    final at = Offset(target.left + 20, target.bottom - 4);
    await g.moveTo(at);
    await tester.pump();
    await g.moveTo(at + const Offset(0, 1));
    await tester.pump();
    final ghost = find.byKey(const Key('drag.ghost'));
    expect(ghost, findsOneWidget);
    final rect = tester.getRect(ghost);
    expect(rect.height, ShellxSizes.row);
    expect(rect.width, lessThanOrEqualTo(ShellxSizes.dragGhostMaxWidth));
    expect(rect.left, at.dx + ShellxSizes.dragGhostOffsetX);
    final line = tester.getRect(find.byKey(const Key('drop.line')));
    expect(rect.overlaps(line), isFalse);
    expect(
      find.ancestor(of: ghost, matching: find.byType(Opacity)),
      findsNothing,
    );
    // Over a header: the chip keeps clear of the target.
    final h = tester.getRect(header(ws));
    await g.moveTo(h.center);
    await tester.pump();
    await g.moveTo(h.center + const Offset(0, 1));
    await tester.pump();
    expect(tester.getRect(ghost).overlaps(h), isFalse);
    await g.up();
    await tester.pumpAndSettle();
  });

  testSidebar('rows sit 8 px in under headers, not without them (V9)', (
    tester,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    final alone = tester.getTopLeft(row(1)).dx;
    expect(alone, ShellxSizes.listMarginH);
    await workspaces().create();
    workspaces().endRename();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(row(1)).dx,
      tester.getTopLeft(header(kDefaultWorkspaceId)).dx +
          ShellxSizes.workspaceRowIndent,
    );
  });

  testSidebar('an empty group: short hint, + always shown (V4)', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester);
    workspaces().moveTab(100, kDefaultWorkspaceId);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(ValueKey('empty.$ws')),
        matching: find.text('Empty — drag a tab here'),
      ),
      findsOneWidget,
    );
    expect(addShown(tester, ws), isTrue);
    expect(addShown(tester, kDefaultWorkspaceId), isFalse);
  });

  testSidebar('the count holds the + slot in the rows\' × column; hover '
      'swaps in the +; the tooltip opens beside the sidebar (V10, V11)', (
    tester,
  ) async {
    final ws = await twoWorkspaces(tester); // tab 100 selected: × shown
    final count = inHeader(ws, const Key('header.count'));
    final close = find.descendant(
      of: row(100),
      matching: find.byKey(const Key('row.close')),
    );
    expect(tester.getCenter(count).dx, tester.getCenter(close).dx);
    expect(countShown(tester, ws), isTrue);
    expect(addShown(tester, ws), isFalse);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(header(ws)));
    await tester.pump();
    expect((countShown(tester, ws), addShown(tester, ws)), (false, true));
    expect(
      tester.getCenter(inHeader(ws, const Key('header.add'))).dx,
      tester.getCenter(close).dx,
    );
    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: inHeader(ws, const Key('header.add')),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.positionDelegate, besideSidebar);
    await mouse.removePointer();
  });

  testWidgets('a collapsed group\'s mark moves inside the focus ring (V3)', (
    tester,
  ) async {
    Widget build({required bool focused}) => MaterialApp(
      theme: buildDesktopTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 208,
          child: WorkspaceHeader(
            name: 'Backend',
            count: 2,
            collapsed: true,
            containsSelected: true,
            focused: focused,
            renaming: false,
            dropTarget: false,
            deletable: true,
            onToggle: () {},
            onStartRename: () {},
            onRename: (_) {},
            onCancelRename: () {},
            onNewTab: () {},
            onMenu: (_) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    final mark = find.byKey(const Key('header.collapsedMark'));
    await tester.pumpWidget(build(focused: false));
    final left = tester.getTopLeft(find.byType(WorkspaceHeader)).dx;
    expect(tester.getTopLeft(mark).dx - left, 0);
    await tester.pumpWidget(build(focused: true));
    expect(
      tester.getTopLeft(mark).dx - left,
      ShellxSizes.focusRing + ShellxSizes.selectedBarGap,
    );
  });

  testSidebar('the name field is a full 22 px box and its text starts where '
      'the title did (V5)', (tester) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop, title: 'vim'));
    await pumpSidebar(tester);
    final title = tester.getTopLeft(
      find.descendant(of: row(1), matching: find.text('vim')),
    );
    workspaces().startRename(const RenameTab(1));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    expect(
      tester
          .getSize(
            find.descendant(of: field, matching: find.byType(InputDecorator)),
          )
          .height,
      ShellxSizes.renameField,
    );
    final text = tester.getTopLeft(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(text.dx, title.dx);
  });

  testSidebar('a right-clicked row and header stay marked while the menu is '
      'open; Move to names the tab (V6)', (tester) async {
    final ws = await twoWorkspaces(tester);
    bool rowMarked(int id) => tester
        .widget<SessionTabRow>(
          find.byType(SessionTabRow).at([1, 2, 100].indexOf(id)),
        )
        .menuOpen;
    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(rowMarked(1), isTrue);
    expect(rowMarked(2), isFalse);
    await tester.tap(find.byKey(const Key('menu.moveTo')));
    await tester.pumpAndSettle();
    expect(rowMarked(1), isTrue); // the submenu still acts on it
    expect(find.text('Move “zsh 1” to'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(rowMarked(1), isFalse);
    await tester.tap(header(ws), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WorkspaceHeader>(find.byType(WorkspaceHeader).last)
          .menuOpen,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<WorkspaceHeader>(find.byType(WorkspaceHeader).last)
          .menuOpen,
      isFalse,
    );
  });

  testSidebar('Default\'s greyed Delete says why; more than two ports go into '
      'a submenu (V12)', (tester) async {
    local.add(
      local.summary(
        1,
        origin: SessionOrigin.desktop,
        ports: [9229, 3000, 5173],
      ),
    );
    await pumpSidebar(tester);
    await workspaces().create();
    workspaces().endRename();
    await tester.pumpAndSettle();
    await tester.tap(header(kDefaultWorkspaceId), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    final tip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(const Key('menu.ws.delete')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tip.message, "The Default workspace can't be deleted");
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(row(1), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.port.3000')), findsNothing);
    await tester.tap(find.byKey(const Key('menu.ports')));
    await tester.pumpAndSettle();
    expect(find.text('Open http://localhost:3000'), findsOneWidget);
    expect(find.text('Open http://localhost:9229'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu.port.5173')));
    await tester.pumpAndSettle();
    expect(h.urlOpener.ports, [5173]);
  });

  testSidebar('the scrollbar thumb runs in the list\'s right gutter (V12)', (
    tester,
  ) async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    await pumpSidebar(tester);
    expect(
      tester
          .widget<ShellxScrollbar>(
            find
                .descendant(
                  of: find.byType(SessionSidebar),
                  matching: find.byType(ShellxScrollbar),
                )
                .first,
          )
          .crossAxisMargin,
      0,
    );
  });

  testSidebar('the branch has a glyph before it; a folder alone has none '
      '(V8)', (tester) async {
    local
      ..add(
        local.summary(
          1,
          origin: SessionOrigin.desktop,
          cwd: '$testHome/w',
          gitBranch: 'main',
        ),
      )
      ..add(local.summary(2, origin: SessionOrigin.desktop, cwd: '/var/log'));
    await pumpSidebar(tester);
    final glyph = find.descendant(
      of: row(1),
      matching: find.byKey(const Key('row.branchGlyph')),
    );
    expect(glyph, findsOneWidget);
    expect(
      tester.getTopRight(glyph).dx,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(of: row(1), matching: find.text('main')),
            )
            .dx,
      ),
    );
    expect(
      find.descendant(
        of: row(2),
        matching: find.byKey(const Key('row.branchGlyph')),
      ),
      findsNothing,
    );
  });

  testSidebar('scrolled, the current group\'s header stays pinned on top '
      'with a 1 px edge; at the top, none (V7)', (tester) async {
    for (var id = 1; id <= 12; id++) {
      local.add(local.summary(id, origin: SessionOrigin.desktop));
    }
    await pumpSidebar(tester);
    await workspaces().create(); // tab 100 in "Workspace 2"
    workspaces().endRename();
    tester.view.physicalSize = const Size(640, 400);
    await tester.pumpAndSettle();
    final sticky = find.byKey(ValueKey('sticky.ws.$kDefaultWorkspaceId'));
    final page = tester.state<TerminalWorkspacePageState>(
      find.byType(TerminalWorkspacePage),
    );
    page.sidebarScroll.jumpTo(0);
    await tester.pump();
    expect(sticky, findsNothing);
    expect(find.byKey(const Key('sidebar.scrollEdge')), findsNothing);
    page.sidebarScroll.jumpTo(120);
    await tester.pump();
    expect(sticky, findsOneWidget);
    expect(
      find.descendant(of: sticky, matching: find.text('Default')),
      findsOneWidget,
    );
    final listTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(tester.getTopLeft(sticky).dy, listTop);
    // A click on the pinned header collapses its group, as the real one.
    // On the chevron: the name waits for a possible double-click.
    await tester.tapAt(tester.getTopLeft(sticky) + const Offset(14, 14));
    await tester.pumpAndSettle();
    expect(sidebar().workspace(kDefaultWorkspaceId)!.collapsed, isTrue);
  });
}
