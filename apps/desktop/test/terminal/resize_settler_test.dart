import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/resize_settler.dart';

void main() {
  test('120 sizes in two seconds make one send, after the last settles', () {
    fakeAsync((async) {
      final settler = ResizeSettler();
      final sent = <(int, int)>[];
      for (var i = 0; i < 120; i++) {
        settler.request(1, 80 + i % 40, 24, (c, r) => sent.add((c, r)));
        if (i < 119) async.elapse(const Duration(milliseconds: 16));
      }
      expect(sent, isEmpty, reason: 'no size reached the PTY mid-drag');
      async.elapse(const Duration(milliseconds: 79));
      expect(sent, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(sent, [(80 + 119 % 40, 24)]);
      expect(settler.hasPending(1), isFalse);
    });
  });

  test('flush sends the waiting size at once and only once', () {
    fakeAsync((async) {
      final settler = ResizeSettler();
      final sent = <(int, int)>[];
      settler.request(1, 100, 30, (c, r) => sent.add((c, r)));
      expect(settler.flush(1), isTrue);
      expect(sent, [(100, 30)]);
      expect(settler.flush(1), isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(sent, hasLength(1));
    });
  });

  test('panes are independent; cancel drops a pane\'s size', () {
    fakeAsync((async) {
      final settler = ResizeSettler();
      final sent = <(int, int, int)>[];
      settler.request(1, 80, 24, (c, r) => sent.add((1, c, r)));
      settler.request(2, 90, 30, (c, r) => sent.add((2, c, r)));
      settler.cancel(1);
      async.elapse(const Duration(milliseconds: 100));
      expect(sent, [(2, 90, 30)]);
    });
  });

  test('flushAll and dispose', () {
    fakeAsync((async) {
      final settler = ResizeSettler();
      final sent = <int>[];
      settler.request(1, 80, 24, (c, r) => sent.add(1));
      settler.request(2, 80, 24, (c, r) => sent.add(2));
      settler.flushAll();
      expect(sent, [1, 2]);
      settler.request(3, 80, 24, (c, r) => sent.add(3));
      settler.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(sent, [1, 2]);
      settler.request(4, 80, 24, (c, r) => sent.add(4));
      async.elapse(const Duration(seconds: 1));
      expect(sent, [1, 2], reason: 'a disposed settler sends nothing');
    });
  });

  test('a zero settle time sends straight away', () {
    final sent = <int>[];
    ResizeSettler(
      settle: Duration.zero,
    ).request(1, 80, 24, (c, r) => sent.add(c));
    expect(sent, [80]);
  });
}
