import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../support/fake_local_sessions.dart';

/// A10 D20: what the PTY is told while a window or a divider is dragged.
/// The container keeps the production settle time (80 ms).
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

  test('120 grid changes in two seconds make one resize of the session', () {
    fakeAsync((async) {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      boot();
      final view = local.views[1]!;
      final terminal = state().tabs.single.terminal;
      final before = view.resizes.length;
      for (var i = 0; i < 120; i++) {
        terminal!.resize(80 + i % 30, 24);
        if (i < 119) async.elapse(const Duration(milliseconds: 16));
      }
      expect(view.resizes.length, before, reason: 'nothing mid-drag');
      async.elapse(const Duration(milliseconds: 79));
      expect(view.resizes.length, before);
      async.elapse(const Duration(milliseconds: 1));
      expect(view.resizes.length, before + 1);
      expect(view.resizes.last, (80 + 119 % 30, 24));
    });
  });

  test('the xterm grid follows at once; only the session waits', () {
    fakeAsync((async) {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      boot();
      final terminal = state().tabs.single.terminal;
      terminal!.resize(132, 43);
      expect((terminal.viewWidth, terminal.viewHeight), (132, 43));
    });
  });

  test(
    'a key typed right after a resize reaches a PTY that has the new size',
    () {
      fakeAsync((async) {
        local.add(local.summary(1, origin: SessionOrigin.desktop));
        boot();
        final view = local.views[1]!;
        final terminal = state().tabs.single.terminal;
        final before = view.resizes.length;
        terminal!.resize(100, 30);
        expect(view.resizes.length, before);
        terminal.textInput('x');
        expect(view.resizes.length, before + 1, reason: 'sent before the key');
        expect(view.resizes.last, (100, 30));
        expect(view.writes.last, 'x');
      });
    },
  );

  test('flushResizes sends what waits, once', () {
    fakeAsync((async) {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      boot();
      final view = local.views[1]!;
      final before = view.resizes.length;
      state().tabs.single.terminal!.resize(90, 20);
      tabs().flushResizes();
      tabs().flushResizes();
      async.elapse(const Duration(seconds: 1));
      expect(view.resizes.length, before + 1);
    });
  });

  test('a pane that ends with a size waiting never gets it', () {
    fakeAsync((async) {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      boot();
      final view = local.views[1]!;
      final before = view.resizes.length;
      state().tabs.single.terminal!.resize(90, 20);
      view.end(3);
      async.elapse(const Duration(seconds: 1));
      expect(view.resizes.length, before);
    });
  });

  test(
    'a hidden tab is not told; coming to the front it hears its size now',
    () {
      fakeAsync((async) {
        local.add(local.summary(1, origin: SessionOrigin.desktop));
        local.add(local.summary(2, origin: SessionOrigin.desktop));
        boot();
        tabs().reportGrid((cols: 80, rows: 24));
        final hidden = state().tabs.last; // tab 2: not selected
        expect(state().selectedId, 1);
        final view = local.views[2]!;
        final before = view.resizes.length;
        hidden.terminal!.resize(111, 33);
        async.elapse(const Duration(seconds: 1));
        expect(view.resizes.length, before, reason: 'never while hidden');
        tabs().select(2);
        expect(view.resizes.last, (111, 33));
      });
    },
  );

  test(
    'closing the tab drops its waiting size and disposing the notifier is safe',
    () {
      fakeAsync((async) {
        local.add(local.summary(1, origin: SessionOrigin.desktop));
        boot();
        state().tabs.single.terminal!.resize(90, 20);
        tabs().close(1);
        container.dispose();
        async.elapse(
          const Duration(seconds: 1),
        ); // no timer fires into a dead notifier
      });
    },
  );

  test('a split: both visible panes settle independently', () async {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    boot();
    tabs().reportPaneMetrics(
      const PaneMetrics(
        area: Size(1000, 600),
        minPane: Size(120, 80),
        divider: 1,
        devicePixelRatio: 1,
      ),
    );
    await tabs().split(SplitAxis.row);
    final tab = state().selected!;
    final ids = tab.paneOrder;
    expect(ids, hasLength(2));
    fakeAsync((async) {
      final a = local.views[ids[0]]!;
      final b = local.views[ids[1]]!;
      final beforeA = a.resizes.length;
      final beforeB = b.resizes.length;
      tab.panes[ids[0]]!.terminal.resize(70, 20);
      async.elapse(const Duration(milliseconds: 40));
      tab.panes[ids[1]]!.terminal.resize(60, 20);
      async.elapse(const Duration(milliseconds: 41));
      expect(a.resizes.length, beforeA + 1, reason: 'its own 80 ms are over');
      expect(b.resizes.length, beforeB, reason: 'still waiting');
      async.elapse(const Duration(milliseconds: 40));
      expect(b.resizes.length, beforeB + 1);
    });
  });
}
