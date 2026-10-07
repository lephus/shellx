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
              ports: _AllFree(),
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
}

final class _AllFree implements LocalPorts {
  @override
  Future<bool> isFree(int port) async => true;
  @override
  Future<int> ephemeral() async => 50000;
}
