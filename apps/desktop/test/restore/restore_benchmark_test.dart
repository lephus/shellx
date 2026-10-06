@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/restore/scrollback_codec.dart';
import 'package:xterm/xterm.dart';

/// Spec criterion 10 (measured, not gated): the final save at quit with
/// 32 panes × 2,000 lines ≤ 500 ms on Apple M-series; one layout write
/// ≤ 20 ms. Skipped by default (dart_test.yaml); run with
/// `flutter test --run-skipped --tags benchmark
/// test/restore/restore_benchmark_test.dart`.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('a5a-bench'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('final save: encode + write 32 panes × 2,000 coloured lines, and '
      'one 32-tab layout write (prints timings)', () async {
    final panes = [
      for (var p = 0; p < 32; p++) Terminal(maxLines: 10000)..resize(120, 40),
    ];
    for (final t in panes) {
      for (var i = 0; i < 2000; i++) {
        t.write('\x1b[3${i % 8}mline $i ${'x' * 80}\x1b[0m\r\n');
      }
    }
    final keys = [for (final _ in panes) newPaneKey()];
    final store = RestoreStore(
      Directory('${temp.path}${Platform.pathSeparator}restore'),
      excludeFromBackup: (_) async {},
    );
    expect(await store.prepare(), isTrue);

    final encode = Stopwatch()..start();
    final textByKey = {
      for (var p = 0; p < panes.length; p++)
        keys[p]: encodeScrollback(panes[p]),
    };
    encode.stop();

    final write = Stopwatch()..start();
    final written = await store.writeScrollbacks(textByKey);
    write.stop();
    expect(written, isTrue);

    final snapshot = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 7),
      cleanExit: true,
      selectedTab: keys.first,
      workspaces: [SavedWorkspace(id: 'default', tabs: keys)],
      tabs: [
        for (final key in keys)
          SavedTab(
            key: key,
            focused: key,
            layout: SavedPane(key: key, cwd: '/Users/test/project'),
          ),
      ],
    );
    final layout = Stopwatch()..start();
    expect(await store.writeLayout(snapshot), isTrue);
    layout.stop();

    final chars = textByKey.values.fold<int>(0, (n, t) => n + t.length);
    final lines = textByKey.values.fold<int>(
      0,
      (n, t) => n + '\n'.allMatches(t).length,
    );
    final total = encode.elapsedMilliseconds + write.elapsedMilliseconds;
    // ignore: avoid_print
    print(
      'A5a encode: ${encode.elapsedMilliseconds} ms, write: '
      '${write.elapsedMilliseconds} ms, total: $total ms (criterion 10: '
      '≤ 500 ms) for 32 panes, $lines lines, $chars chars; layout write: '
      '${layout.elapsedMilliseconds} ms (≤ 20 ms)',
    );
    // Every pane kept its last 2,000 lines, within the 256 KiB cap.
    for (final text in textByKey.values) {
      expect('\n'.allMatches(text).length, kRestoreMaxLines);
      expect(text.length, lessThanOrEqualTo(kRestoreMaxBytes));
    }
  });
}
