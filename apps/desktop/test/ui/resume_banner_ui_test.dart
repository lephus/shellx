import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/closed_items.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/resume_offers.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_workspace.dart';

Finder banner(int pane) => find.byKey(Key('resume.banner.$pane'));
Finder resumeButton(int pane) => find.byKey(Key('resume.go.$pane'));
Finder dismissButton(int pane) => find.byKey(Key('resume.dismiss.$pane'));

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(int, dynamic, ProviderContainer)> boot(
    WidgetTester t, {
    Locale locale = const Locale('en'),
    AgentKind kind = AgentKind.claude,
    String session = 'abc',
  }) async {
    final rig = await pumpConfiguredWorkspace(t, locale: locale);
    final c = rig.container;
    final pane = c.read(terminalTabsProvider).selected!.focusedPaneId;
    c.read(resumeOffersProvider.notifier).add(pane, ResumeOffer(kind, session));
    await t.pumpAndSettle();
    return (pane, rig.local, c);
  }

  testWidgets('shows the §4.2 text in English and in Vietnamese; nothing is '
      'typed', (t) async {
    var (pane, local, c) = await boot(t);
    expect(
      find.text('Claude Code was running here before ShellX restarted.'),
      findsOneWidget,
    );
    expect(find.text('Resume session'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(local.views[pane]!.writes, isEmpty);
    await disposeWorkspace(t, c);

    (pane, local, c) = await boot(t, locale: const Locale('vi'));
    expect(
      find.text('Claude Code đang chạy ở đây trước khi ShellX khởi động lại.'),
      findsOneWidget,
    );
    expect(find.text('Tiếp tục phiên'), findsOneWidget);
    expect(find.text('Bỏ qua'), findsOneWidget);
    expect(local.views[pane]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('one press types the command exactly once, then the banner '
      'and the offer are gone', (t) async {
    final (pane, local, c) = await boot(t);
    await t.tap(resumeButton(pane));
    await t.pump();
    // Gone at once: a second press cannot type it again.
    expect(banner(pane), findsNothing);
    expect(c.read(resumeOffersProvider), isEmpty);
    await t.pump(const Duration(seconds: 10));
    final typed = local.views[pane]!.writes.join();
    expect('claude --resume abc'.allMatches(typed), hasLength(1));
    expect(typed, endsWith('\r'));
    expect(
      typed.replaceAll('\r', '').replaceAll(RegExp(r'\x1b\[20[01]~'), ''),
      'claude --resume abc',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('each agent types its own fixed command', (t) async {
    for (final (kind, expected) in [
      (AgentKind.codex, 'codex resume s-1'),
      (AgentKind.gemini, 'gemini --resume s-1'),
      (AgentKind.opencode, 'opencode --session s-1'),
    ]) {
      final (pane, local, c) = await boot(t, kind: kind, session: 's-1');
      await t.tap(resumeButton(pane));
      await t.pump(const Duration(seconds: 10));
      expect(local.views[pane]!.writes.join(), contains(expected));
      await disposeWorkspace(t, c);
    }
  }, variant: mac);

  testWidgets('Dismiss removes it without typing', (t) async {
    final (pane, local, c) = await boot(t);
    await t.tap(dismissButton(pane));
    await t.pump(const Duration(seconds: 10));
    expect(banner(pane), findsNothing);
    expect(c.read(resumeOffersProvider), isEmpty);
    expect(local.views[pane]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Esc on the banner dismisses it without typing', (t) async {
    final (pane, local, c) = await boot(t);
    t.widget<TextButton>(dismissButton(pane)).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(banner(pane), findsNothing);
    expect(local.views[pane]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the first real keystroke into the pane removes it', (t) async {
    final (pane, local, c) = await boot(t);
    c
        .read(terminalTabsProvider)
        .tabOfSession(pane)!
        .panes[pane]!
        .terminal
        .onUserInput!('x');
    await t.pumpAndSettle();
    expect(banner(pane), findsNothing);
    expect(c.read(resumeOffersProvider), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the tooltip shows the command', (t) async {
    final (pane, _, c) = await boot(t);
    final tip = t.widget<Tooltip>(
      find.ancestor(of: resumeButton(pane), matching: find.byType(Tooltip)),
    );
    expect(tip.message, contains('claude --resume abc'));
    expect(tip.message, contains('presses Enter'));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('it does not take the keyboard from the terminal', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final before = FocusManager.instance.primaryFocus;
    final pane = c.read(terminalTabsProvider).selected!.focusedPaneId;
    c
        .read(resumeOffersProvider.notifier)
        .add(pane, const ResumeOffer(AgentKind.claude, 'abc'));
    await t.pumpAndSettle();
    expect(banner(pane), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(before));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the screen reader hears the whole sentence and two buttons; '
      'it is not a live region', (t) async {
    final semantics = t.ensureSemantics();
    final (pane, _, c) = await boot(t);
    expect(
      find.bySemanticsLabel(
        'Claude Code was running here before ShellX restarted.',
      ),
      findsOneWidget,
    );
    final node = t.getSemantics(
      find.bySemanticsLabel(
        'Claude Code was running here before ShellX restarted.',
      ),
    );
    expect(node.flagsCollection.isLiveRegion, isFalse);
    expect(find.bySemanticsLabel('Resume session'), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss'), findsOneWidget);
    semantics.dispose();
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a split tab shows the banner on its own pane only; the other '
      'pane stays as it was', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    await c.read(terminalTabsProvider.notifier).split(SplitAxis.row);
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    final first = tab.paneOrder.first, second = tab.paneOrder.last;
    c
        .read(resumeOffersProvider.notifier)
        .add(second, const ResumeOffer(AgentKind.codex, 'abc'));
    await t.pumpAndSettle();
    expect(banner(second), findsOneWidget);
    expect(banner(first), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a closed tab brought back with ⌘⇧T offers its agent again '
      '(A11 D14)', (t) async {
    final rig = await pumpConfiguredWorkspace(t);
    final c = rig.container;
    final tabs = c.read(terminalTabsProvider.notifier);
    final second = await tabs.openTabFor(select: true);
    await t.pumpAndSettle();
    // The shell reported its folder (OSC 7).
    rig.local.replace(rig.local.summary(second, cwd: '/w/api'));
    await t.pumpAndSettle();
    expect(
      c
          .read(agentStatusProvider.notifier)
          .ingest(
            AgentEvent(
              pane: second,
              agent: AgentKind.gemini,
              kind: AgentEventKind.start,
              at: DateTime.now(),
              session: 'g-1',
            ),
          ),
      isTrue,
    );
    c.read(terminalTabsProvider).tabs.last.terminal.write('history');
    tabs.close(second);
    await t.pumpAndSettle();
    expect(c.read(closedItemsProvider).length, 1);
    await c.read(closedItemsProvider.notifier).reopenNewest();
    await t.pumpAndSettle();
    final reopened = c.read(terminalTabsProvider).selected!;
    final offer = c.read(resumeOffersProvider)[reopened.focusedPaneId];
    expect(offer?.kind, AgentKind.gemini);
    expect(offer?.session, 'g-1');
    expect(rig.local.views[reopened.focusedPaneId]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
