import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:xterm/xterm.dart' show TerminalKey;

import '../support/fake_local_sessions.dart';

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
    ],
  );
  state();
}

void main() {
  setUp(() => local = FakeLocalSessions());

  test('a session becomes a one-pane tab that reads like A2 (D1, D2)', () {
    local.add(local.summary(1, title: 'vim', cwd: '/Users/test/w'));
    boot();
    final tab = state().tabs.single;
    expect(tab.id, 1);
    expect(tab.layout, const PaneLeaf(1));
    expect(tab.paneOrder, [1]);
    expect(tab.focusedPaneId, 1);
    expect(tab.isSplit, isFalse);
    expect(tab.label, 'vim');
    expect(tab.cwd, '/Users/test/w');
    expect(identical(tab.terminal, tab.panes[1]!.terminal), isTrue);
    expect(state().tabOfSession(1), same(tab));
    expect(state().tabOfSession(2), isNull);
  });

  test('summary changes update the pane inside its tab', () {
    local.add(local.summary(1));
    boot();
    local.replace(local.summary(1, title: 'htop', runningCommand: true));
    expect(state().tabs.single.panes[1]!.title, 'htop');
    expect(state().tabs.single.runningCommand, isTrue);
    expect(tabs().runningPaneCount(1), 1);
    expect(tabs().needsCloseConfirm(1), isTrue);
    expect(tabs().needsPaneCloseConfirm(1), isTrue);
  });

  test('D5: a desktop session that appears while an open is pending waits '
      'for the opener; a phone session does not', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    local.openGate = Completer<void>();
    final opening = tabs().openTab();
    local.add(local.summary(7, origin: SessionOrigin.desktop));
    local.add(local.summary(8)); // phone
    expect(state().tabs.map((t) => t.id), [1, 8]);
    local.openGate!.complete();
    await opening;
    expect(state().tabs.map((t) => t.id), [1, 8, 7, 100]);
    expect(state().selectedId, 100);
  });

  test('close(tab) closes every pane session and removes the tab', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().close(1);
    expect(local.closed, [1]);
    expect(state().tabs.map((t) => t.id), [2]);
  });

  test('closePane on a one-pane tab closes the tab (D6)', () {
    local.add(local.summary(1));
    boot();
    tabs().closePane(1);
    expect(local.closed, [1]);
    expect(state().tabs, isEmpty);
  });

  test('a non-zero exit keeps the tab; Enter closes it (A1 D14)', () async {
    local.add(local.summary(1));
    boot();
    local.views[1]!.end(3);
    await pumpEventQueue();
    expect(state().tabs.single.exited, isTrue);
    expect(state().tabs.single.panes[1]!.exitCode, 3);
    state().tabs.single.terminal.keyInput(TerminalKey.enter);
    expect(state().tabs, isEmpty);
  });
}
