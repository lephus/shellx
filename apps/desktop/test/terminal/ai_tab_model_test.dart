import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' show LocalSessions;
import 'package:shellx_core/shellx_core.dart' show DriverSide;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  TerminalTabsState tabs() => c.read(terminalTabsProvider);
  TerminalTab tabById(int id) => tabs().tabs.firstWhere((t) => t.id == id);

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // session 100
  });

  test('an AI tab: synthetic id, one negative AI leaf, selected (D2, D3)', () {
    final tab = openTestAiTab(c, title: 'Fix login');
    expect(tab.id, greaterThanOrEqualTo(kSyntheticTabIdBase));
    expect(tab.isAi, isTrue);
    expect(tab.ai!.id, lessThan(0));
    expect(isAiPaneId(tab.ai!.id), isTrue);
    expect(tab.layout, PaneLeaf(tab.ai!.id));
    expect(tab.panes, isEmpty);
    expect(tab.paneOrder, [tab.ai!.id]);
    expect(tab.paneCount, 1);
    expect(tab.isSplit, isFalse);
    expect(tabs().selectedId, tab.id);
    expect(tabs().tabOfPane(tab.ai!.id)?.id, tab.id);
    expect(tabs().tabOfSession(tab.ai!.id), isNull);
  });

  test('getters of a tab without a terminal pane are null or empty (D2)', () {
    final tab = openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    expect(tab.focused, isNull);
    expect(tab.label, 'Fix login');
    expect(tab.automaticLabel, 'Fix login');
    expect(tab.cwd, '/w/shop');
    expect(tab.terminal, isNull);
    expect(tab.selection, isNull);
    expect(tab.runningCommand, isFalse);
    expect(tab.exitCode, isNull);
    expect(tab.exited, isFalse);
    expect(tab.gitBranch, isNull);
    expect(tab.ports, isEmpty);
    expect(tab.hasContext, isFalse);
    expect(tab.driver, DriverSide.desktop);
    expect(tab.noticeLabel(tab.ai!.id), 'Fix login');
    expect(tab.ai.toString(), '…');
  });

  test('ids never repeat; a custom name wins over the session title', () {
    final a = openTestAiTab(c);
    final b = openTestAiTab(c, select: false);
    expect(b.id, isNot(a.id));
    expect(b.ai!.id, lessThan(a.ai!.id));
    expect(tabs().selectedId, a.id, reason: 'select: false keeps it');
    c.read(terminalTabsProvider.notifier).rename(a.id, 'Mine');
    expect(tabById(a.id).label, 'Mine');
  });

  test('updateAiPane changes title, folder and session, and only then', () {
    final tab = openTestAiTab(c, cwd: null);
    final paneId = tab.ai!.id;
    final before = tabs();
    c.read(terminalTabsProvider.notifier).updateAiPane(paneId, (p) => p);
    expect(identical(tabs(), before), isTrue);
    c
        .read(terminalTabsProvider.notifier)
        .updateAiPane(
          paneId,
          (p) => p.copyWith(title: 'Login bug', cwd: '/w', sessionId: 's-1'),
        );
    final ai = tabById(tab.id).ai!;
    expect([ai.title, ai.cwd, ai.sessionId], ['Login bug', '/w', 's-1']);
    expect(tabById(tab.id).label, 'Login bug');
  });

  test('focusPane reaches the AI pane; pane moves refuse AI tabs (D3)', () {
    final ai = openTestAiTab(c);
    final notifier = c.read(terminalTabsProvider.notifier);
    notifier.select(100);
    notifier.focusPane(ai.ai!.id);
    expect(tabs().selectedId, ai.id, reason: 'as for a terminal pane');
    expect(tabById(ai.id).focusedPaneId, ai.ai!.id);
    expect(notifier.joinPane(100, ai.id), isFalse);
    expect(notifier.breakPane(ai.ai!.id), isFalse);
  });

  test('the Terminal button adds one pane under the AI pane, 72 % above; '
      'closing it keeps the tab (D3)', () async {
    final ai = openTestAiTab(c, cwd: '/w/shop');
    final notifier = c.read(terminalTabsProvider.notifier);
    final term = await notifier.addAiTerminal(ai.id);
    var tab = tabById(ai.id);
    expect(tab.isSplit, isTrue);
    expect(tab.paneCount, 2);
    final split = tab.layout as PaneSplit;
    expect(split.axis, SplitAxis.column);
    expect(split.ratio, closeTo(kAiPaneRatio, 0.001));
    expect(split.first, PaneLeaf(ai.ai!.id));
    expect(split.second, PaneLeaf(term));
    expect(tab.focused?.id, term);
    expect(local.openCwds.last, '/w/shop');
    expect(local.openTabIds.last, ai.id);
    expect(await notifier.addAiTerminal(ai.id), term, reason: 'one only');
    notifier.closePane(term);
    tab = tabById(ai.id);
    expect(tab.panes, isEmpty);
    expect(tab.layout, PaneLeaf(ai.ai!.id));
    expect(tab.focusedPaneId, ai.ai!.id);
  });

  test('AI tabs outlive a rebuild of the tab list (Review Focus 3)', () async {
    // A new background-service link is a new LocalSessions: the tab list
    // rebuilds from its sessions.
    final first = FakeLocalSessions();
    final link = NotifierProvider<_Link, LocalSessions>(() => _Link(first));
    final r = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWith((ref) => ref.watch(link)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    await r.read(terminalTabsProvider.notifier).openTab();
    final ai = openTestAiTab(r, title: 'Kept');
    await r.read(terminalTabsProvider.notifier).addAiTerminal(ai.id);
    r.read(link.notifier).set(FakeLocalSessions());
    final again = r.read(terminalTabsProvider);
    final kept = again.tabs.where((t) => t.id == ai.id).single;
    expect(kept.ai!.title, 'Kept');
    expect(kept.panes, isEmpty, reason: 'the old sessions are gone');
    expect(kept.layout, PaneLeaf(ai.ai!.id));
    expect(again.selectedId, ai.id);
  });

  test('closing an AI tab removes it', () {
    final ai = openTestAiTab(c);
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(tabs().tabs.any((t) => t.id == ai.id), isFalse);
  });
}

class _Link extends Notifier<LocalSessions> {
  _Link(this.first);
  final LocalSessions first;

  @override
  LocalSessions build() => first;

  void set(LocalSessions next) => state = next;
}
