import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

final class _Rig {
  _Rig({int capacity = 64, int window = 1024}) {
    stream = SessionStream(
      id: 5,
      capacity: capacity,
      sendWindow: window,
      send: (mobileId, message) => sent.add((mobileId, message)),
    );
  }
  late final SessionStream stream;
  final sent = <(String, AppMessage)>[];
  List<AppMessage> to(String m) => [
    for (final (id, msg) in sent)
      if (id == m) msg,
  ];
  String text(String m) => utf8.decode([
    for (final msg in to(m).whereType<OutputMessage>()) ...msg.data,
  ]);
}

void main() {
  test('append does not send; pump sends to the attached phone', () {
    final rig = _Rig();
    rig.stream.attach('p', 0);
    rig.stream.append(_b('hello'));
    expect(rig.to('p'), isEmpty);
    rig.stream.pump();
    expect(rig.text('p'), 'hello');
    expect(rig.stream.drained, isTrue);
  });

  test('attach replays from last_seq inside the buffer', () {
    final rig = _Rig()..stream.append(_b('0123456789'));
    rig.stream.attach('p', 4);
    expect(rig.text('p'), '456789');
    expect(rig.to('p').whereType<SessionReset>(), isEmpty);
    expect((rig.to('p').first as OutputMessage).seq, 4);
  });

  test('attach outside the buffer resets and replays from start', () {
    final rig = _Rig(capacity: 4)..stream.append(_b('0123456789'));
    rig.stream.attach('p', 1);
    expect(rig.to('p').first, const SessionReset(id: 5));
    expect(rig.text('p'), '6789');
  });

  test('a second phone takes over and the first gets taken_over', () {
    final rig = _Rig();
    rig.stream.attach('a', 0);
    expect(rig.stream.attach('b', 0), 'a');
    expect(
      rig.to('a').single,
      const SessionDetached(id: 5, reason: DetachReason.takenOver),
    );
    expect(rig.stream.attachedMobileId, 'b');
  });

  test('the send window holds output until acked', () {
    final rig = _Rig(window: 4);
    rig.stream.attach('p', 0);
    rig.stream
      ..append(_b('abcdefgh'))
      ..pump();
    expect(rig.text('p'), 'abcd');
    rig.stream
      ..ack(4)
      ..pump();
    expect(rig.text('p'), 'abcdefgh');
  });

  test('restartWith resets the attached phone and replays the new bytes', () {
    final rig = _Rig()..stream.append(_b('old screen'));
    rig.stream.attach('p', 0);
    rig.sent.clear();
    rig.stream.restartWith(_b('snapshot'));
    rig.stream.pump();
    expect(rig.to('p').first, const SessionReset(id: 5));
    expect(rig.text('p'), 'snapshot');
    expect((rig.to('p')[1] as OutputMessage).seq, 10);
  });

  test('restartWith with nobody attached sends nothing', () {
    final rig = _Rig()..stream.append(_b('x'));
    rig.stream.restartWith(_b('y'));
    expect(rig.sent, isEmpty);
    expect(rig.stream.start, 1);
    expect(rig.stream.end, 2);
  });

  test('sessionIdAllocator starts in [1, 2^31) and counts up', () {
    final next = sessionIdAllocator(Random(1));
    final first = next();
    expect(first, inInclusiveRange(1, (1 << 31) - 1));
    expect(next(), first + 1);
    expect(next(), first + 2);
  });
}
