import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/mux/daemon_host.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../mux/fake_daemon.dart';
import '../support/fakes.dart';
import '../support/restore_fakes.dart';

/// A5b D14, UI-A5 §6, §7.1, §7.2: "Thoát" leaves the shells running, "Thoát
/// hoàn toàn" ends the background service.
void main() {
  late TestHarness h;
  late RecordingFiles files;
  late FakeConnector connector;
  late FakeDaemon daemon;
  late ProviderContainer c;

  Future<void> boot({
    List<int> ids = const [1, 2],
    DevicePlatform platform = DevicePlatform.macos,
  }) async {
    h = TestHarness(platform: platform);
    files = RecordingFiles()..diskLayout = true;
    connector = FakeConnector()..files = files;
    daemon = FakeDaemon('a' * 32, ids: ids);
    c = ProviderContainer.test(
      overrides: [
        daemonModeProvider.overrideWithValue(true),
        desktopServicesProvider.overrideWithValue(h.services()),
        restoreStoreProvider.overrideWithValue(files),
        daemonConnectorProvider.overrideWithValue(connector),
      ],
    );
    c.read(sidebarWorkspacesProvider);
    c.read(restorePersistenceProvider.notifier).start();
    connector.queue.add(() async => daemon.attach());
    await c.read(daemonStateProvider.notifier).connectAtStartup();
    await pumpEventQueue();
  }

  ConfirmRequest? asked() => c.read(windowRouterProvider).confirm;
  Future<void> run(TrayAction a) => c.read(trayActionsProvider).handle(a);
  bool explained() =>
      h.settings.values[SettingKeys.quitKeepsSessionsExplained] == true;

  /// A pending dialog answered like the buttons do.
  Future<void> answer({bool primary = false, bool secondary = false}) async {
    await pumpEventQueue();
    final request = asked()!;
    if (secondary) {
      request.completeSecondary();
    } else {
      request.complete(primary);
    }
    await pumpEventQueue();
  }

  group('"Thoát" / ⌘Q', () {
    test('with sessions, the first time: the explanation (§7.1); '
        '"Quit" saves clean, never asks the service to quit, then exits; '
        'the key is set', () async {
      await boot();
      final done = run(const Quit());
      await pumpEventQueue();
      final request = asked()!;
      expect(request.title, 'Your shells keep running');
      expect(request.body, contains('2 tabs keep running'));
      expect(request.body, contains('⌥⌘Q'));
      expect(request.confirmLabel, 'Quit');
      expect(request.secondaryLabel, 'Quit Completely');
      expect(h.quits, 0);
      request.complete(true);
      await done;
      expect(explained(), isTrue);
      expect(files.layouts.last.cleanExit, isTrue);
      expect(files.layouts.last.daemon, 'a' * 32);
      expect(daemon.quits, 0);
      expect(h.quits, 1);
      expect(h.imageDeletes, 0, reason: 'the service keeps the shells');
      expect(h.shutdownOrder, ['retries', 'remote', 'quit']);
    });

    test('the second time: no dialog at all, exits at once', () async {
      await boot();
      h.settings.values[SettingKeys.quitKeepsSessionsExplained] = true;
      await run(const Quit());
      expect(asked(), isNull);
      expect(h.quits, 1);
      expect(daemon.quits, 0);
    });

    test('with no session: no dialog', () async {
      await boot(ids: const []);
      await run(const Quit());
      expect(asked(), isNull);
      expect(h.quits, 1);
    });

    test(
      'Esc on the explanation stays: nothing exits, the key is not set',
      () async {
        await boot();
        final done = run(const Quit());
        await answer();
        await done;
        expect(h.quits, 0);
        expect(explained(), isFalse);
        expect(files.layouts.where((l) => l.cleanExit), isEmpty);
      },
    );

    test('Windows: the body names the tray menu, not ⌥⌘Q', () async {
      await boot(platform: DevicePlatform.windows);
      unawaited(run(const Quit()));
      await pumpEventQueue();
      expect(asked()!.body, contains('tray menu'));
      expect(asked()!.body, isNot(contains('⌥⌘Q')));
    });

    test('Quit(confirm: false) (Restart Manager): never asks', () async {
      await boot();
      await run(const Quit(confirm: false));
      expect(asked(), isNull);
      expect(h.quits, 1);
      expect(files.layouts.last.cleanExit, isTrue);
    });

    test('the explanation\'s "Quit Completely" goes on to the confirm; the '
        'key is set either way', () async {
      await boot();
      final done = run(const Quit());
      await answer(secondary: true);
      // The A1 confirm of "Thoát hoàn toàn" follows.
      final confirm = asked()!;
      expect(confirm.title, 'Quit ShellX?');
      expect(confirm.confirmLabel, 'Quit Completely');
      expect(explained(), isTrue);
      confirm.complete(false);
      await done;
      expect(h.quits, 0);
      expect(daemon.quits, 0);
    });
  });

  group('"Thoát hoàn toàn"', () {
    test('with sessions: the A1 confirm; yes saves clean, asks the service '
        'to quit, then exits', () async {
      await boot();
      final done = run(const QuitAll());
      await pumpEventQueue();
      final confirm = asked()!;
      expect(confirm.title, 'Quit ShellX?');
      expect(confirm.confirmLabel, 'Quit Completely');
      expect(confirm.body, contains('2 open tabs'));
      confirm.complete(true);
      await done;
      expect(files.layouts.last.cleanExit, isTrue);
      expect(daemon.quits, 1);
      expect(h.quits, 1);
      expect(h.imageDeletes, 1, reason: 'the shells really end');
      expect(h.shutdownOrder.first, 'retries');
      expect(h.shutdownOrder.last, 'quit');
    });

    test('cancel does nothing', () async {
      await boot();
      final done = run(const QuitAll());
      await answer();
      await done;
      expect(daemon.quits, 0);
      expect(h.quits, 0);
      expect(files.layouts.where((l) => l.cleanExit), isEmpty);
    });

    test('with no session: no question', () async {
      await boot(ids: const []);
      await run(const QuitAll());
      expect(asked(), isNull);
      expect(daemon.quits, 1);
      expect(h.quits, 1);
    });

    test('a service that does not stop: the window stays open, says so, saving '
        'is not left frozen, and the stopping state is gone', () async {
      await boot(ids: const [1]);
      daemon.onQuit = () => throw StateError('stuck');
      final done = run(const QuitAll());
      await answer(primary: true);
      await done;
      expect(h.quits, 0);
      expect(h.imageDeletes, 0, reason: 'the shells still run');
      expect(
        c.read(terminalTabsProvider).notice,
        isA<DaemonQuitFailedNotice>(),
      );
      expect(c.read(daemonStateProvider).strip, isNull);
      final before = files.layouts.length;
      c
          .read(terminalTabsProvider.notifier)
          .rename(c.read(terminalTabsProvider).tabs.first.id, 'after');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(files.layouts.length, greaterThan(before));
      expect(files.layouts.last.cleanExit, isFalse);
    });

    test('while the service stops the window shows it, and a second click '
        'does nothing', () async {
      await boot(ids: const []);
      final gate = Completer<void>();
      daemon.onQuit = () => gate.future;
      final first = run(const QuitAll());
      await pumpEventQueue();
      expect(c.read(daemonStateProvider).strip, DaemonStrip.stopping);
      await run(const QuitAll());
      expect(daemon.quits, 1);
      gate.complete();
      await first;
      expect(h.quits, 1);
    });

    test('the wait for the service covers its own shutdown budget', () {
      expect(
        kDaemonQuitWait,
        greaterThanOrEqualTo(
          kDaemonShutdownBudget + const Duration(seconds: 3),
        ),
      );
    });

    test('a service that dies as it quits is no restart', () async {
      await boot(ids: const []);
      daemon.onQuit = () => daemon.die();
      await run(const QuitAll());
      expect(connector.connects, 1);
      expect(h.quits, 1);
    });
  });

  test('in-process (switch off): "Quit Completely" is just Quit, with the '
      'A1 confirm', () async {
    h = TestHarness();
    final c2 = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    await h.sessions.open(cols: 80, rows: 24);
    final done = c2.read(trayActionsProvider).handle(const QuitAll());
    await pumpEventQueue();
    final confirm = c2.read(windowRouterProvider).confirm!;
    expect(confirm.title, 'Quit ShellX?');
    confirm.complete(true);
    await done;
    expect(h.quits, 1);
    expect(h.imageDeletes, 1, reason: 'in-process: the shells end with it');
  });
}
