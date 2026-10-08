import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/context_line.dart';

double _m(String s) => s.runes.length * 6.0;

ContextLineLayout layout({
  required double width,
  double pr = 0,
  List<int> ports = const [],
  String? path = '~/work/app',
}) => layoutContextLine(
  branch: 'main',
  path: path,
  ports: ports,
  width: width,
  measure: _m,
  windows: false,
  prWidth: pr,
);

void main() {
  test('no PR chip asked for: none shown', () {
    expect(layout(width: 400).showPr, isFalse);
  });

  test('a wide row shows the chip and cuts nothing', () {
    final l = layout(width: 400, pr: 40, ports: [3000]);
    expect(l.showPr, isTrue);
    expect(l.path, '~/work/app');
    expect(l.ports, [3000]);
    expect(l.truncated, isFalse);
  });

  test('a narrow row drops the chip before it narrows the ports', () {
    final without = layout(width: 150, ports: [3000, 3001, 3002]);
    for (var w = 100.0; w <= 300; w += 4) {
      final base = layout(width: w, ports: [3000, 3001, 3002]);
      final withPr = layout(width: w, pr: 40, ports: [3000, 3001, 3002]);
      // Whenever the chip is shown the ports are exactly what they were.
      if (withPr.showPr) {
        expect(withPr.ports, base.ports, reason: '$w');
        expect(withPr.morePorts, base.morePorts, reason: '$w');
      }
    }
    expect(without.ports, isNotEmpty);
  });

  test('somewhere between wide and narrow the chip is dropped', () {
    var shown = 0, hidden = 0;
    for (var w = 60.0; w <= 400; w += 4) {
      final l = layout(width: w, pr: 40, ports: [3000, 3001]);
      l.showPr ? shown++ : hidden++;
    }
    expect(shown, greaterThan(0));
    expect(hidden, greaterThan(0));
  });

  test('a chip with no room is dropped even without ports', () {
    expect(layout(width: 40, pr: 40).showPr, isFalse);
  });
}
