import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/mux/daemon_launcher.dart';
import 'package:shellx_desktop/src/mux/daemon_state.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/fakes.dart';
import '../support/restore_fakes.dart';
import 'fake_daemon.dart';

void main() {
  late TestHarness h;
  late RecordingFiles files;
  late FakeConnector connector;
  late ProviderContainer c;
  late FakeDaemon first;

  Future<void> boot() async {
    h = TestHarness();
    files = RecordingFiles()..diskLayout = true;
    connector = FakeConnector()..files = files;
    first = FakeDaemon('a' * 32, ids: [1, 2]);
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
    connector.queue.add(() async => first.attach());
    final link = await c.read(daemonStateProvider.notifier).connectAtStartup();
    expect(link, isNotNull);
    await pumpEventQueue();
  }

  DaemonUiState ui() => c.read(daemonStateProvider);
  TerminalTabsState tabs() => c.read(terminalTabsProvider);

  String screen(TerminalTab tab) => [
    for (final pane in tab.panes.values)
      for (var i = 0; i < pane.terminal.buffer.lines.length; i++)
        pane.terminal.buffer.lines[i].getText(),
  ].join('\n');

  test(
    'attached: the sessions are the service\'s, the window waits no more',
    () async {
      await boot();
      expect(ui().waiting, isFalse);
      expect(c.read(localSessionsProvider).sessions.map((s) => s.id), [1, 2]);
      expect(tabs().tabs, hasLength(2));
    },
  );

  test(
    'the service dies: no exit line in any tab, the work is saved (not '
    'clean) before the restart, one connect, then the saved tabs are '
    'reopened in the new service without a duplicate (Review Focus 3)',
    () async {
      await boot();
      final second = FakeDaemon('b' * 32);
      final gate = Completer<DaemonConnection>();
      connector.queue.add(() => gate.future);

      await first.die();
      await pumpEventQueue();

      // Still showing the old tabs, with nothing written into them.
      expect(tabs().tabs, hasLength(2));
      for (final tab in tabs().tabs) {
        final text = screen(tab).toLowerCase();
        expect(text, isNot(contains('exited')));
        expect(text, isNot(contains('thoát')));
      }
      // Saved before the restart was asked for, and not as a clean end.
      expect(connector.connects, 2);
      expect(connector.layoutsAtConnect.last, greaterThan(0));
      expect(files.layouts.last.cleanExit, isFalse);
      expect(files.layouts.last.daemon, 'a' * 32);

      gate.complete(await second.attach());
      await pumpEventQueue();
      await pumpEventQueue();

      expect(connector.connects, 2);
      expect(ui().strip, DaemonStrip.restarted);
      expect(second.sessions.openCwds, ['/w1', '/w2']);
      expect(
        tabs().tabs,
        hasLength(2),
      ); // equal to the snapshot's: no duplicate
      // The restore found its own save "clean enough": no A5a abnormal strip.
      expect(c.read(restoreStripProvider), isNull);
      await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
      expect(files.layouts.last.daemon, 'b' * 32);
    },
  );

  test(
    'the restart fails: the lost strip with "Thử lại"; retrying works',
    () async {
      await boot();
      connector.queue.add(() async => const StartFailed());
      await first.die();
      await pumpEventQueue();
      expect(ui().strip, DaemonStrip.lost);
      expect(ui().retrying, isFalse);
      // The old tabs are not replaced by anything while there is no service.
      expect(tabs().tabs, hasLength(2));

      final second = FakeDaemon('b' * 32);
      final gate = Completer<DaemonConnection>();
      connector.queue.add(() => gate.future);
      final retry = c.read(daemonStateProvider.notifier).retry();
      await pumpEventQueue();
      expect(ui().retrying, isTrue);
      gate.complete(await second.attach());
      await retry;
      expect(ui().strip, DaemonStrip.restarted);
      expect(ui().retrying, isFalse);
      expect(second.sessions.openCwds, ['/w1', '/w2']);
    },
  );

  test(
    'keystrokes typed while the service is gone are dropped, not queued',
    () async {
      await boot();
      connector.queue.add(() async => const StartFailed());
      final view = first.sessions.views[1]!;
      await first.die();
      await pumpEventQueue();
      final pane = tabs().tabs.first.panes.values.first;
      expect(() => pane.terminal.onUserInput?.call('ls\r'), returnsNormally);
      await pumpEventQueue();
      expect(view.writes, isEmpty);
    },
  );

  test('a connection we closed ourselves is not a lost service', () async {
    await boot();
    final notifier = c.read(daemonStateProvider.notifier);
    await notifier.disconnect();
    await pumpEventQueue();
    expect(connector.connects, 1);
    expect(ui().strip, isNull);
  });

  test('daemon.quit answered: success, and no restart', () async {
    await boot();
    final answered = await c.read(daemonStateProvider.notifier).quitDaemon();
    expect(answered, isTrue);
    await pumpEventQueue();
    expect(connector.connects, 1);
    expect(ui().strip, isNull);
  });

  test('daemon.quit: a disconnect right after asking is success, and is '
      'not a service that died (no restart)', () async {
    await boot();
    first.onQuit = () => first.die();
    expect(await c.read(daemonStateProvider.notifier).quitDaemon(), isTrue);
    await pumpEventQueue();
    expect(connector.connects, 1);
  });

  test(
    'a service that answers the handshake but never lists its sessions is '
    'a failed start: the start-failed dialog, and Try Again can attach',
    () async {
      h = TestHarness();
      files = RecordingFiles()..diskLayout = true;
      connector = FakeConnector()..files = files;
      final broken = FakeDaemon('a' * 32);
      final fine = FakeDaemon('b' * 32, ids: [1]);
      c = ProviderContainer.test(
        overrides: [
          daemonModeProvider.overrideWithValue(true),
          desktopServicesProvider.overrideWithValue(h.services()),
          restoreStoreProvider.overrideWithValue(files),
          daemonConnectorProvider.overrideWithValue(connector),
        ],
      );
      connector.queue
        ..add(() async {
          final attached = await broken.attach();
          await broken.die(); // gone before the first list answer
          return attached;
        })
        ..add(() async => fine.attach());
      final started = c.read(daemonStateProvider.notifier).connectAtStartup();
      await pumpEventQueue();
      final dialog = c.read(windowRouterProvider).confirm!;
      expect(dialog.title, "Couldn't start the background service");
      expect(await dialog.onConfirm!(), isTrue);
      dialog.complete(true);
      final link = await started;
      expect(link, isNotNull);
      expect(link!.instance, 'b' * 32);
    },
  );
}
