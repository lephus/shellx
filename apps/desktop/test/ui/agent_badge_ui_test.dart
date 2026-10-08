import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/terminal/agent_badge.dart';
import 'package:shellx_desktop/src/ui/terminal/session_tab_row.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import '../support/fake_local_sessions.dart';
import 'sidebar_test_harness.dart';

final t0 = DateTime.utc(2026, 10, 7, 12);

AgentEvent ev(
  int pane,
  AgentEventKind k, {
  int s = 0,
  AgentKind agent = AgentKind.claude,
}) => AgentEvent(
  pane: pane,
  agent: agent,
  kind: k,
  at: t0.add(Duration(seconds: s)),
);

Widget wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  double? width,
}) => MaterialApp(
  theme: buildDesktopTheme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double contrast(Color a, Color b) {
  final hi = max(_lum(a), _lum(b)), lo = min(_lum(a), _lum(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const words = {
    'en': {
      AgentState.running: 'Running',
      AgentState.needsInput: 'Needs input',
      AgentState.idle: 'Idle',
      AgentState.done: 'Done',
    },
    'vi': {
      AgentState.running: 'Đang chạy',
      AgentState.needsInput: 'Cần bạn trả lời',
      AgentState.idle: 'Đang chờ',
      AgentState.done: 'Xong',
    },
  };

  for (final lang in words.keys) {
    testWidgets('$lang: all four states show icon and word', (t) async {
      for (final MapEntry(key: state, value: word) in words[lang]!.entries) {
        await t.pumpWidget(
          wrap(
            AgentBadge(state: state, agent: AgentKind.claude),
            locale: Locale(lang),
          ),
        );
        expect(find.text(word), findsOneWidget, reason: '$lang $state');
        expect(find.byType(Icon), findsOneWidget);
        expect(
          t.widget<Icon>(find.byType(Icon)).icon,
          agentBadgeLook(state).icon,
        );
      }
      // Four different icons: never colour alone.
      expect({
        for (final s in words[lang]!.keys) agentBadgeLook(s).icon,
      }, hasLength(4));
    });
  }

  testWidgets('compact: the icon only, the label stays for screen readers', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      wrap(
        const AgentBadge(
          state: AgentState.running,
          agent: AgentKind.codex,
          compact: true,
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.bySemanticsLabel('Codex: Running'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a live region only for a question', (t) async {
    final semantics = t.ensureSemantics();
    for (final s in [AgentState.running, AgentState.idle, AgentState.done]) {
      await t.pumpWidget(wrap(AgentBadge(state: s, agent: AgentKind.claude)));
      final node = t.getSemantics(
        find.bySemanticsLabel(RegExp('Claude Code: ')),
      );
      expect(node.flagsCollection.isLiveRegion, isFalse, reason: '$s');
    }
    await t.pumpWidget(
      wrap(
        const AgentBadge(state: AgentState.needsInput, agent: AgentKind.claude),
      ),
    );
    final node = t.getSemantics(
      find.bySemanticsLabel('Claude Code needs your input'),
    );
    expect(node.flagsCollection.isLiveRegion, isTrue);
    await t.pumpWidget(
      wrap(
        const AgentBadge(state: AgentState.needsInput, agent: AgentKind.claude),
        locale: const Locale('vi'),
      ),
    );
    expect(
      t
          .getSemantics(find.bySemanticsLabel('Claude Code cần bạn trả lời'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  test('badge colours have 3:1 on every surface they sit on', () {
    for (final s in [
      AgentState.running,
      AgentState.needsInput,
      AgentState.idle,
      AgentState.done,
    ]) {
      for (final bg in [
        ShellxDesktopColors.bgSidebar,
        ShellxDesktopColors.rowSelected,
        ShellxDesktopColors.rowHover,
        ShellxDesktopColors.rowPressed,
        ShellxDesktopColors.bgTerminal,
        ShellxDesktopColors.surface,
      ]) {
        expect(
          contrast(agentBadgeLook(s).color, bg),
          greaterThanOrEqualTo(3),
          reason: '$s on $bg',
        );
      }
    }
  });

  group('in the window', () {
    setUp(() {
      local = FakeLocalSessions();
      local.add(local.summary(1, origin: SessionOrigin.desktop));
    });

    AgentStatusNotifier agents() =>
        container.read(agentStatusProvider.notifier);

    String? rowLabel(WidgetTester t, int tab) => t.getSemantics(row(tab)).label;

    testSidebar('the row shows the badge after the title and reads it', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      await pumpSidebar(t);
      final before = rowLabel(t, 1);
      expect(find.byType(AgentBadge), findsNothing);
      agents().ingest(ev(1, AgentEventKind.running));
      await t.pump();
      final badge = find.descendant(
        of: row(1),
        matching: find.byType(AgentBadge),
      );
      expect(badge, findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(rowLabel(t, 1), contains('Claude Code: Running'));
      expect(t.widget<AgentBadge>(badge).large, isFalse);
      agents().ingest(ev(1, AgentEventKind.needsInput, s: 1));
      await t.pump();
      // The question also made an unread badge: the word gives way, the
      // icon and the label stay.
      expect(find.text('Needs input'), findsNothing);
      expect(t.widget<AgentBadge>(badge).compact, isTrue);
      expect(rowLabel(t, 1), contains('Claude Code needs your input'));
      expect(t.getSemantics(row(1)).flagsCollection.isLiveRegion, isTrue);
      // The agent ends: the row is as it was.
      agents().ingest(ev(1, AgentEventKind.end, s: 2));
      await t.pump();
      expect(find.byType(AgentBadge), findsNothing);
      expect(rowLabel(t, 1), isNot(contains('Claude Code: Running')));
      expect(before, isNot(contains('Claude Code')));
      expect(t.getSemantics(row(1)).flagsCollection.isLiveRegion, isFalse);
      semantics.dispose();
    });

    testSidebar('a tab with no record is laid out exactly as before', (
      t,
    ) async {
      await pumpSidebar(t);
      final rowRect = t.getRect(row(1));
      final title = t.getRect(
        find.descendant(of: row(1), matching: find.byType(Text)).first,
      );
      agents().ingest(ev(1, AgentEventKind.start));
      await t.pump();
      agents().ingest(ev(1, AgentEventKind.end, s: 1));
      await t.pump();
      expect(t.getRect(row(1)), rowRect);
      expect(
        t.getRect(
          find.descendant(of: row(1), matching: find.byType(Text)).first,
        ),
        title,
      );
    });

    testSidebar('two panes: the row shows the most urgent, the headers '
        'their own', (t) async {
      final semantics = t.ensureSemantics();
      await pumpSidebar(t);
      await container.read(terminalTabsProvider.notifier).split(SplitAxis.row);
      await t.pump();
      expect(tabs().tabs.single.paneCount, 2);
      agents().ingest(ev(1, AgentEventKind.running));
      agents().ingest(
        ev(100, AgentEventKind.needsInput, s: 1, agent: AgentKind.codex),
      );
      await t.pump();
      final inRow = find.descendant(
        of: row(1),
        matching: find.byType(AgentBadge),
      );
      expect(t.widget<AgentBadge>(inRow).state, AgentState.needsInput);
      expect(t.widget<AgentBadge>(inRow).agent, AgentKind.codex);
      expect(t.widget<AgentBadge>(inRow).compact, isTrue); // split: crowded
      final h1 = find.byKey(const Key('pane.agent.1'));
      final h100 = find.byKey(const Key('pane.agent.100'));
      expect(t.widget<AgentBadge>(h1).state, AgentState.running);
      expect(t.widget<AgentBadge>(h1).large, isTrue);
      expect(t.widget<AgentBadge>(h100).agent, AgentKind.codex);
      expect(
        find.bySemanticsLabel(RegExp('Pane 1 of 2.*Claude Code: Running')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testSidebar('a row narrower than 160 px keeps the icon only', (t) async {
      await pumpSidebar(t);
      agents().ingest(ev(1, AgentEventKind.running));
      await t.pump();
      Widget narrow(double width) => UncontrolledProviderScope(
        container: container,
        child: wrap(
          width: width,
          SessionTabRow(
            tab: tabs().tabs.single,
            selected: false,
            position: 1,
            count: 1,
            onSelect: () {},
            onClose: () {},
            agentStatus: (state: AgentState.running, agent: AgentKind.claude),
          ),
        ),
      );
      await t.pumpWidget(narrow(150));
      expect(t.widget<AgentBadge>(find.byType(AgentBadge)).compact, isTrue);
      expect(find.text('Running'), findsNothing);
      await t.pumpWidget(narrow(220));
      expect(t.widget<AgentBadge>(find.byType(AgentBadge)).compact, isFalse);
      expect(find.text('Running'), findsOneWidget);
    });
  });
}
