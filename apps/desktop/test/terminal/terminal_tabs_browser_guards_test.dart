import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/pane_moves.dart' as moves;
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

// A6 Task 5 rulings: what a browser leaf must not break in the rest of the
// pane code (layout counts, swaps, break/join, focus history, capture).

late FakeLocalSessions local;
late ProviderContainer container;

TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
TerminalTabsState state() => container.read(terminalTabsProvider);

void boot() {
  container = ProviderContainer.test(
    overrides: [
      localSessionsProvider.overrideWithValue(local),
      appL10nProvider.overrideWithValue(
        lookupAppLocalizations(const Locale('en')),
      ),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
    ],
  );
  state();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('isSplit and paneCount count the layout, not the sessions', () {
    local.add(local.summary(1));
    boot();
    expect(state().tabs.single.isSplit, isFalse);
    tabs().openBrowser();
    final tab = state().tabs.single;
    expect(tab.panes.length, 1);
    expect(tab.isSplit, isTrue);
    expect(tab.paneCount, 2);
    expect(tab.paneOrder, [1, -1]);
    expect(tab.paneNumber(-1), 2);
  });

  test('swapLeaves with a browser id keeps both leaves (no -1 temp id)', () {
    const t = PaneSplit(
      axis: SplitAxis.row,
      ratio: 0.5,
      first: PaneLeaf(1),
      second: PaneLeaf(-1),
    );
    expect(paneIds(moves.swapLeaves(t, 1, -1)), [-1, 1]);
    expect(paneIds(moves.swapLeaves(t, -1, 1)), [-1, 1]);
    const u = PaneSplit(
      axis: SplitAxis.row,
      ratio: 0.5,
      first: PaneLeaf(1),
      second: PaneSplit(
        axis: SplitAxis.column,
        ratio: 0.5,
        first: PaneLeaf(-1),
        second: PaneLeaf(-2),
      ),
    );
    expect(paneIds(moves.swapLeaves(u, -1, -2)), [1, -2, -1]);
    expect(paneIds(moves.swapLeaves(u, 1, -2)), [-2, -1, 1]);
  });

  test('a terminal pane swaps with its browser neighbour', () {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    expect(tabs().swapFocusedPane(PaneDirection.left), isTrue);
    final tab = state().tabs.single;
    expect(tab.paneOrder, [-1, 1]);
    expect(tab.focusedPaneId, -1);
    expect(tabs().canSwapFocusedPane(PaneDirection.right), isTrue);
  });

  test('a browser pane never breaks out; nor does the last terminal of a '
      'tab that has browsers (D5)', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().openBrowser(tabId: 1);
    expect(tabs().breakPane(-1), isFalse);
    expect(tabs().breakPane(1), isFalse);
    expect(tabs().joinPane(-1, 2), isFalse);
    expect(tabs().joinPane(1, 2), isFalse);
    expect(state().tabs.length, 2);
    expect(state().tabs.first.paneOrder, [1, -1]);
  });

  test('with two terminals and a browser a terminal may still move', () async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().openBrowser(tabId: 1);
    await tabs().split(SplitAxis.row); // 100 in the browser's tab
    expect(tabs().joinPane(100, 2), isTrue);
    expect(state().tabs.first.paneOrder, [1, -1]);
    expect(state().tabs.last.paneOrder, [2, 100]);
  });

  test('focus history walks back to a browser pane (alive via tabOfPane)', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    final history = container.read(focusHistoryProvider);
    tabs().select(1);
    final id = tabs().openBrowser(tabId: 1); // focused: -1
    tabs().select(2);
    expect(history.current, FocusEntry(2, 2));
    expect(
      container.read(focusHistoryProvider.notifier).go(back: true),
      isTrue,
    );
    expect(state().selectedId, 1);
    expect(state().tabs.first.focusedPaneId, id);
  });

  test('capture skips browser leaves and never asks keyOf for one', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().openBrowser(tabId: 1); // the browser is the focused pane
    final snapshot = captureSnapshot(
      tabs: state(),
      sidebar: container.read(sidebarWorkspacesProvider),
      keyOf: (id) {
        if (isBrowserPaneId(id)) fail('keyOf($id): that is a browser pane');
        return id.toRadixString(16).padLeft(32, '0');
      },
      now: DateTime.utc(2026),
      cleanExit: true,
    );
    expect(snapshot.tabs.length, 2);
    // The tab opens on its terminal; the browser leaf is not saved.
    expect(snapshot.tabs.first.layout, isA<SavedPane>());
  });

  test('closing a browser pane records nothing to reopen', () {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    tabs().closePane(id);
    expect(tabs().paneEnd(id), isNull);
  });
}
