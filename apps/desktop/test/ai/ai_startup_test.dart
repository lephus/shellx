import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

Future<bool> alive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;

void main() {
  test('the host lives under <support>/ai and names the app version', () {
    final host = buildAiHost(supportDir: '/support', version: '2.0.0');
    expect(host.supportDir, '/support');
    expect(host.clientVersion, '2.0.0');
  });

  test(
    'an agent a crash left behind stops with its whole tree (§6)',
    () async {
      final tmp = Directory.systemTemp.createTempSync('ai_sweep');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final pidFile = File('${tmp.path}/grandchild.pid');
      // An "agent" with a child of its own, as `node` runs its adapter.
      final agent = await Process.start('/bin/sh', [
        '-c',
        'sh -c \'sleep 60 & echo \$! > "${pidFile.path}"; wait\' & wait',
      ]);
      unawaited(agent.stdout.drain<void>());
      unawaited(agent.stderr.drain<void>());
      for (var i = 0; i < 100 && !pidFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final grandchild = int.parse(pidFile.readAsStringSync().trim());
      final host = buildAiHost(supportDir: tmp.path, version: 'test');
      await host.running.add(
        RunningRecord(
          pid: agent.pid,
          command: '/bin/sh',
          startedAt: DateTime.now(),
        ),
      );
      expect(await host.running.sweep(), 1);
      await agent.exitCode;
      var gone = false;
      for (var i = 0; i < 40 && !gone; i++) {
        gone = !await alive(grandchild);
        if (!gone) await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(gone, isTrue, reason: 'the agent\'s child survived the sweep');
    },
    skip: Platform.isWindows,
  );

  test('start: sweep, prune and warm-up, and nothing throws', () async {
    final tmp = Directory.systemTemp.createTempSync('ai_start');
    addTearDown(() => tmp.deleteSync(recursive: true));
    var checked = 0;
    final host = AiHost(
      supportDir: tmp.path,
      clientVersion: 'test',
      // No login shell, no git: the start must still finish.
      env: LoginShellEnv(
        processEnv: const {'PATH': '/usr/bin'},
        run: (_, _, _, _) async => throw StateError('no shell here'),
      ),
      checkpoints: CheckpointStores(
        root: '${tmp.path}/ai/checkpoints',
        locator: GitLocator(probe: (_, _, {environment}) async => null),
      ),
    );
    final c = ProviderContainer.test(
      overrides: [
        aiHostProvider.overrideWithValue(host),
        aiReadinessSourceProvider.overrideWithValue((_) async {
          checked++;
          return const AgentNeedsInstall(null);
        }),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ...configOverrides(MemoryConfigFs()),
      ],
    );
    await startAi(c);
    expect(checked, 4, reason: 'every agent, once');
    await startAi(c);
    expect(checked, 4, reason: 'warm-up runs once a run');
  });
}
