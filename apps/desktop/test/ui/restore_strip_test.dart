import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/scrollback_codec.dart';
import 'package:shellx_desktop/src/ui/terminal/info_strip.dart';
import 'package:shellx_desktop/src/ui/terminal/session_sidebar.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_workspace_page.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

TerminalWorkspacePageState page(WidgetTester t) =>
    t.state<TerminalWorkspacePageState>(find.byType(TerminalWorkspacePage));

final strip = find.byKey(const Key('pane.restoreStrip'));

void showStrip({DateTime? contentsAt}) => container
    .read(restoreStripProvider.notifier)
    .show(RestoreStripState(tabs: 5, contentsAt: contentsAt));

Future<void> key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
  await t.pump();
}

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('no strip until a restore asks for one', (t) async {
    await pumpSidebar(t);
    expect(strip, findsNothing);
    expect(find.byType(InfoStrip), findsNothing);
  });

  testSidebar('the strip shows the restored tabs and the contents time, '
      'above the terminal, and is read once (UI-A5 §4)', (t) async {
    await pumpSidebar(t);
    t.takeAnnouncements();
    // The strip reads the real clock (clockProvider): contents saved a
    // moment ago show as a time of today.
    final at = DateTime.now();
    final time = formatRestoreTime(
      at,
      DateTime.now(),
      localeName: 'en',
      yesterday: (time) => 'yesterday $time',
    );
    final text =
        "ShellX didn't close normally last time. Reopened 5 tabs; "
        'contents as of $time.';
    showStrip(contentsAt: at);
    await t.pump();
    await t.pump();
    expect(strip, findsOneWidget);
    expect(find.text(text), findsOneWidget);
    expect(t.takeAnnouncements().map((a) => a.message).toList(), [text]);
    final stripRect = t.getRect(strip);
    final terminal = t.getRect(find.byKey(const ValueKey('terminal.1')));
    expect(stripRect.bottom, lessThanOrEqualTo(terminal.top));
    // A new strip is read once; rebuilds read nothing more.
    showStrip(contentsAt: null);
    await t.pump();
    expect(
      find.text("ShellX didn't close normally last time. Reopened 5 tabs."),
      findsOneWidget,
    );
    expect(t.takeAnnouncements(), hasLength(1)); // a new strip, read once
    await t.pump();
    await t.pump();
    expect(t.takeAnnouncements(), isEmpty);
  });

  testSidebar('F6 goes sidebar → strip → terminal; Close dismisses with a '
      '120 ms fade and gives the keyboard to the terminal', (t) async {
    await pumpSidebar(t);
    showStrip();
    await t.pumpAndSettle();
    final p = page(t);
    expect(p.terminalFocus.hasFocus, isTrue);
    // Ctrl+F6 leaves the terminal (plain F6 belongs to the shell).
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f6);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(p.sidebarFocus.hasFocus, isTrue);
    await key(t, LogicalKeyboardKey.f6);
    expect(p.restoreStripFocus.hasFocus, isTrue);
    await key(t, LogicalKeyboardKey.f6);
    expect(p.terminalFocus.hasFocus, isTrue);

    await t.tap(find.byKey(const Key('infoStrip.close')));
    await t.pump();
    expect(container.read(restoreStripProvider), isNull);
    expect(p.terminalFocus.hasFocus, isTrue);
    await t.pump(const Duration(milliseconds: 60));
    expect(strip, findsOneWidget); // fading out
    await t.pump(const Duration(milliseconds: 70));
    expect(strip, findsNothing);
    // Gone from the region cycle too.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.f6);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    await key(t, LogicalKeyboardKey.f6);
    expect(p.terminalFocus.hasFocus, isTrue);
  });

  testSidebar('Esc on the strip dismisses it; the terminal gets the '
      'keyboard; the shell gets no key', (t) async {
    await pumpSidebar(t);
    showStrip();
    await t.pumpAndSettle();
    final p = page(t);
    p.restoreStripFocus.requestFocus();
    await t.pump();
    await key(t, LogicalKeyboardKey.escape);
    expect(container.read(restoreStripProvider), isNull);
    expect(p.terminalFocus.hasFocus, isTrue);
    await t.pumpAndSettle();
    expect(strip, findsNothing);
    expect(local.views[1]!.writes, isEmpty);
  });

  testSidebar('Tab order: the strip comes after the sidebar and before the '
      'terminal', (t) async {
    await pumpSidebar(t);
    showStrip();
    await t.pumpAndSettle();
    final p = page(t);
    p.restoreStripFocus.requestFocus();
    await t.pump();
    await key(t, LogicalKeyboardKey.tab);
    expect(p.terminalFocus.hasFocus, isTrue);
    p.restoreStripFocus.requestFocus();
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    final focused = FocusManager.instance.primaryFocus!;
    final inSidebar =
        focused.context?.findAncestorWidgetOfExactType<SessionSidebar>() !=
        null;
    expect(inSidebar, isTrue, reason: '$focused');
  });
}
