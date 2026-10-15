import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, [int seed = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * 31 + seed) & 0xFF,
]);

/// V2-4 E7, E8: windows, acknowledgements, pacing; byte and WebSocket
/// streams in and out.
void main() {
  group('windows (E7)', () {
    test('a stream stops at 256 KiB in flight, a phone at 512 KiB', () {
      final credit = ToolCredit();
      final a = ToolSendWindow(credit);
      final b = ToolSendWindow(credit);
      final c = ToolSendWindow(credit);
      a.onSent(kToolStreamWindow);
      expect(a.canSend(1), isFalse);
      b.onSent(kToolStreamWindow);
      expect(c.canSend(1), isFalse, reason: 'the phone has 512 KiB in flight');
      expect(a.onAck(1024), isTrue);
      expect(c.canSend(1024), isTrue);
      expect(c.canSend(1025), isFalse);
    });

    test(
      'an ack beyond what was sent is refused; closing frees the window',
      () {
        final credit = ToolCredit();
        final a = ToolSendWindow(credit)..onSent(100);
        expect(a.onAck(101), isFalse);
        expect(a.onAck(50), isTrue);
        expect(a.onAck(40), isTrue, reason: 'an old ack changes nothing');
        expect(credit.inFlight, 50);
        a.close();
        expect(credit.inFlight, 0);
        expect(a.canSend(1), isFalse, reason: 'a closed stream sends nothing');
      },
    );
  });

  group('ack book (E8)', () {
    test('every stream in one tool.ack, at most one per 50 ms', () {
      fakeAsync((async) {
        final sent = <ToolAck>[];
        final book = ToolAckBook(sent.add);
        book.consumed(1, 10);
        book.consumed(2, 5);
        book.consumed(1, 30);
        book.consumed(1, 20); // older: ignored
        async.elapse(const Duration(milliseconds: 49));
        expect(sent, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(sent.single.acks, [1, 30, 2, 5]);
        book.consumed(2, 9);
        book.forget(2);
        book.consumed(3, 1);
        async.elapse(const Duration(milliseconds: 50));
        expect(sent.last.acks, [3, 1]);
        expect(sent, hasLength(2));
        book.consumed(4, 1);
        book.clear();
        async.elapse(const Duration(seconds: 1));
        expect(sent, hasLength(2));
      });
    });
  });

  group('token pacer (E7, RF 2)', () {
    test('≤ 150 frames and ≤ 8 MiB per second, whatever is asked', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(clock: () => async.elapsed.inMicroseconds);
        final grants = <Duration>[];
        var bytes = 0;
        // Three greedy streams of full frames for 10 s.
        void stream() {
          pacer.acquire(() {
            grants.add(async.elapsed);
            bytes += kToolMaxChunkBytes;
            scheduleMicrotask(stream);
            return kToolMaxChunkBytes;
          });
        }

        stream();
        stream();
        stream();
        async.elapse(const Duration(seconds: 10));
        expect(grants.length, lessThanOrEqualTo(16 + 150 * 10));
        expect(
          bytes,
          lessThanOrEqualTo((1 + 8 * 10) * 1024 * 1024 + kToolMaxChunkBytes),
        );
        // Busy, it still sends: at least 90% of the rate (full frames reach
        // 150 × 48 KiB a second, a little under 8 MiB).
        const rate = 150 * kToolMaxChunkBytes;
        expect(bytes, greaterThan(rate * 10 * 0.9));
        // Any one second holds at most a burst over the rate.
        for (var s = 0; s < 9; s++) {
          final inSecond = grants
              .where(
                (t) =>
                    t >= Duration(seconds: s) && t < Duration(seconds: s + 1),
              )
              .length;
          expect(inSecond, lessThanOrEqualTo(150 + 16), reason: 'second $s');
        }
      });
    });

    test('small frames are limited by count: 150 per second', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(clock: () => async.elapsed.inMicroseconds);
        var frames = 0;
        void stream() {
          pacer.acquire(() {
            frames++;
            scheduleMicrotask(stream);
            return 10;
          });
        }

        stream();
        async.elapse(const Duration(seconds: 4));
        expect(frames, lessThanOrEqualTo(16 + 150 * 4));
        expect(frames, greaterThan(150 * 4 * 0.9));
      });
    });

    test('in order; a withdrawn request is never granted; nothing sent, '
        'nothing charged', () {
      fakeAsync((async) {
        final pacer = ToolTokenPacer(
          framesPerSecond: 10,
          frameBurst: 1,
          clock: () => async.elapsed.inMicroseconds,
        );
        final order = <String>[];
        pacer.acquire(() {
          order.add('a');
          return 1;
        });
        pacer.acquire(() {
          order.add('b');
          return 1;
        });
        final withdraw = pacer.acquire(() {
          order.add('c');
          return 1;
        });
        pacer.acquire(() {
          order.add('d');
          return null; // sent nothing: the next one gets this frame
        });
        pacer.acquire(() {
          order.add('e');
          return 1;
        });
        withdraw();
        async.elapse(const Duration(milliseconds: 100));
        expect(order, ['a', 'b'], reason: 'one frame per 100 ms');
        async.elapse(const Duration(milliseconds: 100));
        expect(order, ['a', 'b', 'd', 'e']);
      });
    });
  });

  group('bytes out (E7, RF 3)', () {
    test('never more than the window in flight; the source pauses and every '
        'byte arrives once, in order', () {
      fakeAsync((async) {
        final source = StreamController<List<int>>();
        var pauses = 0;
        source.onPause = () => pauses++;
        final body = _bytes(1024 * 1024 + 17);
        final credit = ToolCredit();
        final window = ToolSendWindow(credit);
        final got = BytesBuilder();
        var ended = false;
        var maxInFlight = 0;
        late ToolBytesOut out;
        out = ToolBytesOut(
          id: 3,
          source: source.stream,
          window: window,
          pacer: const ToolUnpaced(),
          send: (m) {
            final data = m as ToolData;
            expect(data.data.length, lessThanOrEqualTo(kToolMaxChunkBytes));
            got.add(data.data);
            ended = data.end;
            if (window.inFlight > maxInFlight) maxInFlight = window.inFlight;
          },
        )..start();
        for (var at = 0; at < body.length; at += 7000) {
          source.add(
            body.sublist(at, at + 7000 > body.length ? body.length : at + 7000),
          );
        }
        unawaited(source.close());
        async.flushMicrotasks();
        // The peer acknowledges slowly, a little at a time.
        var acked = 0;
        while (!ended) {
          async.elapse(const Duration(milliseconds: 10));
          acked = got.length < acked + 40000 ? got.length : acked + 40000;
          expect(out.onAck(acked), isTrue);
          async.flushMicrotasks();
        }
        expect(maxInFlight, lessThanOrEqualTo(kToolStreamWindow));
        expect(pauses, greaterThan(0));
        expect(got.takeBytes(), body);
      });
    });

    test('streams share the phone\'s 512 KiB', () {
      fakeAsync((async) {
        final credit = ToolCredit();
        final windows = [
          ToolSendWindow(credit),
          ToolSendWindow(credit),
          ToolSendWindow(credit),
        ];
        var peak = 0;
        for (final (i, window) in windows.indexed) {
          final source = StreamController<List<int>>();
          ToolBytesOut(
            id: i,
            source: source.stream,
            window: window,
            pacer: const ToolUnpaced(),
            send: (_) {
              if (credit.inFlight > peak) peak = credit.inFlight;
            },
          ).start();
          source.add(_bytes(400 * 1024));
        }
        async.flushMicrotasks();
        expect(peak, lessThanOrEqualTo(kToolPhoneWindow));
        expect(
          credit.inFlight,
          greaterThan(kToolPhoneWindow - kToolMaxChunkBytes),
        );
        // One stream's ack lets another go on.
        windows[0].onAck(windows[0].sent);
        async.flushMicrotasks();
        expect(peak, lessThanOrEqualTo(kToolPhoneWindow));
        expect(
          windows[1].sent + windows[2].sent,
          greaterThan(kToolPhoneWindow - windows[0].sent),
        );
      });
    });

    test('an empty body is one empty piece with end; a body over its limit '
        'stops reading', () {
      fakeAsync((async) {
        final sent = <ToolData>[];
        final empty = StreamController<List<int>>();
        ToolBytesOut(
          id: 1,
          source: empty.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (m) => sent.add(m as ToolData),
        ).start();
        unawaited(empty.close());
        async.flushMicrotasks();
        expect(sent.single.end, isTrue);
        expect(sent.single.data, isEmpty);

        final big = StreamController<List<int>>();
        var cancelled = false;
        big.onCancel = () => cancelled = true;
        var tooLarge = false;
        ToolBytesOut(
          id: 2,
          source: big.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (_) {},
          maxBytes: 1000,
          onTooLarge: () => tooLarge = true,
        ).start();
        big.add(_bytes(600));
        big.add(_bytes(600));
        async.flushMicrotasks();
        expect(tooLarge, isTrue);
        expect(cancelled, isTrue);
      });
    });
  });

  group('bytes in (E7)', () {
    test('what the sink takes is reported; more than the window, after the '
        'end or past the limit is refused', () async {
      final consumed = <int>[];
      final inlet = ToolBytesIn(onConsumed: consumed.add, maxBytes: 100);
      final sink = <int>[];
      final done = inlet.stream.forEach(sink.addAll);
      expect(inlet.add(_bytes(60), end: false), isTrue);
      expect(inlet.add(_bytes(40), end: true), isTrue);
      expect(inlet.add(_bytes(1), end: true), isFalse);
      await done;
      expect(sink, hasLength(100));
      expect(consumed.last, 100);

      final small = ToolBytesIn(onConsumed: (_) {}, window: 10);
      // Nobody takes the bytes yet: 11 in flight is more than the window.
      expect(small.add(_bytes(10), end: false), isTrue);
      expect(small.add(_bytes(1), end: false), isFalse);

      final limited = ToolBytesIn(onConsumed: (_) {}, maxBytes: 5);
      expect(limited.add(_bytes(6), end: false), isFalse);
    });

    test('fail cuts the sink with an error', () async {
      final inlet = ToolBytesIn(onConsumed: (_) {});
      final done = inlet.stream.drain<void>();
      inlet.add(_bytes(3), end: false);
      inlet.fail(StateError('cut'));
      await expectLater(done, throwsStateError);
    });
  });

  group('WebSocket out and in (E7, E10)', () {
    test(
      'a long message goes in pieces, the last with fin; text stays text',
      () {
        fakeAsync((async) {
          final source = StreamController<Object?>();
          final window = ToolSendWindow(ToolCredit());
          final pieces = <ToolWsMessage>[];
          final out = ToolWsOut(
            id: 5,
            source: source.stream,
            window: window,
            pacer: const ToolUnpaced(),
            send: (m) => pieces.add(m as ToolWsMessage),
          )..start();
          final long = 'ả' * 100000; // 300 000 UTF-8 bytes
          source
            ..add(long)
            ..add(Uint8List.fromList([1, 2]));
          async.flushMicrotasks();
          // 256 KiB went out; the rest waits for an ack.
          expect(window.inFlight, lessThanOrEqualTo(kToolStreamWindow));
          out.onAck(window.sent);
          async.flushMicrotasks();
          expect(pieces.where((p) => p.fin), hasLength(2));
          final text = pieces.where((p) => p.text).toList();
          expect(
            text.every((p) => p.data.length <= kToolMaxChunkBytes),
            isTrue,
          );
          expect(text.last.fin, isTrue);
          expect(utf8.decode([for (final p in text) ...p.data]), long);
          expect(pieces.last.text, isFalse);
          expect(pieces.last.data, [1, 2]);
        });
      },
    );

    test('a message over 16 MiB stops the stream (close 1009)', () {
      fakeAsync((async) {
        final source = StreamController<Object?>();
        var tooBig = false;
        ToolWsOut(
          id: 1,
          source: source.stream,
          window: ToolSendWindow(ToolCredit()),
          pacer: const ToolUnpaced(),
          send: (_) {},
          onTooBig: () => tooBig = true,
        ).start();
        source.add(Uint8List(kToolMaxWsMessageBytes + 1));
        async.flushMicrotasks();
        expect(tooBig, isTrue);
      });
    });

    test('pieces are put together and written in order; what follows a '
        'message waiting to be written is not acknowledged', () async {
      final written = <Object>[];
      final consumed = <int>[];
      final gate = Completer<void>();
      final inlet = ToolWsIn(
        write: (m) async {
          written.add(m);
          if (written.length == 1) await gate.future;
        },
        onConsumed: consumed.add,
      );
      final hello = utf8.encode('hello');
      expect(
        inlet.add(
          ToolWsMessage(
            id: 1,
            data: Uint8List.sublistView(hello, 0, 2),
            text: true,
            fin: false,
          ),
        ),
        isTrue,
      );
      expect(consumed, [2], reason: 'a message being put together is taken');
      expect(
        inlet.add(
          ToolWsMessage(
            id: 1,
            data: Uint8List.sublistView(hello, 2),
            text: true,
            fin: true,
          ),
        ),
        isTrue,
      );
      expect(written, ['hello']);
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: false, fin: true),
        ),
        isTrue,
      );
      expect(consumed, [2], reason: 'held while "hello" waits for the socket');
      gate.complete();
      await inlet.idle;
      expect(written, hasLength(2));
      expect(consumed.last, 9);
    });

    test('a piece that changes the kind, or a message over the limit, is '
        'refused', () {
      final inlet = ToolWsIn(
        write: (_) async {},
        onConsumed: (_) {},
        maxMessage: 10,
      );
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: true, fin: false),
        ),
        isTrue,
      );
      expect(
        inlet.add(
          ToolWsMessage(id: 1, data: Uint8List(4), text: false, fin: true),
        ),
        isFalse,
      );
      final small = ToolWsIn(
        write: (_) async {},
        onConsumed: (_) {},
        maxMessage: 10,
      );
      expect(
        small.add(
          ToolWsMessage(id: 1, data: Uint8List(6), text: false, fin: false),
        ),
        isTrue,
      );
      expect(
        small.add(
          ToolWsMessage(id: 1, data: Uint8List(6), text: false, fin: true),
        ),
        isFalse,
      );
    });
  });
}
