@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/desktop_terminal.dart';
import 'package:shellx_desktop/src/terminal/terminal_feed.dart';

/// One run: [text] written in slices of [slice] characters, as TerminalFeed
/// does per frame. Returns (total ms, slowest slice ms, MB/s).
(int, int, double) _run(String text, {int slice = 256 * 1024}) {
  final terminal = DesktopTerminal();
  terminal.resize(160, 48);
  final total = Stopwatch()..start();
  var slowest = 0;
  for (var start = 0; start < text.length; start += slice) {
    final end = (start + slice).clamp(0, text.length);
    final one = Stopwatch()..start();
    terminal.write(text.substring(start, end));
    one.stop();
    if (one.elapsedMilliseconds > slowest) slowest = one.elapsedMilliseconds;
  }
  total.stop();
  final mb = text.length / (1024 * 1024);
  final seconds = total.elapsedMicroseconds / 1e6;
  return (total.elapsedMilliseconds, slowest, mb / seconds);
}

void _report(String name, (int, int, double) r) {
  final (total, slowest, rate) = r;
  // ignore: avoid_print
  print(
    'xterm benchmark — $name: total ${total}ms, slowest 256 KiB slice '
    '${slowest}ms, ${rate.toStringAsFixed(1)} MB/s '
    '(criterion 8: a slice under 1000 ms keeps the UI painting: '
    '${slowest < 1000 ? 'met' : 'NOT met'})',
  );
}

void main() {
  test('yes | head -n 2000000', () {
    _report('yes x2M', _run('y\r\n' * 2000000));
  });

  test('cat of a 50 MB text file (80-column lines)', () {
    final line = '${'0123456789abcdefghijklmnopqrstuvwxyz' * 2}01234567\r\n';
    final count = (50 * 1024 * 1024) ~/ line.length;
    _report('cat 50 MB', _run(line * count));
  });

  test('colourful output (SGR every few characters, like ls --color)', () {
    const chunk = '\x1b[1;34mdir\x1b[0m  \x1b[32mfile.sh\x1b[0m  plain.txt\r\n';
    _report('SGR 8 MB', _run(chunk * ((8 * 1024 * 1024) ~/ chunk.length)));
  });

  test('TerminalFeed caps a hidden flood at 1 MiB pending', () {
    var written = 0;
    final feed = TerminalFeed((text) => written += text.length);
    final chunk = List<int>.filled(64 * 1024, 0x79); // 'y'
    for (var i = 0; i < 800; i++) {
      feed.add(chunk); // 50 MiB arriving faster than any tick
    }
    feed.drain();
    feed.dispose();
    // ignore: avoid_print
    print(
      'TerminalFeed: 50 MiB in, ${(written / (1024 * 1024)).toStringAsFixed(2)} '
      'MiB written, ${feed.dropped} drops',
    );
    expect(written, lessThan(2 * 1024 * 1024));
  });
}
