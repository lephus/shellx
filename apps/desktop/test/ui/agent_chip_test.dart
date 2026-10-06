import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/agent_marks.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/agent_chip.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

void main() {
  var now = DateTime(2026, 10, 7, 9);
  setUp(() {
    now = DateTime(2026, 10, 7, 9);
    local = FakeLocalSessions();
    local.add(local.summary(1, origin: SessionOrigin.desktop));
  });

  Future<void> pump(WidgetTester t) => pumpSidebar(
    t,
    overrides: [agentMarksClockProvider.overrideWithValue(() => now)],
  );

  AgentMarks marks() => container.read(agentMarksProvider.notifier);

  Finder chipIn(Finder parent) =>
      find.descendant(of: parent, matching: find.byType(AgentChip));

  testSidebar('the tab row shows "Agent" for 10 s after a command, after '
      'the title; read in the row\'s label (D27)', (t) async {
    final semantics = t.ensureSemantics();
    await pump(t);
    expect(find.byType(AgentChip), findsNothing);
    marks().touch(tab: 1);
    await t.pump();
    expect(chipIn(row(1)), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    final chip = t.getRect(chipIn(row(1)));
    expect(chip.height, ShellxSizes.agentChipRowHeight);
    // UI §2.1 of A6: warn fill and border, pill, the robot icon at 12.
    final box = t.widget<DecoratedBox>(
      find.descendant(of: chipIn(row(1)), matching: find.byType(DecoratedBox)),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, ShellxDesktopColors.warnBg);
    expect(
      decoration.border,
      Border.all(color: ShellxDesktopColors.warnBorder),
    );
    expect(decoration.borderRadius, BorderRadius.circular(ShellxRadius.pill));
    final icon = t.widget<Icon>(
      find.descendant(of: chipIn(row(1)), matching: find.byType(Icon)),
    );
    expect(icon.icon, Icons.smart_toy_outlined);
    expect(icon.size, 12);
    expect(
      find.bySemanticsLabel(
        RegExp('A program is controlling this tab through the ShellX'),
      ),
      findsOneWidget,
    );
    // Not a focus stop.
    expect(
      find.descendant(of: chipIn(row(1)), matching: find.byType(ExcludeFocus)),
      findsOneWidget,
    );

    now = now.add(const Duration(seconds: 9));
    await t.pump(const Duration(seconds: 9));
    expect(chipIn(row(1)), findsOneWidget);
    now = now.add(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(find.byType(AgentChip), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('A program is controlling this tab')),
      findsNothing,
    );
    semantics.dispose();
  });

  testSidebar('a split tab: the target pane\'s header shows the larger chip '
      'before ×; its region label says so', (t) async {
    final semantics = t.ensureSemantics();
    await pump(t);
    await container.read(terminalTabsProvider.notifier).split(SplitAxis.row);
    await t.pump();
    await t.pump();
    final second = tabs().tabs.single.panes.keys.last;
    marks().touch(tab: tabs().tabs.single.id, pane: second);
    await t.pump();
    final header = find.byKey(Key('pane.header.$second'));
    expect(chipIn(header), findsOneWidget);
    expect(chipIn(find.byKey(const Key('pane.header.1'))), findsNothing);
    expect(t.getRect(chipIn(header)).height, ShellxSizes.agentChipPaneHeight);
    // Before the × (which sits at the header's right end).
    expect(
      t.getRect(chipIn(header)).right,
      lessThan(t.getRect(find.byKey(Key('pane.close.$second'))).left),
    );
    expect(
      find.bySemanticsLabel(RegExp('Pane 2 of 2.*A program is controlling')),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
