import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/ssh_reachability.dart';
import 'package:shellx_desktop/src/remote/ssh_reconnector.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

final devbox = SshTarget.parse('devbox')!;

void main() {
  late FakeLocalSessions local;
  late ProviderContainer container;
  late FakeAsync clock;
  var reachable = true;
  var probes = 0;

  void boot(FakeAsync async) {
    clock = async;
    container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        sshReachabilityProvider.overrideWithValue((_) async {
          probes++;
          return reachable;
        }),
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

  setUp(() {
    local = FakeLocalSessions();
    reachable = true;
    probes = 0;
  });

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
      local.openError = const SpawnFailedException('ssh_unavailable');
      lose(async, 1);
      final waits = <int>[];
      for (var i = 0; i < 60; i++) {
        final info = retries()[1];
        if (info == null || info.stopped) break;
        final wait = info.nextAt!.difference(
          DateTime(2026, 10, 7, 9).add(async.elapsed),
        );
        waits.add(wait.inSeconds);
        async.elapse(wait);
      }
      // D20: 3, 6, 12, 24, 48, then 60 s steps until 30 minutes passed.
      expect(waits.take(8), [3, 6, 12, 24, 48, 60, 60, 60]);
      expect(retries()[1]!.stopped, isTrue);
      expect(retries()[1]!.needsSignIn, isFalse);
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

  void connect(FakeAsync async, int id) {
    local.replace(
      local.summary(
        id,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      ),
    );
    async.flushMicrotasks();
  }

  void addFive() {
    for (var id = 1; id <= 5; id++) {
      add(id);
    }
  }

  test('five lost panes on one host: one ssh at a time (I1)', () {
    fakeAsync((async) {
      addFive();
      boot(async);
      for (var id = 1; id <= 5; id++) {
        lose(async, id);
      }
      async.elapse(const Duration(seconds: 3));
      expect(local.openLaunches, hasLength(1)); // the others wait
      async.elapse(const Duration(minutes: 2));
      expect(local.openLaunches, hasLength(1)); // still at the prompt
      connect(async, local.nextId - 1); // signed in: the master is up
      expect(local.openLaunches, hasLength(2));
      connect(async, local.nextId - 1);
      expect(local.openLaunches, hasLength(3));
      connect(async, local.nextId - 1);
      connect(async, local.nextId - 1);
      connect(async, local.nextId - 1);
      expect(local.openLaunches, hasLength(5));
      expect(retries(), isEmpty);
    });
  });

  test('the running attempt failed: the others reschedule together (I1)', () {
    fakeAsync((async) {
      addFive();
      boot(async);
      for (var id = 1; id <= 5; id++) {
        lose(async, id);
      }
      async.elapse(const Duration(seconds: 3));
      expect(local.openLaunches, hasLength(1));
      lose(async, local.nextId - 1);
      expect(local.openLaunches, hasLength(1)); // none started its own ssh
      final waiting = retries().values.where((i) => i.nextAt != null);
      expect(waiting, hasLength(5));
      async.elapse(const Duration(seconds: 6));
      expect(local.openLaunches, hasLength(2)); // one again, not five
    });
  });

  test('wake with five lost panes starts one attempt first (I1)', () {
    fakeAsync((async) {
      addFive();
      boot(async);
      for (var id = 1; id <= 5; id++) {
        lose(async, id);
      }
      container.read(sshReconnectorProvider.notifier).onWake();
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
    });
  });

  test('two sign-in failures in a row stop the host; Enter retries (I2)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      async.elapse(const Duration(seconds: 3));
      lose(async, local.nextId - 1); // refused (255), never connected
      async.elapse(const Duration(seconds: 6));
      final second = local.nextId - 1;
      lose(async, second);
      final info = retries()[second]!;
      expect(info.needsSignIn, isTrue);
      expect(info.stopped, isTrue);
      final n = local.openLaunches.length;
      async.elapse(const Duration(minutes: 10));
      expect(local.openLaunches.length, n);
      container.read(sshReconnectorProvider.notifier).onWake();
      async.flushMicrotasks();
      expect(local.openLaunches.length, n); // wake does not retry it either
      container.read(sshReconnectorProvider.notifier).reconnectNow(second);
      async.flushMicrotasks();
      expect(local.openLaunches.length, n + 1);
    });
  });

  test('stop(): nothing retries, wake included (I3)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      final notifier = container.read(sshReconnectorProvider.notifier);
      notifier.stop();
      notifier.onWake();
      async.elapse(const Duration(minutes: 5));
      expect(local.openLaunches, isEmpty);
    });
  });

  test('a second request while one is in flight does nothing (M1)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      final gate = Completer<void>();
      local.openGate = gate;
      final notifier = container.read(sshReconnectorProvider.notifier);
      notifier.reconnectNow(1);
      async.flushMicrotasks();
      notifier.reconnectNow(1);
      notifier.onWake();
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
      gate.complete();
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(1));
    });
  });

  test('wake after give-up does nothing; disposing cancels timers (M2)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      local.openError = const SpawnFailedException('ssh_unavailable');
      lose(async, 1);
      async.elapse(const Duration(minutes: 31));
      expect(retries()[1]!.stopped, isTrue);
      final n = local.openLaunches.length;
      container.read(sshReconnectorProvider.notifier).onWake();
      async.flushMicrotasks();
      expect(local.openLaunches.length, n);

      add(2);
      lose(async, 2);
      container.dispose();
      async.elapse(const Duration(minutes: 5));
      expect(local.openLaunches.length, n);
    });
  });

  test('Enter after a failed open keeps retrying on the back-off (M2)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      local.openError = const SpawnFailedException('ssh_unavailable');
      container.read(sshReconnectorProvider.notifier).reconnectNow(1);
      async.flushMicrotasks();
      expect(retries()[1]!.nextAt, isNotNull);
      expect(retries()[1]!.retrying, isFalse);
      local.openError = null;
      async.elapse(const Duration(seconds: 10));
      expect(local.openLaunches.length, greaterThan(1));
    });
  });

  test(
    'host down: back-off goes on for 30 min, no ssh, no needsSignIn (N1)',
    () {
      fakeAsync((async) {
        add(1);
        boot(async);
        reachable = false;
        lose(async, 1);
        async.elapse(const Duration(minutes: 25));
        expect(local.openLaunches, isEmpty);
        expect(probes, greaterThan(10));
        final info = retries()[1]!;
        expect(info.needsSignIn, isFalse);
        expect(info.stopped, isFalse);
        reachable = true; // the server is back: the next step connects
        async.elapse(const Duration(seconds: 61));
        expect(local.openLaunches, hasLength(1));
        async.elapse(const Duration(minutes: 10));
        expect(local.openLaunches, hasLength(1)); // then it gave up on its own
      });
    },
  );

  test(
    'host down then up: failures start counting only once reachable (N1)',
    () {
      fakeAsync((async) {
        add(1);
        boot(async);
        reachable = false;
        lose(async, 1);
        async.elapse(const Duration(minutes: 3));
        reachable = true;
        async.elapse(const Duration(seconds: 60));
        final first = local.nextId - 1;
        lose(async, first);
        expect(retries()[first]!.needsSignIn, isFalse); // one failure
      });
    },
  );

  test('closing the pane at the prompt is not a failure (N2)', () {
    fakeAsync((async) {
      addFive();
      boot(async);
      for (var id = 1; id <= 5; id++) {
        lose(async, id);
      }
      async.elapse(const Duration(seconds: 3));
      final tabs = container.read(terminalTabsProvider.notifier);
      tabs.close(1); // the first attempt's tab closed at its prompt
      async.flushMicrotasks();
      expect(local.openLaunches, hasLength(2)); // the next one goes
      expect(retries().values.any((i) => i.needsSignIn), isFalse);
    });
  });

  test('after the stop a later loss starts with two fresh tries (N3)', () {
    fakeAsync((async) {
      add(1);
      boot(async);
      lose(async, 1);
      async.elapse(const Duration(seconds: 3));
      lose(async, local.nextId - 1);
      async.elapse(const Duration(seconds: 6));
      final stopped = local.nextId - 1;
      lose(async, stopped);
      expect(retries()[stopped]!.needsSignIn, isTrue);
      // The user signs in by hand, it drops later.
      container.read(sshReconnectorProvider.notifier).reconnectNow(stopped);
      async.flushMicrotasks();
      connect(async, local.nextId - 1);
      expect(retries(), isEmpty);
      lose(async, local.nextId - 1);
      async.elapse(const Duration(seconds: 3));
      lose(async, local.nextId - 1); // one failure only
      expect(retries().values.single.needsSignIn, isFalse);
    });
  });

  test('parseSshG: resolved host and port; jump hosts are marked (N1)', () {
    final plain = parseSshG(
      'user me\nhostname 10.0.0.5\nport 2222\nproxyjump none\n',
    );
    expect(plain, (host: '10.0.0.5', port: 2222, proxied: false));
    expect(parseSshG('hostname h\nproxyjump bastion\n')!.proxied, isTrue);
    expect(parseSshG('hostname h\nproxycommand nc %h %p\n')!.proxied, isTrue);
    expect(parseSshG('hostname h\n')!.port, 22);
    expect(parseSshG('nothing'), isNull);
  });
}
