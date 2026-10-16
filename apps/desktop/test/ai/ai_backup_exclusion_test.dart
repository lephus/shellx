import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

/// V2-1b final review M-11: Time Machine keeps neither the agents' npm
/// adapters (hundreds of MB, downloaded again on demand) nor the restore
/// points' repositories (a copy of every project that changes each turn).
void main() {
  late Directory tmp;
  late AiHost host;
  late String agents;
  late String checkpoints;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ai_backup');
    addTearDown(() => tmp.deleteSync(recursive: true));
    agents = p.join(tmp.path, 'ai', 'agents');
    checkpoints = p.join(tmp.path, 'ai', 'checkpoints');
    host = AiHost(
      supportDir: tmp.path,
      clientVersion: 'test',
      // No login shell, no git: the start must still finish.
      env: LoginShellEnv(
        processEnv: const {'PATH': '/usr/bin'},
        run: (_, _, _, _) async => throw StateError('no shell here'),
      ),
      checkpoints: CheckpointStores(
        root: checkpoints,
        locator: GitLocator(probe: (_, _, {environment}) async => null),
      ),
    );
  });

  group('excludeAiDataFromBackup', () {
    test('agents and checkpoints, made if need be (the system can only '
        'exclude a folder that exists)', () async {
      final seen = <String>[];
      final existed = <bool>[];
      await excludeAiDataFromBackup(
        host,
        exclude: (path) async {
          seen.add(path);
          existed.add(Directory(path).existsSync());
        },
      );
      expect(seen, [agents, checkpoints]);
      expect(existed, [true, true]);
    });

    test('a failure is ignored, the other folder is still tried, and '
        'nothing but the error\'s type is logged', () async {
      final seen = <String>[];
      final logged = <String>[];
      await excludeAiDataFromBackup(
        host,
        exclude: (path) async {
          seen.add(path);
          throw ProcessException('/usr/bin/tmutil', ['secret-arg', path]);
        },
        log: logged.add,
      );
      expect(seen, [agents, checkpoints]);
      expect(logged, hasLength(2));
      for (final line in logged) {
        expect(line, contains('ProcessException'));
        expect(line, isNot(contains(tmp.path)));
        expect(line, isNot(contains('secret-arg')));
      }
    });

    test('a call that hangs is given up on after the timeout', () async {
      final seen = <String>[];
      await excludeAiDataFromBackup(
        host,
        exclude: (path) {
          seen.add(path);
          return Completer<void>().future;
        },
        timeout: const Duration(milliseconds: 20),
        log: (_) {},
      );
      expect(seen, [agents, checkpoints]);
    });
  });

  group('startAi', () {
    ProviderContainer container({
      Future<void> Function(String path)? exclude,
    }) => ProviderContainer.test(
      overrides: [
        aiHostProvider.overrideWithValue(host),
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNeedsInstall(null),
        ),
        aiBackupExcluderProvider.overrideWithValue(exclude),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ...configOverrides(MemoryConfigFs()),
      ],
    );

    test('asks for both folders to be left out, in the background', () async {
      final seen = <String>[];
      final both = Completer<void>();
      final gate = Completer<void>();
      final c = container(
        exclude: (path) async {
          seen.add(path);
          await gate.future;
          if (seen.length == 2 && !both.isCompleted) both.complete();
        },
      );
      // The start does not wait for the exclusion.
      await startAi(c);
      gate.complete();
      await both.future.timeout(const Duration(seconds: 10));
      expect(seen, [agents, checkpoints]);
    });

    test('where the system has no such thing (no excluder), nothing is '
        'asked and the start finishes', () async {
      await startAi(container());
    });

    test('an exclusion that throws never fails the start', () async {
      var asked = 0;
      final c = container(
        exclude: (_) async {
          asked++;
          throw StateError('tmutil is not here');
        },
      );
      await startAi(c);
      for (var i = 0; i < 100 && asked < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(asked, 2);
    });
  });
}
