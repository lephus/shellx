import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

ClientTab newTab(List<AckMessage> acks) => ClientTab(
  id: 3,
  index: 1,
  shell: 'zsh',
  cols: 80,
  rows: 24,
  sendAck: acks.add,
);

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// Delivers [data] as consecutive output messages cut at [cuts].
void deliver(ClientTab tab, List<int> data, List<int> cuts, {int from = 0}) {
  var start = 0;
  for (final cut in [...cuts, data.length]) {
    tab.handleOutput(from + start, bytes(data.sublist(start, cut)));
    start = cut;
  }
}

String textOf(List<TabEvent> events) =>
    events.whereType<TabOutput>().map((e) => e.text).join();

void main() {
  test('multi-byte characters split across output messages decode whole', () {
    fakeAsync((async) {
      final tab = newTab([]);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      final data = utf8.encode('Việt Nam 😀!');
      // Cut inside "ệ" (3 bytes) and inside the emoji (4 bytes).
      final e = utf8.encode('Vi').length;
      final emoji = utf8.encode('Việt Nam ').length;
      deliver(tab, data, [e + 1, e + 2, emoji + 1, emoji + 3]);
      async.flushMicrotasks();

      expect(textOf(events), 'Việt Nam 😀!');
      expect(textOf(events), isNot(contains('�')));
      expect(tab.received, data.length);
    });
  });

  test(
    'a reset drops a half-received character and starts a fresh decoder',
    () {
      fakeAsync((async) {
        final tab = newTab([]);
        final events = <TabEvent>[];
        tab.events.listen(events.add);
        final e = utf8.encode('ệ');
        tab.handleOutput(0, bytes([0x61, e[0]])); // "a" + first byte of "ệ"
        tab.handleReset();
        tab.handleOutput(500, bytes(utf8.encode('ok')));
        async.flushMicrotasks();

        expect(events.map((e) => e.runtimeType), [
          TabOutput,
          TabReset,
          TabOutput,
        ]);
        expect(textOf(events), 'aok');
        expect(textOf(events), isNot(contains('�')));
        expect(tab.received, 502);
      });
    },
  );

  test('received follows seq; duplicates and overlaps are not shown twice', () {
    fakeAsync((async) {
      final tab = newTab([]);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      tab.handleOutput(0, bytes(utf8.encode('abcd')));
      tab.handleOutput(0, bytes(utf8.encode('abcd')));
      tab.handleOutput(2, bytes(utf8.encode('cdef')));
      async.flushMicrotasks();
      expect(textOf(events), 'abcdef');
      expect(tab.received, 6);
    });
  });

  test(
    'acks after 32 KiB immediately, otherwise 100 ms after the last output',
    () {
      fakeAsync((async) {
        final acks = <AckMessage>[];
        final tab = newTab(acks);
        tab.handleOutput(0, Uint8List(10));
        async.elapse(const Duration(milliseconds: 60));
        tab.handleOutput(10, Uint8List(10));
        async.elapse(const Duration(milliseconds: 99));
        expect(acks, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect([for (final a in acks) (a.id, a.seq)], [(3, 20)]);

        tab.handleOutput(20, Uint8List(32 * 1024));
        expect(acks.last.seq, 20 + 32 * 1024);
        async.elapse(const Duration(seconds: 1));
        expect(acks, hasLength(2));
      });
    },
  );

  test('beginAttach counts everything received as acknowledged', () {
    fakeAsync((async) {
      final acks = <AckMessage>[];
      final tab = newTab(acks);
      tab.handleOutput(0, Uint8List(100));
      tab.beginAttach();
      async.elapse(const Duration(seconds: 1));
      expect(acks, isEmpty);
    });
  });

  test('detached, exited and error end the tab and stop acks', () {
    fakeAsync((async) {
      final acks = <AckMessage>[];
      final tab = newTab(acks);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      tab.handleOutput(0, Uint8List(10));
      tab.handleDetached(DetachReason.takenOver);
      async.elapse(const Duration(seconds: 1));
      expect(tab.isAttached, isFalse);
      expect(acks, isEmpty);

      tab.beginAttach();
      expect(tab.isAttached, isTrue);
      tab.handleExited(0);
      expect(tab.isAttached, isFalse);
      tab.beginAttach();
      tab.handleError(AppErrorCode.sessionNotFound, 'gone');
      expect(tab.isAttached, isFalse);
      async.flushMicrotasks();
      expect(events.map((e) => e.runtimeType), [
        TabOutput,
        TabDetached,
        TabExited,
        TabError,
      ]);
    });
  });

  // Final review M4.
  test('held keystrokes keep the newest 64 KiB and are dropped when the tab '
      'ends', () {
    final tab = newTab([]);
    final paste = bytes(List.filled(60 << 10, 0x61));
    tab.holdInput(paste);
    paste[0] = 0x7a; // The caller reuses its buffer: the held copy is kept.
    tab.holdInput(bytes(List.filled(8 << 10, 0x62)));
    expect(tab.takeHeldInput(), [
      ...List.filled(56 << 10, 0x61),
      ...List.filled(8 << 10, 0x62),
    ]);
    expect(tab.hasHeldInput, isFalse);

    tab.holdInput(bytes([0x63]));
    tab.handleDetached(DetachReason.takenOver);
    expect(tab.hasHeldInput, isFalse);
    tab.beginAttach(); // Re-attached later: nothing old is sent.
    expect(tab.takeHeldInput(), isEmpty);
  });

  test('events emitted before the first listener are replayed to it', () {
    fakeAsync((async) {
      final tab = newTab([]);
      tab.handleReset();
      tab.handleOutput(0, bytes(utf8.encode('replayed')));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      async.flushMicrotasks();
      expect(events.first, isA<TabReset>());
      expect(textOf(events), 'replayed');
    });
  });
}
