import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const _phone = 'p1';
final _t0 = DateTime.utc(2026, 10, 15, 9);

AiBlob _part(int blob, int part, int parts, List<int> data, {String? mime}) =>
    AiBlob(
      rid: 1,
      blob: blob,
      part: part,
      parts: parts,
      mime: mime,
      data: Uint8List.fromList(data),
    );

/// A store whose timer is cancelled when the test ends.
AiBlobStore _store({DateTime Function()? now, int phoneBytes = 20 << 20}) {
  final store = AiBlobStore(now: now ?? () => _t0, phoneBytes: phoneBytes);
  addTearDown(store.clear);
  return store;
}

/// V2-2b B12: the images phones upload, in memory until a prompt takes them.
void main() {
  test(
    'parts in any order make the image; peek leaves it, take removes it',
    () {
      final store = _store();
      expect(store.put(_phone, _part(1, 2, 3, [5, 6])), isNull);
      expect(
        store.put(_phone, _part(1, 0, 3, [1, 2], mime: 'image/png')),
        isNull,
      );
      expect(store.complete(_phone, 1), isFalse);
      expect(store.put(_phone, _part(1, 1, 3, [3, 4])), isNull);
      expect(store.complete(_phone, 1), isTrue);
      final image = store.peek(_phone, 1)!;
      expect(image.mime, 'image/png');
      expect(image.bytes, [1, 2, 3, 4, 5, 6]);
      expect(store.heldBy(_phone), 6);
      expect(store.take(_phone, 1)!.bytes, [1, 2, 3, 4, 5, 6]);
      expect(store.take(_phone, 1), isNull);
      expect(store.heldBy(_phone), 0);
    },
  );

  test('a part sent again replaces itself; once whole, the image stays as it '
      'came', () {
    final store = _store();
    store.put(_phone, _part(1, 0, 2, [1, 1, 1], mime: 'image/png'));
    store.put(_phone, _part(1, 0, 2, [9], mime: 'image/png'));
    expect(store.heldBy(_phone), 1);
    store.put(_phone, _part(1, 1, 2, [2]));
    expect(store.peek(_phone, 1)!.bytes, [9, 2]);
    expect(store.put(_phone, _part(1, 1, 2, [7, 7])), isNull);
    expect(store.peek(_phone, 1)!.bytes, [9, 2]);
  });

  test('refused: no parts, a number out of range, nothing or too much in it, '
      'no type on part 0, another count of parts', () {
    final store = _store();
    expect(
      store.put(_phone, _part(1, 0, 0, [1], mime: 'image/png')),
      'refused',
    );
    expect(store.put(_phone, _part(1, 2, 2, [1])), 'refused');
    expect(store.put(_phone, _part(1, -1, 2, [1])), 'refused');
    expect(
      store.put(
        _phone,
        _part(1, 0, AiBlobStore.maxParts + 1, [1], mime: 'image/png'),
      ),
      'refused',
    );
    expect(store.put(_phone, _part(1, 0, 1, [], mime: 'image/png')), 'refused');
    expect(
      store.put(
        _phone,
        AiBlob(
          rid: 1,
          blob: 1,
          part: 0,
          parts: 1,
          mime: 'image/png',
          data: Uint8List(kAiMaxBlobPartBytes + 1),
        ),
      ),
      'refused',
    );
    expect(store.put(_phone, _part(1, 0, 2, [1])), 'refused', reason: 'type');
    expect(store.put(_phone, _part(1, 0, 2, [1], mime: '')), 'refused');
    expect(store.put(_phone, _part(1, 0, 2, [1], mime: 'image/png')), isNull);
    expect(store.put(_phone, _part(1, 1, 3, [1])), 'refused');
  });

  test('a sixth image takes the place of the least recently used one (a '
      "try before's leftovers)", () {
    final store = _store();
    for (var b = 1; b <= kAiImagesMax; b++) {
      expect(store.put(_phone, _part(b, 0, 1, [b], mime: 'image/png')), isNull);
    }
    store.peek(_phone, 1); // used again: image 2 is the least recently used
    expect(store.put(_phone, _part(6, 0, 1, [6], mime: 'image/png')), isNull);
    expect(
      [for (var b = 1; b <= 6; b++) store.complete(_phone, b)],
      [true, false, true, true, true, true],
    );
  });

  test('past what a phone holds, its least recently used images make room; '
      'an image that never fits is too_large and goes, alone', () {
    final store = _store(phoneBytes: 10);
    store.put(_phone, _part(1, 0, 1, List.filled(6, 1), mime: 'image/png'));
    expect(
      store.put(_phone, _part(2, 0, 2, List.filled(6, 2), mime: 'image/png')),
      isNull,
    );
    expect((store.complete(_phone, 1), store.heldBy(_phone)), (false, 6));
    expect(
      store.put(_phone, _part(3, 0, 1, List.filled(11, 3), mime: 'image/png')),
      'too_large',
    );
    expect(store.heldBy(_phone), 6, reason: 'image 2 stays');
  });

  test('too_large: an image over 10 MiB, and it goes', () {
    final big = _store();
    final piece = Uint8List(kAiMaxBlobPartBytes);
    const parts = AiBlobStore.maxParts;
    String? last;
    for (var k = 0; k < parts && last == null; k++) {
      last = big.put(
        _phone,
        AiBlob(
          rid: 1,
          blob: 1,
          part: k,
          parts: parts,
          mime: k == 0 ? 'image/jpeg' : null,
          data: piece,
        ),
      );
    }
    expect(last, 'too_large');
    expect(big.heldBy(_phone), 0);
  });

  test('an image nothing touched for two minutes goes, also without a request '
      '(the timer); a part touches it', () {
    fakeAsync((async) {
      final clock = async.getClock(_t0);
      final store = _store(now: clock.now);
      store.put(_phone, _part(1, 0, 2, [1], mime: 'image/png'));
      async.elapse(const Duration(minutes: 1));
      store.put(_phone, _part(1, 1, 2, [2]));
      async.elapse(const Duration(minutes: 1, seconds: 30));
      expect(store.complete(_phone, 1), isTrue);
      async.elapse(const Duration(minutes: 3));
      expect(store.heldBy(_phone), 0);
    });
  });

  test('a clock set back drops nothing', () {
    var now = _t0;
    final store = _store(now: () => now);
    store.put(_phone, _part(1, 0, 1, [1], mime: 'image/png'));
    now = _t0.subtract(const Duration(hours: 1));
    expect(store.complete(_phone, 1), isTrue);
  });

  test('a phone that leaves takes its images; clear takes all', () {
    final store = _store();
    store
      ..put('a', _part(1, 0, 1, [1], mime: 'image/png'))
      ..put('b', _part(1, 0, 1, [1], mime: 'image/png'));
    store.dropPhone('a');
    expect((store.complete('a', 1), store.complete('b', 1)), (false, true));
    store.clear();
    expect(store.complete('b', 1), isFalse);
  });
}
