import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/l10n/app_localizations_vi.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/notifications_panel.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_overlays.dart'
    show ShellxScrollbar;
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

/// The fake's notices arrive asynchronously (a broadcast stream, as from
/// the agent): the first pump delivers them, the second draws the result.
Future<void> deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

Future<void> openPanel(WidgetTester tester) =>
    chord(tester, LogicalKeyboardKey.keyI);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

TerminalWorkspacePageState page(WidgetTester tester) => tester
    .state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

final panel = find.byKey(const Key('panel'));

TerminalTabs tabs1() => container.read(terminalTabsProvider.notifier);

List<String?> panelTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: panel, matching: find.byType(Text)))
    .map((t) => t.data)
    .toList();

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'zsh'));
    local.add(local.summary(2, title: 'api'));
    local.add(local.summary(3, title: 'web'));
  });

  testSidebar('⌘⇧I opens the panel with the newest first; Esc closes it '
      'and gives the keyboard back to the terminal', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'first');
    local.notice(3, SessionNoticeKind.message, body: 'second');
    await deliver(tester);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
    await openPanel(tester);
    expect(panel, findsOneWidget);
    expect(page(tester).panelOpen, isTrue);
    final texts = panelTexts(tester);
    expect(texts.indexOf('second'), lessThan(texts.indexOf('first')));
    expect(texts, contains('Next unread  ⌘⇧U'));
    await press(tester, LogicalKeyboardKey.escape);
    expect(panel, findsNothing);
    expect(page(tester).panelOpen, isFalse);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testSidebar('⌘⇧I again closes it; the sidebar keeps the keyboard it had', (
    tester,
  ) async {
    await pumpSidebar(tester);
    page(tester).sidebarFocus.requestFocus();
    await tester.pump();
    await openPanel(tester);
    expect(panel, findsOneWidget);
    expect(page(tester).sidebarFocus.hasFocus, isFalse);
    await openPanel(tester);
    expect(panel, findsNothing);
    expect(page(tester).sidebarFocus.hasFocus, isTrue);
  });

  testSidebar('geometry: x 6, under the header band + 4, 360 wide '
      '(UI-A4 §5.2)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    await openPanel(tester);
    final rect = tester.getRect(panel);
    expect(rect.left, 6);
    // The selected row's 3 px bar is covered, not peeking out (F-3).
    final bar = tester.getRect(find.byKey(const Key('row.selectedBar')));
    expect(rect.left, lessThanOrEqualTo(bar.left));
    expect(rect.top, 38 + 4); // macOS band
    expect(rect.width, 360);
    // border 1 + padding 4 + header 36 + line 1 + item 52 + footer 24
    // + padding 4 + border 1.
    expect(rect.height, 1 + 4 + 36 + 1 + 52 + 24 + 4 + 1);
    expect(tester.getSize(find.byKey(const Key('panel.item.0'))).height, 52);
    // Everything fits: no scrollbar gutter, items span the panel's inside.
    expect(tester.getSize(find.byKey(const Key('panel.item.0'))).width, 350);
  });

  testSidebar('↓ + Enter jumps to the tab, reads it and closes (N5)', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.message, body: 'b');
    await deliver(tester);
    await openPanel(tester); // cursor on the first unread: "b" (tab 3)
    await press(tester, LogicalKeyboardKey.arrowDown); // "a" (tab 2)
    await press(tester, LogicalKeyboardKey.enter);
    expect(tabs().selectedId, 2);
    expect(container.read(tabAttentionProvider).hasUnread(2), isFalse);
    expect(container.read(tabAttentionProvider).hasUnread(3), isTrue);
    expect(panel, findsNothing);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testSidebar('the cursor opens on the first unread, does not wrap, and '
      'Home / End go to the ends', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'old');
    local.notice(3, SessionNoticeKind.message, body: 'new');
    await deliver(tester);
    container.read(tabAttentionProvider.notifier).markRead(3);
    await tester.pump();
    await openPanel(tester); // history: new (read), old (unread)
    bool selected(int seq) =>
        tester
            .getSemantics(find.byKey(Key('panel.item.$seq')))
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;
    expect(selected(0), isTrue); // "old", seq 0
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(selected(0), isTrue);
    await press(tester, LogicalKeyboardKey.home);
    expect(selected(1), isTrue);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(selected(1), isTrue);
    await press(tester, LogicalKeyboardKey.end);
    expect(selected(0), isTrue);
  });

  testSidebar('a click on an item jumps to its tab', (tester) async {
    await pumpSidebar(tester);
    local.notice(3, SessionNoticeKind.message, body: 'click me');
    await deliver(tester);
    await openPanel(tester);
    await tester.tap(
      find.descendant(of: panel, matching: find.text('click me')),
    );
    await tester.pumpAndSettle();
    expect(tabs().selectedId, 3);
    expect(container.read(tabAttentionProvider).totalUnread, 0);
    expect(panel, findsNothing);
  });

  testSidebar('an entry from a split tab names the pane that sent it '
      '(final m-6)', (tester) async {
    await pumpSidebar(tester);
    await tabs1().split(SplitAxis.row); // 1 | 100, 100 focused ("zsh 4")
    await tester.pump();
    await tester.pump();
    expect(tabs().selected!.label, 'zsh 4');
    local.notice(1, SessionNoticeKind.message, body: 'from pane 1');
    await deliver(tester);
    await openPanel(tester);
    final texts = panelTexts(tester);
    expect(texts, contains('zsh'));
    expect(texts, isNot(contains('zsh 4')));
  });

  testSidebar('a closed tab entry says so and does not jump', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'gone');
    await deliver(tester);
    container.read(terminalTabsProvider.notifier).close(2);
    await tester.pump();
    await openPanel(tester);
    expect(find.textContaining('Tab closed'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    expect(panel, findsOneWidget);
    await tester.tap(find.text('gone'));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(tabs().selectedId, isNot(2));
  });

  testSidebar('A7 D23: a "Command line" entry shows its source, never "Tab '
      'closed"; Enter reads it and closes the panel; it alone enables '
      '"Mark all as read"', (tester) async {
    await pumpSidebar(tester);
    final selected = tabs().selectedId;
    container
        .read(tabAttentionProvider.notifier)
        .addCommandLine(title: 'cron', body: 'backup done');
    await tester.pump();
    await openPanel(tester);
    final texts = panelTexts(tester);
    expect(texts, contains('Command line'));
    expect(texts, contains('cron: backup done'));
    expect(find.textContaining('Tab closed'), findsNothing);
    final markAll = tester.widget<TextButton>(
      find.byKey(const Key('panel.markAll')),
    );
    expect(markAll.onPressed, isNotNull);
    await press(tester, LogicalKeyboardKey.enter);
    expect(panel, findsNothing);
    expect(tabs().selectedId, selected);
    expect(container.read(tabAttentionProvider).history.single.read, isTrue);
  });

  testSidebar('A7 D23: the "Command line" entry follows the language shown', (
    tester,
  ) async {
    await pumpSidebar(tester, locale: const Locale('vi'));
    container.read(tabAttentionProvider.notifier).addCommandLine(body: 'xong');
    await tester.pump();
    await openPanel(tester);
    expect(panelTexts(tester), contains('Dòng lệnh'));
  });

  testSidebar('empty state and disabled "Mark all as read"', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      find.text('A glowing ring appears on a pane when an agent needs you.'),
      findsOneWidget,
    );
    expect(find.textContaining('Next unread'), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('panel.markAll')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      0.38,
    );
  });

  testSidebar('"Mark all as read" reads every tab and stays open', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(3, SessionNoticeKind.bell);
    await deliver(tester);
    await openPanel(tester);
    await tester.tap(find.byKey(const Key('panel.markAll')));
    await tester.pumpAndSettle();
    expect(container.read(tabAttentionProvider).totalUnread, 0);
    expect(panel, findsOneWidget);
  });

  testSidebar('Tab moves between the list and "Mark all as read" and stays '
      'in the panel', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    await openPanel(tester);
    bool markAllFocused() => Focus.of(
      tester.element(
        find.descendant(
          of: find.byKey(const Key('panel.markAll')),
          matching: find.byType(Text),
        ),
      ),
    ).hasPrimaryFocus;
    expect(markAllFocused(), isFalse);
    await press(tester, LogicalKeyboardKey.tab);
    expect(markAllFocused(), isTrue);
    await press(tester, LogicalKeyboardKey.tab);
    expect(markAllFocused(), isFalse);
    expect(page(tester).terminalFocus.hasFocus, isFalse);
    expect(page(tester).sidebarFocus.hasFocus, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(markAllFocused(), isTrue);
    // Enter on the button marks all as read, the panel stays.
    await press(tester, LogicalKeyboardKey.enter);
    expect(container.read(tabAttentionProvider).totalUnread, 0);
    expect(panel, findsOneWidget);
  });

  testSidebar('a click outside closes it', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    await tester.tapAt(const Offset(900, 600));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    // The click only closed the panel: no tab change.
    expect(tabs().selectedId, 1);
  });

  testSidebar('⌘T while the panel is open closes it first', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tabs().tabs.length, 4);
  });

  testSidebar('the bell: hollow at 0; filled with a dot when unread; opens '
      'and closes the panel; "on" while open (UI-A4 §5.1)', (tester) async {
    await pumpSidebar(tester);
    final bell = find.byKey(const Key('sidebar.bell'));
    final dot = find.byKey(const Key('sidebar.bell.dot'));
    expect(
      find.descendant(
        of: bell,
        matching: find.byIcon(Icons.notifications_none),
      ),
      findsOneWidget,
    );
    expect(dot, findsNothing);
    // Bell, 4, then `+`, between the 24 px visuals (UI-A4 §5.1, A1 band).
    Rect visualOf(Finder button) => tester.getRect(
      find.descendant(of: button, matching: find.byType(AnimatedContainer)),
    );
    final plus = visualOf(find.byKey(const Key('sidebar.newTab')));
    expect(visualOf(bell).width, 24);
    expect(plus.left - visualOf(bell).right, 4);
    expect(visualOf(bell).top, plus.top);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    expect(
      find.descendant(of: bell, matching: find.byIcon(Icons.notifications)),
      findsOneWidget,
    );
    expect(dot, findsOneWidget);
    // Centre (19, 7) of the 24 visual, 2 px inside the 28 hit square.
    final b = tester.getRect(bell);
    expect(tester.getCenter(dot), b.topLeft + const Offset(2 + 19, 2 + 7));
    expect(tester.getSize(dot), const Size(6, 6));

    final handle = tester.ensureSemantics();
    final bellNode = find.bySemanticsLabel(
      'Notifications, 1 unread notification',
    );
    expect(
      tester.getSemantics(bellNode),
      isSemantics(
        label: 'Notifications, 1 unread notification',
        isButton: true,
        hasTapAction: true,
        hasToggledState: true,
        isToggled: false,
      ),
    );
    // The band's drag area lies under the buttons: a click is immediate.
    await tester.tap(bell);
    await tester.pump();
    expect(page(tester).panelOpen, isTrue);
    await tester.pumpAndSettle();
    expect(page(tester).panelOpen, isTrue);
    expect(panel, findsOneWidget);
    // The panel is modal for screen readers: the window behind it, the
    // bell included, leaves the tree until it closes (Esc).
    expect(
      find.semantics.byLabel('Notifications, 1 unread notification'),
      findsNothing,
    );
    final visual = tester.widget<AnimatedContainer>(
      find.descendant(of: bell, matching: find.byType(AnimatedContainer)),
    );
    expect(
      (visual.decoration! as BoxDecoration).color,
      const Color(0xFF1F2F34), // rowSelected
    );
    // The band stays out of the barrier: the bell itself closes it.
    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    handle.dispose();
  });

  testSidebar('⌘⇧U jumps to the next unread; none left shows a toast (D13)', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(3, SessionNoticeKind.bell);
    await deliver(tester);
    await chord(tester, LogicalKeyboardKey.keyU);
    expect(tabs().selectedId, 3);
    expect(container.read(tabAttentionProvider).hasUnread(3), isFalse);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
    await chord(tester, LogicalKeyboardKey.keyU);
    expect(tabs().notice, isA<NoUnreadNotice>());
    expect(find.text('No unread notifications'), findsOneWidget);
    expect(tabs().selectedId, 3);
  });

  testSidebar('⌘⇧U from the open panel closes it and jumps', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    await deliver(tester);
    await openPanel(tester);
    await chord(tester, LogicalKeyboardKey.keyU);
    expect(panel, findsNothing);
    expect(tabs().selectedId, 2);
  });

  testSidebar('reduced motion: the panel opens and closes at once', (
    tester,
  ) async {
    await pumpSidebar(tester, disableAnimations: true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(panel, findsOneWidget);
    // Fully shown after one frame: no fade, no slide.
    expect(
      tester
          .widget<FadeTransition>(
            find
                .ancestor(of: panel, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value,
      1,
    );
    expect(
      tester
          .widget<Transform>(
            find.ancestor(of: panel, matching: find.byType(Transform)).first,
          )
          .transform
          .getTranslation()
          .y,
      0,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);
  });

  testSidebar('screen readers follow the ↑/↓ cursor: the item is focused '
      'in semantics while the list holds the keyboard', (tester) async {
    await pumpSidebar(tester);
    final handle = tester.ensureSemantics();
    local.notice(2, SessionNoticeKind.message, body: 'a'); // seq 0
    local.notice(3, SessionNoticeKind.message, body: 'b'); // seq 1
    await deliver(tester);
    await openPanel(tester);
    Tristate focused(int seq) => tester
        .getSemantics(find.byKey(Key('panel.item.$seq')))
        .flagsCollection
        .isFocused;
    expect(focused(1), Tristate.isTrue);
    expect(focused(0), isNot(Tristate.isTrue));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(0), Tristate.isTrue);
    expect(focused(1), isNot(Tristate.isTrue));
    // On "Mark all as read" the item is no longer where the keyboard is.
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(0), isNot(Tristate.isTrue));
    handle.dispose();
  });

  testSidebar('the panel is modal for screen readers too', (tester) async {
    await pumpSidebar(tester);
    final handle = tester.ensureSemantics();
    expect(find.semantics.byLabel('Terminal zsh'), findsOne);
    await openPanel(tester);
    expect(find.semantics.byLabel('Terminal zsh'), findsNothing);
    expect(find.semantics.byLabel('Notifications'), findsOne);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.semantics.byLabel('Terminal zsh'), findsOne);
    handle.dispose();
  });

  testSidebar('after Enter on "Mark all as read" the keyboard is back on '
      'the list: arrows and Esc still work', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a'); // seq 0
    local.notice(3, SessionNoticeKind.message, body: 'b'); // seq 1
    await deliver(tester);
    await openPanel(tester);
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.enter);
    expect(container.read(tabAttentionProvider).totalUnread, 0);
    bool selected(int seq) =>
        tester
            .getSemantics(find.byKey(Key('panel.item.$seq')))
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;
    expect(selected(1), isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(selected(0), isTrue);
    await press(tester, LogicalKeyboardKey.escape);
    expect(panel, findsNothing);
    expect(page(tester).terminalFocus.hasFocus, isTrue);
  });

  testSidebar('with 50 entries the cursor opens scrolled into view and '
      'Home / End follow it', (tester) async {
    await pumpSidebar(tester);
    // Oldest: 5 on tab 2 (unread, seq 0…4); newer: 45 on tab 3, read.
    for (var i = 0; i < 5; i++) {
      local.notice(2, SessionNoticeKind.message, body: 'old $i');
    }
    for (var i = 0; i < 45; i++) {
      local.notice(3, SessionNoticeKind.message, body: 'new $i');
    }
    await deliver(tester);
    container.read(tabAttentionProvider.notifier).markRead(3);
    await tester.pump();
    expect(container.read(tabAttentionProvider).history, hasLength(50));
    await openPanel(tester);
    final box = tester.getRect(panel);
    expect(box.height, lessThanOrEqualTo(480));
    bool shown(int seq) {
      final item = find.byKey(Key('panel.item.$seq'));
      if (item.evaluate().isEmpty) return false;
      final r = tester.getRect(item);
      return r.top >= box.top && r.bottom <= box.bottom;
    }

    // The first unread is the 46th entry (seq 4).
    expect(shown(4), isTrue);
    expect(shown(49), isFalse);
    await press(tester, LogicalKeyboardKey.home);
    expect(shown(49), isTrue);
    expect(shown(4), isFalse);
    await press(tester, LogicalKeyboardKey.end);
    expect(shown(0), isTrue);
  });

  testSidebar('the band stays draggable while the panel is open: the '
      'barrier starts under it (macOS)', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    final barrier = tester.getRect(find.byKey(const Key('panel.barrier')));
    expect(barrier.top, 38);
    // A click on the rest of the window still closes it.
    await tester.tapAt(const Offset(150, 300));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  double fade(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.ancestor(of: panel, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;

  testSidebar('the panel fades in and out (I1)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(fade(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(fade(tester), 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(panel, findsOneWidget); // still fading out
    expect(fade(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testSidebar('more entries than fit: the scrollbar stays visible (F-1)', (
    tester,
  ) async {
    await pumpSidebar(tester);
    for (var i = 0; i < 12; i++) {
      local.notice(2, SessionNoticeKind.message, body: '$i');
    }
    await deliver(tester);
    await openPanel(tester);
    final bar = tester.widget<ShellxScrollbar>(
      find.descendant(of: panel, matching: find.byType(ShellxScrollbar)),
    );
    expect(bar.alwaysVisible, isTrue);
    // The list does overflow: entries are below the fold.
    final list = tester.state<ScrollableState>(
      find.descendant(of: panel, matching: find.byType(Scrollable)),
    );
    expect(list.position.maxScrollExtent, greaterThan(0));
    // The thumb has its own gutter: items end 10 px (6 + 2 × 2) short of
    // the list, so it never covers the time column.
    final item = tester.getRect(find.byKey(const Key('panel.item.11')));
    final scroller = tester.getRect(
      find.descendant(of: panel, matching: find.byType(Scrollable)),
    );
    expect(scroller.right - item.right, 10);
  });

  testSidebar('a failed command is tinted `err`; the cursor on a closed '
      'entry has the dimmer ring (F-9)', (tester) async {
    await pumpSidebar(tester);
    local.notice(
      2,
      SessionNoticeKind.command,
      command: const CompletedCommand(
        commandLine: 'npm test',
        exitCode: 1,
        duration: Duration(seconds: 45),
      ),
    );
    local.notice(3, SessionNoticeKind.message, body: 'bye');
    await deliver(tester);
    Color dot(int seq) =>
        ((tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byKey(Key('panel.item.$seq')),
                        matching: find.byKey(const Key('panel.item.dot')),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .color!);
    container.read(terminalTabsProvider.notifier).close(3);
    await tester.pumpAndSettle();
    await openPanel(tester); // cursor: the first unread (seq 0, failed)
    expect(dot(0), ShellxDesktopColors.err);
    await press(tester, LogicalKeyboardKey.arrowUp); // seq 1, closed
    Color ring(int seq) =>
        ((tester
                            .widget<Container>(
                              find
                                  .descendant(
                                    of: find.byKey(Key('panel.item.$seq')),
                                    matching: find.byType(Container),
                                  )
                                  .first,
                            )
                            .foregroundDecoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(ring(1), ShellxDesktopColors.dim);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(ring(0), ShellxDesktopColors.accent);
  });

  test('relative time (UI-A4 §5.2, F-2)', () {
    final en = AppLocalizationsEn();
    final vi = AppLocalizationsVi();
    final now = DateTime(2026, 10, 7, 12);
    expect(
      relativeTime(now.subtract(const Duration(seconds: 30)), now, en),
      'now',
    );
    expect(relativeTime(now.add(const Duration(seconds: 30)), now, en), 'now');
    expect(
      relativeTime(now.subtract(const Duration(minutes: 5)), now, en),
      '5 min',
    );
    expect(
      relativeTime(now.subtract(const Duration(hours: 3)), now, en),
      '3 h',
    );
    // Yesterday but within 24 h: still hours.
    expect(relativeTime(DateTime(2026, 10, 6, 13), now, en), '23 h');
    expect(
      relativeTime(DateTime(2026, 10, 6, 9, 4), now, en),
      'Yesterday 09:04',
    );
    expect(relativeTime(DateTime(2026, 10, 6, 9, 4), now, vi), 'Hôm qua 09:04');
    expect(relativeTime(DateTime(2026, 10, 5, 22, 5), now, en), 'Oct 5, 22:05');
    expect(relativeTime(DateTime(2026, 10, 5, 22, 5), now, vi), '05/10 22:05');
    // 25 h old, two calendar days back: dated, not "yesterday".
    final early = DateTime(2026, 10, 7, 0, 30);
    expect(
      relativeTime(DateTime(2026, 10, 5, 23, 30), early, en),
      'Oct 5, 23:30',
    );
    expect(
      relativeTime(DateTime(2025, 12, 31, 8, 0), now, en),
      'Dec 31, 08:00',
    );
    expect(
      relativeTime(now.subtract(const Duration(minutes: 5)), now, vi),
      '5 phút',
    );
    expect(
      relativeTime(now.subtract(const Duration(seconds: 1)), now, vi),
      'vừa xong',
    );
  });
}
