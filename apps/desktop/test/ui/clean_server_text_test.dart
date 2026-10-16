import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/remote_marks.dart';

void main() {
  test('server text loses control characters and bidi controls', () {
    expect(cleanServerText('dev\x1b[31mbox\n'), 'dev[31mbox');
    expect(cleanServerText('a b c\u0085d\u007fe'), 'abcde');
    expect(cleanServerText('a‎b‏c؜d'), 'abcd');
    expect(cleanServerText('máy-chủ.example'), 'máy-chủ.example');
  });

  test('embeddings, overrides and isolates go too', () {
    // Built from code points: the analyzer rejects them as literals.
    for (final (from, to) in [(0x202a, 0x202e), (0x2066, 0x2069)]) {
      for (var cp = from; cp <= to; cp++) {
        final mark = String.fromCharCode(cp);
        expect(
          cleanServerText('a${mark}b'),
          'ab',
          reason: cp.toRadixString(16),
        );
      }
    }
  });
}
