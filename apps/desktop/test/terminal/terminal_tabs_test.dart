import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;

  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  TerminalTabsState state() => container.read(terminalTabsProvider);
  String text(int id) =>
      state().tabs.firstWhere((t) => t.id == id).terminal!.buffer.getText();

  void boot({AppLocalizations? l10n}) {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        // A10 D20: these tests check layout, not settling: sizes go at once.
        resizeSettleProvider.overrideWithValue(Duration.zero),
        appL10nProvider.overrideWithValue(
          l10n ?? lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    state(); // build
  }

  setUp(() => local = FakeLocalSessions());

  test(
    'sessions become tabs in creation order; backlog is written first',
    () async {
      local.add(local.summary(1), backlog: 'hello');
      local.add(local.summary(2, title: 'vim'));
      boot();
      expect(state().tabs.map((t) => t.id), [1, 2]);
      expect(text(1), contains('hello'));
      local.views[1]!.emit(' world');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(text(1), contains('hello world'));
    },
  );

  test('the title falls back to "<shell> <index>" (D13)', () {
    local.add(local.summary(1));
    local.add(local.summary(2, title: 'htop'));
    boot();
    expect(state().tabs.map((t) => t.label), ['zsh 1', 'htop']);
  });

  test('openTab opens at the last measured grid and selects the tab', () async {
    boot();
    tabs().reportGrid((cols: 120, rows: 40));
    await tabs().openTab();
    expect(local.opens, [(120, 40)]);
    expect(state().selectedId, 100);
    expect(state().selected!.origin, SessionOrigin.desktop);
    expect(state().opening, isFalse);
  });

  test('a second openTab while one is in flight is ignored', () async {
    boot();
    local.openGate = Completer<void>();
    final first = tabs().openTab();
    expect(state().opening, isTrue);
    await tabs().openTab();
    local.openGate!.complete();
    await first;
    expect(local.opens, hasLength(1));
  });

  test('a tab opened from the phone is appended and not selected', () async {
    boot();
    await tabs().openTab();
    local.add(local.summary(7));
    await pumpEventQueue();
    expect(state().tabs.map((t) => t.id), [100, 7]);
    expect(state().selectedId, 100);
  });

  test(
    'with nothing selected, the first tab that appears is selected',
    () async {
      boot();
      local.add(local.summary(7));
      await pumpEventQueue();
      expect(state().selectedId, 7);
    },
  );

  test('the session limit becomes a notice and no tab', () async {
    boot();
    local.openError = const SessionLimitException(32);
    await tabs().openTab();
    expect(state().tabs, isEmpty);
    expect(state().notice, isA<SessionLimitNotice>());
    expect((state().notice! as SessionLimitNotice).max, 32);
    tabs().dismissNotice();
    expect(state().notice, isNull);
  });

  test('spawn failures are classified for the toast', () async {
    boot();
    local.openError = const SpawnFailedException(
      'ProcessException: No such file or directory',
    );
    await tabs().openTab();
    expect((state().notice! as SpawnFailedNotice).kind, SpawnFailure.notFound);
    expect(
      spawnFailureOf('Permission denied (errno = 13)'),
      SpawnFailure.denied,
    );
    expect(spawnFailureOf('Bad state: boom'), SpawnFailure.other);
  });

  test('typing goes to write, emulator answers go to reply', () {
    local.add(local.summary(1));
    boot();
    final terminal = state().tabs.single.terminal;
    terminal!.textInput('ls');
    terminal.write('\x1b[6n');
    expect(local.views[1]!.writes, ['ls']);
    expect(local.views[1]!.replies, hasLength(1));
  });

  test('a backlog that arrives late (a session in the daemon) is laid out '
      'first and its queries are answered into nothing (A5b D10)', () async {
    local.add(local.summary(1));
    final late = Completer<Uint8List>();
    local.views[1]!.lateBacklog = late;
    boot();
    final terminal = state().tabs.single.terminal;
    late.complete(Uint8List.fromList(utf8.encode('old\x1b[6n\x1b[c')));
    await pumpEventQueue();
    expect(terminal!.buffer.getText(), contains('old'));
    expect(local.views[1]!.replies, isEmpty);
    local.views[1]!.emit('new');
    await pumpEventQueue();
    expect(terminal.buffer.getText(), contains('oldnew'));
    terminal.write('\x1b[6n');
    expect(local.views[1]!.replies, hasLength(1));
  });

  test('a reset replay is shown but is not pane output (A5b D11)', () async {
    local.add(local.summary(1));
    boot();
    final seen = <int>[];
    final sub = tabs().paneOutputs.listen(seen.add);
    final terminal = state().tabs.single.terminal;
    local.views[1]!.replaying = true;
    local.views[1]!.emit('replayed');
    await pumpEventQueue();
    expect(terminal!.buffer.getText(), contains('replayed'));
    expect(seen, isEmpty);
    local.views[1]!.replaying = false;
    local.views[1]!.emit('live');
    await Future<void>.delayed(const Duration(milliseconds: 40)); // feed tick
    expect(seen, [1]);
    await sub.cancel();
  });

  test('a replay arriving while the feed timer is pending is still written '
      'held: no pane output, no reply (A5b D11)', () async {
    local.add(local.summary(1));
    boot();
    final seen = <int>[];
    final sub = tabs().paneOutputs.listen(seen.add);
    final terminal = state().tabs.single.terminal;
    local.views[1]!.emit('a'); // written at once, arms the feed timer
    await pumpEventQueue();
    expect(seen, [1]);
    local.views[1]!.replaying = true;
    local.views[1]!.emit('replayed\x1b[6n');
    await pumpEventQueue();
    local.views[1]!.replaying = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(terminal!.buffer.getText(), contains('replayed'));
    expect(seen, [1]);
    expect(local.views[1]!.replies, isEmpty);
    await sub.cancel();
  });

  test('a replay larger than the feed budget is written held too', () async {
    local.add(local.summary(1));
    boot();
    final seen = <int>[];
    final sub = tabs().paneOutputs.listen(seen.add);
    final terminal = state().tabs.single.terminal;
    local.views[1]!.replaying = true;
    local.views[1]!.emit('\x1b[6n${'z\r\n' * 120000}end');
    await pumpEventQueue();
    local.views[1]!.replaying = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(seen, isEmpty);
    expect(local.views[1]!.replies, isEmpty);
    expect(terminal!.buffer.getText(), contains('end'));
    await sub.cancel();
  });

  test('layout size goes to resize', () {
    local.add(local.summary(1));
    boot();
    local.views[1]!.resizes.clear();
    state().tabs.single.terminal!.resize(90, 30);
    expect(local.views[1]!.resizes, [(90, 30)]);
  });

  test('only the selected tab reports its layout size: a hidden tab the '
      'phone drives keeps the phone driver until it is selected', () {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2)); // phone-origin, the phone drives
    boot();
    expect(state().selectedId, 1);
    for (final view in local.views.values) {
      view.resizes.clear();
    }
    // The window grows: every mounted TerminalView lays out again.
    for (final tab in state().tabs) {
      tab.terminal!.resize(100, 30);
    }
    expect(local.views[1]!.resizes, [(100, 30)]);
    expect(local.views[2]!.resizes, isEmpty);

    tabs().select(2);
    expect(local.views[2]!.resizes, [(100, 30)]);
    // Re-selecting the first tab sends its (unchanged) size again; the
    // session ignores a size it already has.
    tabs().select(1);
    expect(local.views[1]!.resizes, [(100, 30), (100, 30)]);
  });

  test('a tab selected because its neighbour closed sends its size', () {
    local.add(local.summary(1, origin: SessionOrigin.desktop));
    local.add(local.summary(2));
    boot();
    for (final tab in state().tabs) {
      tab.terminal!.resize(90, 28);
    }
    local.views[2]!.resizes.clear();
    tabs().close(1);
    expect(state().selectedId, 2);
    expect(local.views[2]!.resizes, [(90, 28)]);
  });

  test('openTab always clears the busy flag, even on an unexpected '
      'error', () async {
    boot();
    local.openError = StateError('boom');
    await expectLater(tabs().openTab(), throwsStateError);
    expect(state().opening, isFalse);
    local.openError = null;
    await tabs().openTab();
    expect(local.opens, hasLength(2));
  });

  test('output keeps reaching a tab that is not selected (spec §5)', () async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    tabs().select(1);
    local.views[2]!.emit('background');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(text(2), contains('background'));
  });

  group('exit (D14)', () {
    test('exit 0 closes that tab and keeps the selection', () async {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      tabs().select(1);
      local.views[2]!.end(0);
      await pumpEventQueue();
      expect(state().tabs.map((t) => t.id), [1]);
      expect(state().selectedId, 1);
      expect(local.views[2]!.disposed, isTrue);
    });

    test('a non-zero exit writes the line into that tab; Enter closes it, '
        'other keys are ignored', () async {
      local.add(local.summary(1));
      local.add(local.summary(2));
      boot();
      tabs().select(1);
      local.views[2]!.emit('error: build failed');
      local.views[2]!.end(2);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final tab = state().tabs.firstWhere((t) => t.id == 2);
      expect(tab.exited, isTrue);
      expect(tab.exitCode, 2);
      expect(text(2), contains('error: build failed'));
      expect(text(2), contains('[Process exited with code 2]'));
      expect(state().selectedId, 1);

      tab.terminal!.textInput('x');
      expect(state().tabs, hasLength(2));
      expect(local.views[2]!.writes, isEmpty);
      tab.terminal!.textInput('\r');
      expect(state().tabs.map((t) => t.id), [1]);
    });

    test(
      'a tab closed on request disappears even with a non-zero code',
      () async {
        local.add(local.summary(1));
        boot();
        local.views[1]!.end(-15, onRequest: true);
        await pumpEventQueue();
        expect(state().tabs, isEmpty);
      },
    );
  });

  test('closing the selected tab kills it and selects its neighbour', () {
    local.add(local.summary(1));
    local.add(local.summary(2));
    local.add(local.summary(3));
    boot();
    tabs().select(2);
    tabs().close(2);
    expect(local.closed, [2]);
    expect(state().tabs.map((t) => t.id), [1, 3]);
    expect(state().selectedId, 3);
    tabs().close(3);
    expect(state().selectedId, 1);
    tabs().close(1);
    expect(state().selectedId, isNull);
  });

  test('closing asks only while a command runs (D15)', () {
    local.add(local.summary(1, runningCommand: true));
    local.add(local.summary(2));
    boot();
    expect(tabs().needsCloseConfirm(1), isTrue);
    expect(tabs().needsCloseConfirm(2), isFalse);
    local.replace(local.summary(1, runningCommand: false));
    expect(tabs().needsCloseConfirm(1), isFalse);
  });

  test('summary changes update the tab; driver changes arrive live', () {
    local.add(local.summary(1));
    boot();
    local.replace(local.summary(1, title: 'claude', attachedMobileId: 'm1'));
    expect(state().tabs.single.label, 'claude');
    expect(state().tabs.single.phoneAttached, isTrue);
    local.views[1]!.driverController.add(DriverSide.desktop);
    expect(state().tabs.single.driver, DriverSide.desktop);
  });

  test('next/previous wrap; selectIndex picks the n-th tab', () {
    for (final id in [1, 2, 3]) {
      local.add(local.summary(id));
    }
    boot();
    tabs().select(3);
    tabs().next();
    expect(state().selectedId, 1);
    tabs().previous();
    expect(state().selectedId, 3);
    tabs().selectIndex(2);
    expect(state().selectedId, 2);
    tabs().selectIndex(9); // no 9th tab: unchanged
    expect(state().selectedId, 2);
  });

  test('ensureTab opens exactly one tab only when there is none', () async {
    boot();
    await Future.wait([tabs().ensureTab(), tabs().ensureTab()]);
    expect(local.opens, hasLength(1));
    await tabs().ensureTab();
    expect(local.opens, hasLength(1));
  });

  test('disposing the container disposes every view', () {
    local.add(local.summary(1));
    boot();
    container.dispose();
    expect(local.views[1]!.disposed, isTrue);
  });

  test('a new shell that is already gone leaves the selection alone', () async {
    local.add(local.summary(1));
    boot();
    local.afterOpen = (id) => local.views.remove(id); // view() throws
    await tabs().openTab();
    expect(state().tabs.map((t) => t.id), [1]);
    expect(state().selectedId, 1);
    expect(state().opening, isFalse);
  });

  test(
    'a new shell that is already gone, with no tabs, selects nothing',
    () async {
      boot();
      local.afterOpen = (id) => local.views.remove(id);
      await tabs().openTab();
      expect(state().tabs, isEmpty);
      expect(state().selectedId, isNull);
    },
  );

  test(
    'an exit line translated without the number is written uncoloured',
    () async {
      local.add(local.summary(1));
      boot(l10n: _NoNumberL10n());
      local.views[1]!.end(3);
      await pumpEventQueue();
      expect(state().tabs.single.exitCode, 3);
      expect(text(1), contains('Process exited'));
    },
  );

  test('close() on a running tab disposes its view', () {
    local.add(local.summary(1));
    boot();
    tabs().close(1);
    expect(local.closed, [1]);
    expect(local.views[1]!.disposed, isTrue);
  });

  test('a removed tab releases its selection controller', () async {
    local.add(local.summary(1));
    local.add(local.summary(2));
    boot();
    final first = state().tabs.first.selection;
    final second = state().tabs.last.selection;
    tabs().close(1);
    expect(_isDisposed(first!), isTrue);
    expect(_isDisposed(second!), isFalse);
    container.dispose();
    expect(_isDisposed(second), isTrue);
  });

  test('cwd, branch and ports follow the summary and stay after an exit '
      '(A2 C7)', () async {
    local.add(local.summary(1, cwd: '/w', gitBranch: 'main', ports: [3000]));
    boot();
    var tab = state().tabs.single;
    expect((tab.cwd, tab.gitBranch, tab.hasContext), ('/w', 'main', true));
    expect(tab.ports, [3000]);
    local.replace(local.summary(1, cwd: '/w/api'));
    tab = state().tabs.single;
    expect((tab.cwd, tab.gitBranch), ('/w/api', null));
    expect(tab.ports, isEmpty);
    local.views[1]!.end(2);
    await pumpEventQueue();
    expect(state().tabs.single.cwd, '/w/api');
  });

  test('rename: a name wins over the OSC title; blank restores it; at most '
      '64 characters (C6, D19)', () {
    local.add(local.summary(1, title: 'vim'));
    boot();
    tabs().rename(1, '  api server  ');
    expect(state().tabs.single.label, 'api server');
    local.replace(local.summary(1, title: 'htop'));
    expect(state().tabs.single.label, 'api server');
    expect(state().tabs.single.automaticLabel, 'htop');
    tabs().rename(1, '   ');
    expect(state().tabs.single.label, 'htop');
    tabs().rename(1, 'x' * 100);
    expect(state().tabs.single.label, 'x' * kTabNameMaxLength);
    tabs().rename(999, 'nobody'); // unknown id: nothing happens
  });

  test('showNotice replaces the current notice', () {
    boot();
    tabs().showNotice(const PortOpenFailedNotice());
    expect(state().notice, isA<PortOpenFailedNotice>());
    tabs().showNotice(
      const WorkspaceDeletedNotice(name: 'Ops', movedTo: 'Default'),
    );
    expect(state().notice, isA<WorkspaceDeletedNotice>());
  });
}

bool _isDisposed(ChangeNotifier notifier) {
  try {
    ChangeNotifier.debugAssertNotDisposed(notifier);
    return false;
  } on FlutterError {
    return true;
  }
}

final class _NoNumberL10n extends AppLocalizationsEn {
  @override
  String terminalExitedLine(int code) => '[Process exited] — press Enter';
}
