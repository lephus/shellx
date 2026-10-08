import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/global_search.dart';
import 'package:xterm/core.dart';

Terminal term(List<String> rows) {
  final t = Terminal(maxLines: 1000)..resize(80, 10);
  t.write(rows.join('\r\n'));
  return t;
}

PaneSource src(int tab, Terminal t, {int pane = 1, String label = 'x'}) =>
    PaneSource(
      tabId: tab,
      paneId: tab,
      tabLabel: label,
      paneNumber: pane,
      terminal: t,
    );

void main() {
  test(
    'finds across panes in the order given, with a snippet around the match',
    () {
      final a = PaneSource(
        tabId: 1,
        paneId: 1,
        tabLabel: 'one',
        paneNumber: 1,
        terminal: term(['first line', 'an Error happened here', 'last']),
      );
      final b = PaneSource(
        tabId: 2,
        paneId: 2,
        tabLabel: 'two',
        paneNumber: 1,
        terminal: term(['nothing', 'another error']),
      );
      final s = GlobalSearch([a, b], 'error')..step();
      expect(s.hits.map((h) => (h.tabId, h.row)), [(1, 1), (2, 1)]);
      final first = s.hits.first;
      expect(first.snippet, contains('an Error happened'));
      expect(
        first.snippet
            .substring(first.snippetStart, first.snippetEnd)
            .toLowerCase(),
        'error',
      );
      expect(first.tabLabel, 'one');
      s.dispose();
    },
  );

  test('stops at 20 per pane and 200 overall and says so', () {
    final many = [for (var i = 0; i < 100; i++) 'error $i'];
    final srcs = [for (var p = 0; p < 15; p++) src(p, term(many))];
    final s = GlobalSearch(srcs, 'error')..step();
    expect(s.hits.where((h) => h.paneId == 0).length, 20);
    expect(s.hits.length, 200);
    expect(s.capped, isTrue);
    s.dispose();
  });

  test('a one-character query finds nothing (needs 2)', () {
    final s = GlobalSearch([
      src(1, term(['aaa'])),
    ], 'a');
    expect(s.step(), isTrue);
    expect(s.hits, isEmpty);
  });

  test(
    'snippets are at most 120 characters and carry no control characters',
    () {
      final s = GlobalSearch([
        src(1, term(['${'x' * 200}needle${'y' * 200}'])),
      ], 'needle')..step();
      final h = s.hits.first;
      expect(h.snippet.length, lessThanOrEqualTo(120));
      expect(RegExp(r'[\x00-\x1f\x7f]').hasMatch(h.snippet), isFalse);
      expect(h.snippet.substring(h.snippetStart, h.snippetEnd), 'needle');
      s.dispose();
    },
  );

  test('works in slices: a tiny slice needs several steps, same hits', () {
    final srcs = [
      src(1, term([for (var i = 0; i < 500; i++) 'line error $i'])),
    ];
    final s = GlobalSearch(srcs, 'error', slice: Duration.zero);
    var steps = 0;
    while (!s.step()) {
      steps++;
      if (steps > 5000) fail('did not finish');
    }
    expect(steps, greaterThan(1));
    expect(s.hits.length, 20);
    s.dispose();
  });

  test('toString does not leak the snippet (privacy)', () {
    final s = GlobalSearch([
      src(1, term(['secret error'])),
    ], 'error')..step();
    expect(s.hits.single.toString(), '…');
    expect(s.toString(), isNot(contains('error')));
    s.dispose();
  });

  test('a hit follows its line when the scrollback is trimmed (anchors)', () {
    final t = Terminal(maxLines: 30)..resize(40, 10);
    t.write(
      [
        for (var i = 0; i < 10; i++) i == 8 ? 'the needle row' : 'row $i',
      ].join('\r\n'),
    );
    final s = GlobalSearch([src(1, t)], 'needle')..step();
    final hit = s.hits.single;
    final before = hit.liveRow;
    expect(before, hit.row);
    // Output that pushes older rows out of the 30-line history.
    t.write('\r\nx' * 40);
    expect(hit.liveRow, isNull, reason: 'the row was trimmed away');
    s.dispose();
  });

  test('a hit tracks its row while lines are only added below it', () {
    final t = Terminal(maxLines: 1000)..resize(40, 5);
    t.write('\r\n\r\nneedle here');
    final s = GlobalSearch([src(1, t)], 'needle')..step();
    final hit = s.hits.single;
    t.write('\r\nafter');
    expect(hit.liveRow, hit.row);
    s.dispose();
  });
}
