@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

/// A7 D40 (measured, not gated): the window's own time for `ui.ls` with
/// 32 tabs (target ≤ 5 ms) and for a whole `ui.pane.read` of 10,000
/// lines, every page (target ≤ 100 ms). Skipped by default
/// (dart_test.yaml); run with `flutter test --run-skipped --tags benchmark
/// test/cli/cli_benchmark_test.dart`. The numbers go in the ledger.
void main() {
  late FakeLocalSessions local;
  late UiCommandHandler h;

  setUp(() async {
    local = FakeLocalSessions();
    final c = cliContainer(local);
    h = c.read(uiCommandHandlerProvider);
    final tabs = c.read(terminalTabsProvider.notifier);
    for (var i = 0; i < 32; i++) {
      await tabs.openTab();
    }
  });

  /// Median and worst of [runs] timings of [body], in microseconds.
  Future<(int, int)> time(int runs, Future<void> Function() body) async {
    final us = <int>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      await body();
      us.add(sw.elapsedMicroseconds);
    }
    us.sort();
    return (us[us.length ~/ 2], us.last);
  }

  test('ui.ls with 32 tabs; ui.pane.read of 10,000 lines (prints '
      'timings)', () async {
    final ls = MuxMessage(CliType.uiLs, q: 1);
    await h.handle(ls); // warm up
    final (lsMedian, lsMax) = await time(50, () => h.handle(ls));

    local.views[100]!.emit(
      [for (var i = 0; i < 10000; i++) 'line $i ${'x' * 60}'].join('\r\n'),
    );
    await pumpFeed();
    var pages = 0;
    Future<void> readAll() async {
      int? offset = 0;
      pages = 0;
      while (offset != null) {
        final r = await h.handle(
          MuxMessage(
            CliType.uiPaneRead,
            q: 1,
            fields: {'pane': 100, 'lines': 10000, 'offset': offset},
          ),
        );
        pages++;
        offset = r['next'] as int?;
      }
    }

    await readAll(); // warm up
    final (readMedian, readMax) = await time(10, readAll);

    // ignore: avoid_print
    print(
      'D40 ui.ls (32 tabs): median ${lsMedian / 1000} ms, max '
      '${lsMax / 1000} ms; ui.pane.read 10,000 lines ($pages pages): '
      'median ${readMedian / 1000} ms, max ${readMax / 1000} ms',
    );
    expect(pages, greaterThan(1));
  });
}
