import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/terminal/terminal_font_size.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/ui/terminal/attention_marks.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:xterm/xterm.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  setUp(() {
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  testSidebar('a one-pane tab is laid out, labelled, ringed and sized '
      'exactly like A4', (t) async {
    final semantics = t.ensureSemantics();
    await pumpSidebar(t);
    await t.pump();
    // Layout: the terminal fills the area right of the sidebar.
    final view = t.getRect(find.byType(TerminalView));
    expect(view.left, ShellxSizes.sidebarWidth + 1);
    expect(view.top, ShellxSizes.paneHeaderMac);
    expect(view.right, 1100);
    expect(view.bottom, 720);
    // No A3 chrome.
    expect(find.byKey(const Key('pane.header.1')), findsNothing);
    expect(find.byKey(const Key('pane.focusOutline')), findsNothing);
    expect(find.byKey(const Key('pane.divider.')), findsNothing);
    expect(find.byKey(const Key('row.paneCount.1')), findsNothing);
    expect(find.bySemanticsLabel('Terminal zsh 1'), findsOneWidget);
    // Size: the session got the grid of the whole area (A1).
    final grid = measureTerminalGrid(
      ShellxSizes.terminalPadding.deflateSize(view.size),
      desktopTerminalStyle(container.read(terminalFontSizeProvider)),
      TextScaler.noScaling,
    )!;
    expect(local.views[1]!.resizes.last, (grid.cols, grid.rows));
    // Ring: A4's rect (the terminal area).
    container.read(windowFocusProvider.notifier).set(false);
    local.notice(1, SessionNoticeKind.message, body: 'done');
    await t.pump(); // notices reach the listener asynchronously
    await t.pump();
    final ring = find.byWidgetPredicate((w) => w is AttentionRing && w.visible);
    expect(t.getRect(ring), view);
    semantics.dispose();
  });
}
