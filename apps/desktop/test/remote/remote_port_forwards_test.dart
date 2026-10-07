import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/remote/remote_port_forwards.dart';
import 'package:shellx_desktop/src/remote/remote_tools_provider.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';

void main() {
  final devbox = SshTarget.parse('devbox')!;

  test('local pane: the port as is; SSH pane: a forward, opened, remembered, '
      'cancelled with the last pane (D19)', () async {
    final local = FakeLocalSessions();
    final runs = <List<String>>[];
    var forwardExit = 0;
    final opened = <int>[];
    local.add(
      local.summary(1, origin: SessionOrigin.desktop, ports: const [5173]),
    );
    local.add(
      local.summary(
        2,
        origin: SessionOrigin.desktop,
        ports: const [8000],
        remote: SessionRemote(launch: SshLaunch(devbox), connected: true),
      ),
    );
    final container = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        portOpenerProvider.overrideWithValue((port) async => opened.add(port)),
        remoteToolsProvider.overrideWithValue(
          RemoteTools(
            sshPath: '/usr/bin/ssh',
            control: SshControl(
              sshPath: '/usr/bin/ssh',
              controlDirectory: '/tmp/sx',
              run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
                runs.add(args);
                return CommandResult(
                  args.contains('forward') ? forwardExit : 0,
                  '',
                  '',
                );
              },
              ports: _Ports(),
            ),
          ),
        ),
      ],
    );
    final tabs = container.read(terminalTabsProvider);
    final forwards = container.read(remotePortForwardsProvider.notifier);
    PaneSession pane(int id) => tabs.tabOfSession(id)!.panes[id]!;

    await forwards.open(pane(1), 5173);
    expect(opened, [5173]);
    expect(runs, isEmpty);
    await forwards.open(pane(2), 8000);
    expect(opened, [5173, 8000]);
    expect(
      runs.last,
      containsAllInOrder([
        '-O',
        'forward',
        '-L',
        '127.0.0.1:8000:localhost:8000',
      ]),
    );
    expect(forwards.forwarded('devbox', 8000), 8000);
    forwardExit = 1;
    expect(await forwards.localPort(pane(2), 9000), isNull);
    expect(
      container.read(terminalTabsProvider).notice,
      isA<RemotePortForwardFailedNotice>(),
    );
    container.read(terminalTabsProvider.notifier).close(2);
    await pumpEventQueue();
    expect(runs.last, containsAllInOrder(['-O', 'cancel']));
    expect(forwards.forwarded('devbox', 8000), isNull);
  });

  group('rig', () {
    late FakeLocalSessions local;
    late List<List<String>> runs;
    late List<int> opened;
    Completer<void>? gate;
    Object? runError;
    int forwardExit = 0;
    final busy = <int>{};
    SshControl? control;

    ProviderContainer boot({bool withControl = true, Object? openError}) {
      control = withControl
          ? SshControl(
              sshPath: '/usr/bin/ssh',
              controlDirectory: '/tmp/sx',
              run: (exe, args, {timeout = const Duration(seconds: 5)}) async {
                runs.add(args);
                if (args.contains('forward')) {
                  await gate?.future;
                  if (runError != null) throw runError!;
                  return CommandResult(forwardExit, '', '');
                }
                return CommandResult(0, '', '');
              },
              ports: _Ports(busy),
            )
          : null;
      return ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          appL10nProvider.overrideWithValue(
            lookupAppLocalizations(const Locale('en')),
          ),
          portOpenerProvider.overrideWithValue((port) async {
            if (openError != null) throw openError;
            opened.add(port);
          }),
          remoteToolsProvider.overrideWithValue(
            RemoteTools(sshPath: '/usr/bin/ssh', control: control),
          ),
        ],
      );
    }

    void server(int id, SshTarget host, {bool connected = true}) => local.add(
      local.summary(
        id,
        origin: SessionOrigin.desktop,
        remote: SessionRemote(launch: SshLaunch(host), connected: connected),
      ),
    );

    setUp(() {
      local = FakeLocalSessions();
      runs = [];
      opened = [];
      gate = null;
      runError = null;
      forwardExit = 0;
      busy.clear();
    });

    PaneSession paneOf(ProviderContainer c, int id) =>
        c.read(terminalTabsProvider).tabOfSession(id)!.panes[id]!;

    int forwardRuns() => runs.where((a) => a.contains('forward')).length;

    test('two clicks at once share one forward and one request (R1)', () async {
      server(1, devbox);
      final c = boot();
      gate = Completer();
      final f = c.read(remotePortForwardsProvider.notifier);
      c.read(terminalTabsProvider);
      final a = f.localPort(paneOf(c, 1), 8000);
      final b = f.localPort(paneOf(c, 1), 8000);
      gate!.complete();
      expect(await a, 8000);
      expect(await b, 8000);
      expect(forwardRuns(), 1);
      expect(c.read(terminalTabsProvider).notice, isNull);
    });

    test(
      'the last pane closing while the forward starts cancels it (R2)',
      () async {
        server(1, devbox);
        final c = boot();
        c.read(terminalTabsProvider);
        gate = Completer();
        final f = c.read(remotePortForwardsProvider.notifier);
        final pending = f.localPort(paneOf(c, 1), 8000);
        c.read(terminalTabsProvider.notifier).close(1);
        await pumpEventQueue();
        gate!.complete();
        expect(await pending, isNull);
        await pumpEventQueue();
        expect(f.forwarded('devbox', 8000), isNull);
        expect(runs.last, containsAllInOrder(['-O', 'cancel']));
      },
    );

    test(
      'ssh failing to start shows the same toast, no unhandled error (R3)',
      () async {
        server(1, devbox);
        final c = boot();
        c.read(terminalTabsProvider);
        runError = const ProcessException('ssh', []);
        final f = c.read(remotePortForwardsProvider.notifier);
        expect(await f.localPort(paneOf(c, 1), 8000), isNull);
        expect(
          c.read(terminalTabsProvider).notice,
          isA<RemotePortForwardFailedNotice>(),
        );
      },
    );

    test(
      'a busy port gets an ephemeral local one; a repeat reuses the forward',
      () async {
        server(1, devbox);
        final c = boot();
        c.read(terminalTabsProvider);
        busy.add(8000);
        final f = c.read(remotePortForwardsProvider.notifier);
        expect(await f.localPort(paneOf(c, 1), 8000), 50000);
        expect(
          runs.where((a) => a.contains('forward')).last,
          contains('127.0.0.1:50000:localhost:8000'),
        );
        expect(f.forwarded('devbox', 8000), 50000);
        final before = forwardRuns();
        expect(await f.localPort(paneOf(c, 1), 8000), 50000);
        expect(forwardRuns(), before);
      },
    );

    test(
      'user@host:port round-trips through the forward bookkeeping',
      () async {
        final target = SshTarget.parse('me@box:2222')!;
        server(1, target);
        final c = boot();
        c.read(terminalTabsProvider);
        final f = c.read(remotePortForwardsProvider.notifier);
        await f.localPort(paneOf(c, 1), 8000);
        expect(f.forwarded('me@box:2222', 8000), 8000);
        c.read(terminalTabsProvider.notifier).close(1);
        await pumpEventQueue();
        expect(f.forwarded('me@box:2222', 8000), isNull);
        expect(runs.last, containsAllInOrder(['-O', 'cancel']));
      },
    );

    test(
      'a host with a live pane keeps its forwards; the other one goes',
      () async {
        final other = SshTarget.parse('other')!;
        server(1, devbox);
        server(2, devbox);
        server(3, other);
        final c = boot();
        c.read(terminalTabsProvider);
        final f = c.read(remotePortForwardsProvider.notifier);
        await f.localPort(paneOf(c, 1), 8000);
        await f.localPort(paneOf(c, 3), 9000);
        c.read(terminalTabsProvider.notifier).close(3);
        await pumpEventQueue();
        expect(f.forwarded('other', 9000), isNull);
        c.read(terminalTabsProvider.notifier).close(1);
        await pumpEventQueue();
        expect(f.forwarded('devbox', 8000), 8000); // pane 2 is still live
      },
    );

    test('a lost (not closed) pane cancels too (D19, documented)', () async {
      server(1, devbox);
      final c = boot();
      c.read(terminalTabsProvider);
      final f = c.read(remotePortForwardsProvider.notifier);
      await f.localPort(paneOf(c, 1), 8000);
      local.summaries.removeWhere((s) => s.id == 1);
      local.views[1]!.end(255);
      await pumpEventQueue();
      expect(f.forwarded('devbox', 8000), isNull);
      expect(runs.last, containsAllInOrder(['-O', 'cancel']));
    });

    test('no ssh control: the ssh-unavailable toast', () async {
      server(1, devbox);
      final c = boot(withControl: false);
      c.read(terminalTabsProvider);
      final f = c.read(remotePortForwardsProvider.notifier);
      expect(await f.localPort(paneOf(c, 1), 8000), isNull);
      expect(c.read(terminalTabsProvider).notice, isA<SshUnavailableNotice>());
    });

    test('the browser failing to open shows the port-open toast', () async {
      local.add(local.summary(1, origin: SessionOrigin.desktop));
      final c = boot(openError: StateError('no browser'));
      c.read(terminalTabsProvider);
      await c
          .read(remotePortForwardsProvider.notifier)
          .open(paneOf(c, 1), 5173);
      expect(c.read(terminalTabsProvider).notice, isA<PortOpenFailedNotice>());
    });
  });
}

final class _Ports implements LocalPorts {
  _Ports([this.busy = const {}]);
  final Set<int> busy;
  @override
  Future<bool> isFree(int port) async => !busy.contains(port);
  @override
  Future<int> ephemeral() async => 50000;
}
