import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/paste_sender.dart';

final class FakeSink implements PasteSink {
  FakeSink({this.bracketed = false});
  @override
  bool alive = true;
  @override
  final bool bracketed;
  final pasted = <String>[];
  final sent = <String>[];
  @override
  void paste(String text) => pasted.add(text);
  @override
  void send(String data) => sent.add(data);
  String get all => sent.join();
}

void main() {
  test('a small paste is one Terminal.paste (it brackets itself)', () async {
    final sink = FakeSink(bracketed: true);
    final out = await PasteSender().send(1, 'ls -la\n', sink);
    expect(out, PasteOutcome.sent);
    expect(sink.pasted, ['ls -la\r']);
    expect(sink.sent, isEmpty);
  });

  test('control characters never survive, large or small', () async {
    final sink = FakeSink(bracketed: true);
    await PasteSender().send(1, 'a\x1b[201~rm -rf ~', sink);
    expect(sink.pasted.single, 'a[201~rm -rf ~');
  });

  test('empty clipboard text sends nothing', () async {
    final sink = FakeSink();
    expect(await PasteSender().send(1, '', sink), PasteOutcome.empty);
    expect(await PasteSender().send(1, '\x1b\x07', sink), PasteOutcome.empty);
    expect(sink.pasted, isEmpty);
  });

  test('800 KB goes in 32 KiB pieces 8 ms apart, bracketed once', () {
    fakeAsync((async) {
      final sink = FakeSink(bracketed: true);
      final text = 'x' * 800000;
      PasteOutcome? outcome;
      PasteSender().send(1, text, sink).then((o) => outcome = o);
      async.flushMicrotasks();
      expect(sink.sent.first, '\x1b[200~');
      expect(sink.sent[1].length, 32 * 1024);
      expect(outcome, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(outcome, PasteOutcome.sent);
      expect(sink.sent.last, '\x1b[201~');
      expect(sink.sent.where((s) => s == '\x1b[200~'), hasLength(1));
      final body = sink.sent.sublist(1, sink.sent.length - 1).join();
      expect(body, text);
      expect(sink.sent.length, 2 + (800000 / (32 * 1024)).ceil());
    });
  });

  test('without bracketed paste there are no markers', () {
    fakeAsync((async) {
      final sink = FakeSink();
      PasteSender().send(1, 'y' * 100000, sink);
      async.elapse(const Duration(seconds: 1));
      expect(sink.all, 'y' * 100000);
    });
  });

  test('a surrogate pair is never cut between two pieces', () {
    fakeAsync((async) {
      final sink = FakeSink();
      // 😀 is two UTF-16 units; put it across the 32 KiB boundary.
      final text = '${'a' * (32 * 1024 - 1)}😀${'b' * 70000}';
      PasteSender().send(1, text, sink);
      async.elapse(const Duration(seconds: 1));
      for (final piece in sink.sent) {
        final u = piece.codeUnitAt(piece.length - 1);
        expect(u >= 0xD800 && u <= 0xDBFF, isFalse);
      }
      expect(sink.all, text);
    });
  });

  test('a pane that goes away stops the paste and sends nothing more', () {
    fakeAsync((async) {
      final sink = FakeSink(bracketed: true);
      PasteOutcome? outcome;
      PasteSender().send(1, 'z' * 400000, sink).then((o) => outcome = o);
      async.elapse(const Duration(milliseconds: 20));
      final before = sink.sent.length;
      sink.alive = false;
      async.elapse(const Duration(seconds: 2));
      expect(outcome, PasteOutcome.cancelled);
      expect(sink.sent.length, before);
      expect(sink.sent.contains('\x1b[201~'), isFalse);
    });
  });

  test(
    'cancel on a live pane closes the bracket so the program is not stuck',
    () {
      fakeAsync((async) {
        final sender = PasteSender();
        final sink = FakeSink(bracketed: true);
        PasteOutcome? outcome;
        sender.send(1, 'z' * 400000, sink).then((o) => outcome = o);
        async.elapse(const Duration(milliseconds: 20));
        sender.cancel(1);
        async.elapse(const Duration(seconds: 2));
        expect(outcome, PasteOutcome.cancelled);
        expect(sink.sent.last, '\x1b[201~');
      });
    },
  );

  test('two pastes into one pane run one after the other', () {
    fakeAsync((async) {
      final sender = PasteSender();
      final sink = FakeSink();
      sender.send(1, 'a' * 100000, sink);
      sender.send(1, 'b' * 100000, sink);
      async.elapse(const Duration(seconds: 2));
      expect(sink.all, '${'a' * 100000}${'b' * 100000}');
    });
  });

  test('above 1 MiB the user is asked; no means nothing is sent', () async {
    final sink = FakeSink();
    int? asked;
    final out = await PasteSender().send(
      1,
      'q' * (1024 * 1024 + 1),
      sink,
      confirm: (bytes) async {
        asked = bytes;
        return false;
      },
    );
    expect(out, PasteOutcome.declined);
    expect(asked, 1024 * 1024 + 1);
    expect(sink.sent, isEmpty);
    expect(sink.pasted, isEmpty);
  });

  test('over 16 MiB is refused without asking', () async {
    final sink = FakeSink();
    var asked = false;
    final out = await PasteSender().send(
      1,
      'q' * (16 * 1024 * 1024 + 1),
      sink,
      confirm: (_) async => asked = true,
    );
    expect(out, PasteOutcome.tooLarge);
    expect(asked, isFalse);
  });

  test('the pane may be gone by the time the user confirms', () async {
    final sink = FakeSink();
    final out = await PasteSender().send(
      1,
      'q' * (1024 * 1024 + 1),
      sink,
      confirm: (_) async {
        sink.alive = false;
        return true;
      },
    );
    expect(out, PasteOutcome.cancelled);
    expect(sink.sent, isEmpty);
  });

  test('a write that throws ends the paste cleanly and closes the bracket', () {
    fakeAsync((async) {
      final sink = _ThrowingSink(failAfter: 3);
      PasteOutcome? outcome;
      Object? error;
      PasteSender()
          .send(1, 'w' * 400000, sink)
          .then((o) => outcome = o, onError: (Object e) => error = e);
      async.elapse(const Duration(seconds: 2));
      expect(error, isNull);
      expect(outcome, PasteOutcome.cancelled);
      expect(sink.sent.last, '\x1b[201~');
    });
  });

  test('a small paste that throws is cancelled, not an error', () async {
    final sink = _ThrowingSink(failAfter: 0);
    expect(await PasteSender().send(1, 'abc', sink), PasteOutcome.cancelled);
  });

  test('cancel on an idle pane does not cancel the next paste', () {
    fakeAsync((async) {
      final sender = PasteSender()..cancel(1);
      final sink = FakeSink();
      PasteOutcome? outcome;
      sender.send(1, 'n' * 100000, sink).then((o) => outcome = o);
      async.elapse(const Duration(seconds: 2));
      expect(outcome, PasteOutcome.sent);
      expect(sink.all, 'n' * 100000);
    });
  });

  test('pieces are 32 KiB of UTF-8, never splitting a code point', () {
    fakeAsync((async) {
      for (final unit in ['日', 'ệ', '😀', 'é']) {
        final sink = FakeSink();
        final text = unit * 60000;
        PasteSender().send(1, text, sink);
        async.elapse(const Duration(seconds: 2));
        expect(sink.all, text);
        for (final p in sink.sent) {
          expect(utf8.encode(p).length, lessThanOrEqualTo(32 * 1024));
          expect(p.runes.every((r) => r != 0xFFFD), isTrue);
        }
        expect(sink.sent.length, greaterThan(1));
      }
    });
  });

  test('the threshold counts UTF-8 bytes: 400 000 × 日 asks', () async {
    final sink = FakeSink();
    int? asked;
    final out = await PasteSender().send(
      1,
      '日' * 400000,
      sink,
      confirm: (bytes) async {
        asked = bytes;
        return false;
      },
    );
    expect(out, PasteOutcome.declined);
    expect(asked, 1200000);
  });

  test('whenIdle waits for the pastes queued so far', () {
    fakeAsync((async) {
      final sender = PasteSender();
      final sink = FakeSink();
      sender.send(1, 'a' * 200000, sink);
      var idle = false;
      sender.whenIdle(1).then((_) => idle = true);
      async.elapse(const Duration(milliseconds: 5));
      expect(idle, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(idle, isTrue);
    });
  });
}

final class _ThrowingSink extends FakeSink {
  _ThrowingSink({required this.failAfter}) : super(bracketed: true);
  final int failAfter;
  int _n = 0;
  @override
  void send(String data) {
    if (++_n > failAfter && data != '\x1b[201~') throw StateError('gone');
    super.send(data);
  }

  @override
  void paste(String text) => throw StateError('gone');
}
