import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/browser/browser_controller.dart';
import 'package:shellx_desktop/src/browser/browser_url.dart';
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

Matcher browserError(String code) =>
    isA<BrowserError>().having((e) => e.code, 'code', code);

void main() {
  setUp(() => local = FakeLocalSessions());

  test('openBrowser splits right of the focused pane with a negative id, '
      'at the smallest port of the active terminal (D4, D7)', () {
    local.add(local.summary(1, ports: [5173, 3000]));
    boot();
    final id = tabs().openBrowser();
    expect(id, -1);
    expect(isBrowserPaneId(id), isTrue);
    final tab = state().tabs.single;
    expect(
      tab.layout,
      const PaneSplit(
        axis: SplitAxis.row,
        ratio: 0.5,
        first: PaneLeaf(1),
        second: PaneLeaf(-1),
      ),
    );
    expect(tab.focusedPaneId, -1);
    expect(tab.browsers[-1]!.url.toString(), 'http://localhost:3000/');
    expect(tab.panes.keys, [1]); // never a session
    expect(state().tabOfPane(-1), same(tab));
    expect(state().tabOfSession(-1), isNull);
    expect(tabs().openBrowser(), -2); // ids never reused
  });

  test('no port → about:blank; explicit URL and target honoured', () {
    local.add(local.summary(1));
    boot();
    final a = tabs().openBrowser();
    expect(state().tabs.single.browsers[a]!.url, aboutBlank);
    final b = tabs().openBrowser(
      target: 1,
      url: Uri.parse('http://localhost:8000/docs'),
      axis: SplitAxis.column,
      focus: false,
    );
    final tab = state().tabs.single;
    expect(
      tab.focusedPaneId,
      a,
    ); // focus: false keeps the keyboard where it was
    expect(tab.browsers[b]!.url.toString(), 'http://localhost:8000/docs');
    expect(paneIds(tab.layout), [1, b, a]);
  });

  test(
    'getters follow the active terminal pane while a browser is focused (D6)',
    () {
      local.add(local.summary(1, title: 'vim', cwd: '/w'));
      boot();
      tabs().openBrowser();
      final tab = state().tabs.single;
      expect(tab.focusedPaneId, -1);
      expect(tab.activeTerminalPane.id, 1);
      expect(tab.label, 'vim');
      expect(tab.cwd, '/w');
      expect(tab.paneCount, 2);
    },
  );

  test('limit of 8 browser panes (D28) and no room (D31) → notice + error', () {
    local.add(local.summary(1));
    boot();
    for (var i = 0; i < kMaxBrowserPanes; i++) {
      tabs().openBrowser(target: 1);
    }
    expect(() => tabs().openBrowser(), throwsA(browserError('browser_limit')));
    expect(state().notice, isA<BrowserLimitNotice>());
    expect(state().browserCount, 8);

    local = FakeLocalSessions();
    local.add(local.summary(1));
    boot();
    tabs().reportPaneMetrics(
      const PaneMetrics(
        area: Size(400, 600),
        minPane: Size(170, 112),
        divider: 1,
      ),
    );
    expect(() => tabs().openBrowser(), throwsA(browserError('no_room')));
    expect(state().notice, isA<PaneNoRoomNotice>());
    expect(state().tabs.single.browsers, isEmpty);
  });

  test('agent opens (notify: false) raise no notice', () {
    local.add(local.summary(1));
    boot();
    for (var i = 0; i < kMaxBrowserPanes; i++) {
      tabs().openBrowser(target: 1, notify: false);
    }
    expect(
      () => tabs().openBrowser(notify: false),
      throwsA(browserError('browser_limit')),
    );
    expect(state().notice, isNull);
  });

  test('closing a browser pane: MRU focus, no session closed', () {
    local.add(local.summary(1));
    boot();
    final id = tabs().openBrowser();
    tabs().closePane(id);
    final tab = state().tabs.single;
    expect(tab.browsers, isEmpty);
    expect(tab.layout, const PaneLeaf(1));
    expect(tab.focusedPaneId, 1);
    expect(local.closed, isEmpty);
  });

  test('D5: the last terminal pane exiting 0 stays (exit line) while a '
      'browser pane is there; Enter then closes the whole tab', () async {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    local.views[1]!.end(0);
    await pumpEventQueue();
    final tab = state().tabs.single;
    expect(tab.panes[1]!.exitCode, 0);
    expect(tab.panes[1]!.exited, isTrue);
    expect(tab.browsers.keys, [-1]);
    tab.panes[1]!.terminal.keyInput(TerminalKey.enter);
    expect(state().tabs, isEmpty);
  });

  test(
    'D5: closing the last terminal pane closes the tab with its browsers',
    () {
      local.add(local.summary(1));
      boot();
      tabs().openBrowser();
      tabs().closePane(1);
      expect(local.closed, [1]);
      expect(state().tabs, isEmpty);
    },
  );

  test('a second terminal pane exiting 0 still goes away (A3 D7)', () async {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    await tabs().split(
      SplitAxis.column,
    ); // from the browser pane: new terminal 100
    local.views[100]!.end(0);
    await pumpEventQueue();
    expect(state().tabs.single.panes.keys, [1]);
  });

  test('splitting a terminal from a focused browser pane uses the active '
      'terminal cwd (D6)', () async {
    local.add(local.summary(1, cwd: '/w/app'));
    boot();
    tabs().openBrowser();
    await tabs().split(SplitAxis.row);
    expect(local.openCwds.last, '/w/app');
  });

  test(
    'focusPane selects the tab of a browser pane; updateBrowser stores state',
    () {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      final id = tabs().openBrowser(tabId: 1, focus: false);
      tabs().select(2);
      tabs().focusPane(id);
      expect(state().selectedId, 1);
      expect(state().tabs.first.focusedPaneId, id);
      tabs().updateBrowser(
        id,
        BrowserPaneState(url: Uri.parse('http://localhost/'), title: 'Hi'),
      );
      expect(state().tabs.first.browsers[id]!.title, 'Hi');
    },
  );

  test('a browser pane never gets a resize or a view (D31, D4)', () {
    local.add(local.summary(1));
    boot();
    tabs().openBrowser();
    tabs().toggleZoom();
    tabs().toggleZoom();
    expect(local.views.keys, [1]);
    expect(local.viewRequests.where((id) => id < 0), isEmpty);
  });
}
