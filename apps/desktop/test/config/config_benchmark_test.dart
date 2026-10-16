@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

/// A9 D42 (measured, not gated): a full load + build of a 1,000-line
/// configuration (target ≤ 20 ms), and the watcher's stat cost per poll
/// with the worst-case file list (the include limit of 64 files plus the
/// Ghostty candidates and theme folders; every poll stats each once).
/// Skipped by default (dart_test.yaml); run with `flutter test
/// --run-skipped --tags benchmark test/config/config_benchmark_test.dart`.
/// The numbers go in the ledger.
void main() {
  final thousand = [
    for (var i = 0; i < 1000; i++) 'keybind = ctrl+alt+shift+f12=new_tab',
  ].join('\n');

  int medianUs(List<int> samples) => (samples..sort())[samples.length ~/ 2];

  test(
    'load + build of a 1,000-line file, in memory (prints timings)',
    () async {
      final fs = MemoryConfigFs()..write(testConfigPaths().shellx, thousand);
      final c = ProviderContainer(overrides: configOverrides(fs));
      addTearDown(c.dispose);
      await loadConfig(c); // warm-up
      final samples = <int>[];
      for (var i = 0; i < 30; i++) {
        final sw = Stopwatch()..start();
        await loadConfig(c);
        samples.add(sw.elapsedMicroseconds);
      }
      // ignore: avoid_print
      print(
        'A9 D42 load+build 1,000 lines (memory fs): median '
        '${medianUs(samples) / 1000} ms, max ${samples.last / 1000} ms',
      );
    },
  );

  test(
    'load + build of a 1,000-line file on the real disk (prints timings)',
    () async {
      final home = Directory.systemTemp.createTempSync('a9-bench');
      addTearDown(() => home.deleteSync(recursive: true));
      final paths = configPathsFor(
        windows: false,
        env: const {},
        home: home.path,
      );
      File(paths.shellx)
        ..createSync(recursive: true)
        ..writeAsStringSync(thousand);
      final c = ProviderContainer(
        overrides: [
          configFsProvider.overrideWithValue(const IoConfigFs()),
          configPathsProvider.overrideWithValue(paths),
          configPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ],
      );
      addTearDown(c.dispose);
      await loadConfig(c);
      final samples = <int>[];
      for (var i = 0; i < 30; i++) {
        final sw = Stopwatch()..start();
        await loadConfig(c);
        samples.add(sw.elapsedMicroseconds);
      }
      // ignore: avoid_print
      print(
        'A9 D42 load+build 1,000 lines (real disk): median '
        '${medianUs(samples) / 1000} ms, max ${samples.last / 1000} ms',
      );
    },
  );

  test(
    'watcher stat cost per poll, worst-case list (prints timings)',
    () async {
      final dir = Directory.systemTemp.createTempSync('a9-bench');
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = configPathsFor(
        windows: false,
        env: const {},
        home: dir.path,
      );
      // 64 real include files + every Ghostty candidate and theme folder
      // (mostly missing, as on a machine without Ghostty).
      final files = <String>[
        for (var i = 0; i < kConfigMaxFiles; i++)
          (File(
            '${dir.path}/inc$i',
          )..writeAsStringSync('font-size = 13\n')).path,
        ...paths.ghostty,
      ];
      const fs = IoConfigFs();
      for (final f in files) {
        await fs.stamp(f); // warm-up
      }
      final samples = <int>[];
      for (var i = 0; i < 100; i++) {
        final sw = Stopwatch()..start();
        for (final f in files) {
          await fs.stamp(f);
        }
        samples.add(sw.elapsedMicroseconds);
      }
      // ignore: avoid_print
      print(
        'A9 D42 watcher poll, ${files.length} stats: median '
        '${medianUs(samples) / 1000} ms, max ${samples.last / 1000} ms '
        '(once per second)',
      );
    },
  );
}
