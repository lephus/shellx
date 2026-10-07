import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/ssh_reconnector.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final devbox = SshTarget.parse('devbox')!;

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;
  late FakeAsync clock;

  void boot(FakeAsync async) {
    clock = async;
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        reconnectClockProvider.overrideWithValue(
          () => DateTime(2026, 10, 7, 9).add(clock.elapsed),
        ),
      ],
    );
    container.read(terminalTabsProvider);
    container.read(sshReconnectorProvider);
  }

  void add(int id, {bool connected = true}) => local.add(
    local.summary(
      id,
      origin: SessionOrigin.desktop,
      remote: SessionRemote(launch: SshLaunch(devbox), connected: connected),
    ),
  );

  void lose(FakeAsync async, int id, [int code = 255]) {
    local.summaries.removeWhere((s) => s.id == id);
    local.views[id]!.end(code);
    async.flushMicrotasks();
  }

  Map<int, RetryInfo> retries() => container.read(sshReconnectorProvider);

  setUp(() => local = FakeLocalSessions());

  test(
    'disconnected → 3 s, then 6 s after a failed attempt; connected clears (D20)',
    () {
      fakeAsync((async) {
        add(1);
        boot(async);
        lose(async, 1);
        expect(retries()[1]!.nextAt, DateTime(2026, 10, 7, 9, 0, 3));
        async.elapse(const Duration(seconds: 2));
        expect(local.openLaunches, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(local.openLaunches, [SshLaunch(devbox)]);
        final first = local.nextId - 1;
        expect(retries().containsKey(first), isTrue); // moved to the new id
        lose(async, first); // the retry never got through
        expect(retries()[first]!.attempt, 1);
        async.elapse(const Duration(seconds: 5));
        expect(local.openLaunches, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(local.openLaunches, hasLength(2));
        final second = local.nextId - 1;
        local.replace(
          local.summary(
            second,
            origin: SessionOrigin.desktop,
            remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
          ),
        );
        async.flushMicrotasks();
        expect(retries(), isEmpty);
      });
    },
  );

  test('failed (never connected) never retries by itself; Enter does', () {
    fakeAsync((async) {
      add(1, connected: false);
      boot(async);
      lose(async, 1);
      async.elapse(const Duration(minutes: 5));
      expect(local.openLaunches, isEmpty);
      container.read(sshReconnectorProvider.notifier).reconnectNow(1);
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
    });
  });

  test('gives up after 30 minutes (delays capped at 60 s)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      var current = 1;
      for (var i = 0; i < 60; i++) {
        final info = retries()[current];
        if (info == null || info.stopped) break;
        async.elapse(
          info.nextAt!.difference(DateTime(2026, 10, 7, 9).add(async.elapsed)),
        );
        current = local.nextId - 1;
        lose(async, current);
      }
      final info = retries()[current]!;
      expect(info.stopped, isTrue);
      expect(local.openLaunches.length, lessThanOrEqualTo(34));
      final n = local.openLaunches.length;
      async.elapse(const Duration(hours: 1));
      expect(local.openLaunches.length, n);
    });
  });

  test('wake retries at once; closing the pane cancels', () {
    fakeAsync((async) {
      add(1);
      add(2);
      boot(async);
      lose(async, 1);
      lose(async, 2);
      container.read(terminalTabsProvider.notifier).close(2);
      async.flushMicrotasks();
      container.read(sshReconnectorProvider.notifier).onWake();
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
      async.elapse(const Duration(minutes: 1));
      expect(local.openLaunches, hasLength(1));
    });
  });

  test(
    'Enter on a lost pane goes through the reconnector (strip shows it)',
    () {
      fakeAsync((async) {
        add(1);
        boot(async);
        lose(async, 1);
        final pane = container
            .read(terminalTabsProvider)
            .tabOfSession(1)!
            .panes[1]!;
        pane.terminal.onUserInput!('\r');
        expect(retries()[1]!.retrying, isTrue);
        async.flushMicrotasks();
        expect(local.openLaunches, hasLength(1));
      });
    },
  );

  test(
    'a manual try on a never-connected pane that fails does not auto-retry',
    () {
      fakeAsync((async) {
        add(1, connected: false);
        boot(async);
        lose(async, 1);
        local.openError = SpawnFailedException('ssh_unavailable');
        container.read(sshReconnectorProvider.notifier).reconnectNow(1);
        async.flushMicrotasks();
        expect(retries(), isEmpty);
        local.openError = null;
        async.elapse(const Duration(minutes: 5));
        expect(local.openLaunches, hasLength(1));
      });
    },
  );
}
