import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/l10n/app_localizations_vi.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/notifications_panel.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';

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

  testSidebar('geometry: x 8, under the header band + 4, 360 wide '
      '(UI-A4 §5.2)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    await openPanel(tester);
    final rect = tester.getRect(panel);
    expect(rect.left, 8);
    expect(rect.top, 38 + 4); // macOS band
    expect(rect.width, 360);
    // border 1 + padding 4 + header 36 + line 1 + item 52 + footer 24
    // + padding 4 + border 1.
    expect(rect.height, 1 + 4 + 36 + 1 + 52 + 24 + 4 + 1);
    expect(tester.getSize(find.byKey(const Key('panel.item.0'))).height, 52);
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

  testSidebar('empty state and disabled "Mark all as read"', (tester) async {
    await pumpSidebar(tester);
    await openPanel(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      find.text(
        'Programs in your tabs send notifications with OSC 9, 99, 777 or '
        'the shellx notify command.',
      ),
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
    // Bell, 4, then `+` (UI-A4 §5.1).
    final plus = tester.getRect(find.byKey(const Key('sidebar.newTab')));
    expect(tester.getRect(bell).right + 4, plus.left);
    expect(tester.getRect(bell).top, plus.top);
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
    // The macOS band is a DragToMoveArea (double-click zooms): a click
    // resolves after the double-tap timeout.
    await tester.tap(bell);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(page(tester).panelOpen, isTrue);
    expect(panel, findsOneWidget);
    expect(
      tester.getSemantics(bellNode),
      isSemantics(hasToggledState: true, isToggled: true),
    );
    final visual = tester.widget<AnimatedContainer>(
      find.descendant(of: bell, matching: find.byType(AnimatedContainer)),
    );
    expect(
      (visual.decoration! as BoxDecoration).color,
      const Color(0xFF1F2F34), // rowSelected
    );
    // The barrier over it takes the click: it closes as well.
    await tester.tapAt(tester.getCenter(bell));
    await tester.pump(kDoubleTapTimeout);
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
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);
  });

  test('relative time (UI-A4 §5.2)', () {
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
    expect(relativeTime(DateTime(2026, 10, 5, 9, 4), now, en), '09:04');
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
