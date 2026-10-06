import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;

  TerminalTabs tabs() => container.read(terminalTabsProvider.notifier);
  TerminalTabsState state() => container.read(terminalTabsProvider);
  String text(int id) =>
      state().tabs.firstWhere((t) => t.id == id).terminal.buffer.getText();

  void boot() {
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
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
    terminal.textInput('ls');
    terminal.write('\x1b[6n');
    expect(local.views[1]!.writes, ['ls']);
    expect(local.views[1]!.replies, hasLength(1));
  });

  test('layout size goes to resize', () {
    local.add(local.summary(1));
    boot();
    local.views[1]!.resizes.clear();
    state().tabs.single.terminal.resize(90, 30);
    expect(local.views[1]!.resizes, [(90, 30)]);
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

      tab.terminal.textInput('x');
      expect(state().tabs, hasLength(2));
      expect(local.views[2]!.writes, isEmpty);
      tab.terminal.textInput('\r');
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
}
