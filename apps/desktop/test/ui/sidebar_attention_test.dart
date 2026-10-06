import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

/// The fake's notices arrive asynchronously (a broadcast stream, as from
/// the agent): the first pump delivers them, the second draws the result.
Future<void> deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, title: 'zsh'));
    local.add(local.summary(2, title: 'api', cwd: '/Users/test/api'));
  });

  testSidebar('an unread tab shows a badge and its last text; reading '
      'removes both (UI-A4 §2)', (tester) async {
    await pumpSidebar(tester);
    expect(find.byKey(const Key('row.badge')), findsNothing);
    local.notice(2, SessionNoticeKind.message, body: 'Build xong');
    local.notice(2, SessionNoticeKind.message, body: 'Lần hai');
    await deliver(tester);
    expect(
      find.descendant(of: row(2), matching: find.byKey(const Key('row.badge'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row(2), matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('Lần hai'), findsOneWidget);
    // title + notification + context line: 62 (UI-A4 §1.3).
    expect(tester.getSize(row(2)).height, 62);
    container.read(tabAttentionProvider.notifier).markRead(2);
    await tester.pump();
    expect(find.byKey(const Key('row.badge')), findsNothing);
    expect(find.text('Lần hai'), findsNothing);
    expect(tester.getSize(row(2)).height, 46);
  });

  testSidebar('a row without context grows to 46 with a notification', (
    tester,
  ) async {
    await pumpSidebar(tester);
    // The harness never focuses the window, so the selected tab 1 still
    // gets unread (D7 needs an active window).
    local.notice(1, SessionNoticeKind.bell);
    await deliver(tester);
    expect(tester.getSize(row(1)).height, 46);
    expect(find.text('Bell'), findsOneWidget);
  });

  testSidebar('99+ over 99', (tester) async {
    await pumpSidebar(tester);
    for (var i = 0; i < 4; i++) {
      // 4 × 30 (agent limit is not in the fake): 120 unread.
      for (var j = 0; j < 30; j++) {
        local.notice(2, SessionNoticeKind.message, body: '$i$j');
      }
    }
    await deliver(tester);
    expect(find.text('99+'), findsOneWidget);
  });

  testSidebar('the row label says the unread count and latest text '
      '(UI-A4 §8)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, title: 'CI', body: 'đỏ');
    await deliver(tester);
    expect(
      tester.getSemantics(row(2)).label,
      contains('1 unread notification, latest: CI: đỏ'),
    );
  });

  testSidebar('row menu: Mark as read / Mark all as read (D23)', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    local.notice(1, SessionNoticeKind.message, body: 'b');
    await deliver(tester);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.markRead')));
    await tester.pumpAndSettle();
    final attention = container.read(tabAttentionProvider);
    expect(attention.hasUnread(2), isFalse);
    expect(attention.hasUnread(1), isTrue);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu.markAllRead')));
    await tester.pumpAndSettle();
    expect(container.read(tabAttentionProvider).unread, isEmpty);
  });

  testSidebar('a collapsed workspace with unread shows the dot (D22)', (
    tester,
  ) async {
    await pumpSidebar(tester);
    await workspaces().create(moveTab: 2);
    await tester.pump();
    final ws = sidebar().workspaceOf(2)!;
    workspaces().setCollapsed(ws, true);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    await deliver(tester);
    expect(find.byKey(const Key('header.unreadDot')), findsOneWidget);
    workspaces().setCollapsed(ws, false);
    await tester.pump();
    expect(find.byKey(const Key('header.unreadDot')), findsNothing);
  });

  testSidebar('the badge sits 4 after the title; the line starts at 32, '
      '2 under the title line (UI-A4 §2.1)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'Build xong');
    await deliver(tester);
    final badge = find.byKey(const Key('row.badge'));
    final title = find.descendant(of: row(2), matching: find.text('api'));
    expect(tester.getTopLeft(badge).dx - tester.getTopRight(title).dx, 4);
    expect(tester.getSize(badge).height, 16);
    final rowBox = tester.getTopLeft(row(2));
    final line = tester.getTopLeft(find.byKey(const Key('row.notification')));
    expect(line.dx - rowBox.dx, 32);
    expect(line.dy - rowBox.dy, 6 + 18 + 2);
    // The context line moves below it: 6 + 18 + 2 + 14 + 2
    final context = find.descendant(
      of: row(2),
      matching: find.byKey(const Key('row.contextLine')),
    );
    // (centred in its 24 px port hit box).
    expect(tester.getCenter(context).dy - rowBox.dy, 42 + 7);
  });

  testSidebar('large text: 46/62 grow with the scale (UI-A4 §1.3)', (
    tester,
  ) async {
    await pumpSidebar(tester, textScale: 1.5);
    local.notice(1, SessionNoticeKind.bell);
    local.notice(2, SessionNoticeKind.message, body: 'x');
    await deliver(tester);
    // 27 + 21 + 14 and 27 + 2·21 + 16.
    expect(tester.getSize(row(1)).height, 62);
    expect(tester.getSize(row(2)).height, 85);
    expect(tester.getSize(find.byKey(const Key('row.badge')).first).height, 23);
  });

  testSidebar('mark-as-read entries are dimmed with nothing to read '
      '(UI-A4 §10.4)', (tester) async {
    await pumpSidebar(tester);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    PopupMenuItem<Object> item(String key) =>
        tester.widget<PopupMenuItem<Object>>(find.byKey(Key(key)));
    expect(item('menu.markRead').enabled, isFalse);
    expect(item('menu.markAllRead').enabled, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    local.notice(1, SessionNoticeKind.message, body: 'b');
    await deliver(tester);
    await tester.tap(row(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(item('menu.markRead').enabled, isFalse);
    expect(item('menu.markAllRead').enabled, isTrue);
  });

  testSidebar('"Mark as read" is a custom action only while the row has '
      'unread (UI-A4 §8)', (tester) async {
    await pumpSidebar(tester);
    const action = CustomSemanticsAction(label: 'Mark as read');
    bool hasAction() => tester
        .getSemantics(row(2))
        .getSemanticsData()
        .customSemanticsActionIds!
        .contains(CustomSemanticsAction.getIdentifier(action));
    expect(hasAction(), isFalse);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    expect(hasAction(), isTrue);
    final node = tester.getSemantics(row(2));
    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(action),
    );
    await tester.pump();
    expect(container.read(tabAttentionProvider).hasUnread(2), isFalse);
    expect(hasAction(), isFalse);
  });

  testSidebar('custom actions follow the row menu: mark read, mark all, '
      'rename, move, close (UI-A4 §8)', (tester) async {
    await pumpSidebar(tester);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    final labels = [
      for (final id
          in tester
              .getSemantics(row(2))
              .getSemanticsData()
              .customSemanticsActionIds!)
        CustomSemanticsAction.getAction(id)!.label,
    ];
    expect(labels, [
      'Mark as read',
      'Mark all as read',
      'Rename tab',
      'Move to workspace…',
      'Move up',
      'Close tab',
    ]);
  });

  testSidebar('the line is worded in the language shown, not the one of '
      'its arrival (F-4); a failed command tints the icon `err`', (
    tester,
  ) async {
    await pumpSidebar(tester, locale: const Locale('vi'));
    local.notice(2, SessionNoticeKind.bell); // arrives with the en provider
    await deliver(tester);
    expect(
      find.descendant(of: row(2), matching: find.text('Chuông')),
      findsOneWidget,
    );
    Color icon() => tester
        .widget<Icon>(
          find.descendant(
            of: row(2),
            matching: find.byKey(const Key('row.notificationIcon')),
          ),
        )
        .color!;
    expect(icon(), ShellxDesktopColors.accent);
    local.notice(
      2,
      SessionNoticeKind.command,
      command: const CompletedCommand(
        commandLine: 'npm test',
        exitCode: 2,
        duration: Duration(seconds: 3),
      ),
    );
    await deliver(tester);
    expect(icon(), ShellxDesktopColors.err);
  });

  testSidebar('collapsed header: the dot sits 4 px left of the count '
      'glyph (UI-A4 §3)', (tester) async {
    await pumpSidebar(tester);
    await workspaces().create(moveTab: 2);
    workspaces().toggleCollapsed(sidebar().workspaceOf(2)!);
    local.notice(2, SessionNoticeKind.message, body: 'a');
    await deliver(tester);
    await tester.pumpAndSettle();
    final dot = tester.getRect(find.byKey(const Key('header.unreadDot')).first);
    final count = find.byKey(const Key('header.count')).first;
    final glyph = tester.renderObject<RenderParagraph>(count);
    final box = tester.getRect(count);
    final glyphLeft =
        box.left + (box.width - glyph.getMaxIntrinsicWidth(box.height)) / 2;
    expect(glyphLeft - dot.right, closeTo(4, 0.01));
  });

  testSidebar('renaming hides the badge, keeps the line, and the open name '
      'field survives a notice and its read (UI-A4 §2.2, I1)', (tester) async {
    await pumpSidebar(tester);
    container.read(terminalTabsProvider.notifier).select(1);
    workspaces().startRename(const RenameTab(2));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('row.renameField'));
    await tester.enterText(field, 'typed');
    final state = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    Future<void> expectKept() async {
      await tester.pumpAndSettle();
      final now = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(identical(now, state), isTrue);
      expect(now.textEditingValue.text, 'typed');
      expect(now.widget.focusNode.hasFocus, isTrue);
    }

    local.notice(2, SessionNoticeKind.message, body: 'Build xong');
    await deliver(tester);
    await expectKept();
    expect(find.byKey(const Key('row.badge')), findsNothing);
    expect(find.text('Build xong'), findsOneWidget);
    expect(tester.getSize(row(2)).height, 62);
    container.read(tabAttentionProvider.notifier).markRead(2);
    await expectKept();
    expect(find.text('Build xong'), findsNothing);
  });

  testSidebar('without unread the rows and headers look as in A2', (
    tester,
  ) async {
    await pumpSidebar(tester);
    expect(tester.getSize(row(1)).height, 30);
    expect(tester.getSize(row(2)).height, 46);
    expect(find.byKey(const Key('row.notification')), findsNothing);
    expect(find.byKey(const Key('header.unreadDot')), findsNothing);
  });

  testSidebar('the × keeps its whole column over the notification line', (
    tester,
  ) async {
    await pumpSidebar(tester);
    local.notice(1, SessionNoticeKind.bell);
    await deliver(tester);
    final close = tester.getRect(
      find.descendant(of: row(1), matching: find.byKey(const Key('row.close'))),
    );
    final line = tester.getRect(find.byKey(const Key('row.notification')));
    // At 1× the 24 px × box reaches 1 px into the line's band.
    expect(close.bottom - line.top, 1);
    await tester.tapAt(Offset(close.center.dx, close.bottom - 0.5));
    await tester.pumpAndSettle();
    expect(local.closed, contains(1));
  });
}
