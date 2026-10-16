import 'dart:async';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  test('runs one at a time, in the order queued', () async {
    final queue = SerialQueue();
    final log = <String>[];
    final gate = Completer<void>();
    Future<void> op(String name, [Future<void>? wait]) => queue.run(() async {
      log.add('start $name');
      await wait;
      log.add('end $name');
    });

    final all = Future.wait([op('a', gate.future), op('b'), op('c')]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(log, ['start a'], reason: 'b and c wait for a to finish');
    gate.complete();
    await all;
    expect(log, ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
  });

  test('hands each caller its own result', () async {
    final queue = SerialQueue();
    final results = await Future.wait([
      queue.run(() async => 1),
      queue.run(() async => 'two'),
      queue.run(
        () => Future.delayed(const Duration(milliseconds: 10), () => 3),
      ),
    ]);
    expect(results, [1, 'two', 3]);
  });

  test('a failure reaches its caller and does not block the next', () async {
    final queue = SerialQueue();
    final order = <String>[];
    final failed = expectLater(
      queue.run<void>(() async {
        order.add('async failure');
        throw StateError('boom');
      }),
      throwsStateError,
    );
    final failedSync = expectLater(
      queue.run<void>(() {
        order.add('sync failure');
        throw ArgumentError('thrown before any future');
      }),
      throwsArgumentError,
    );
    final after = queue.run(() async {
      order.add('after');
      return 42;
    });
    await failed;
    await failedSync;
    expect(await after, 42);
    expect(order, ['async failure', 'sync failure', 'after']);
  });

  test('an operation queued from inside another waits for it to end', () async {
    final queue = SerialQueue();
    final log = <String>[];
    final gate = Completer<void>();
    late Future<void> inner;
    final outer = queue.run(() async {
      log.add('outer start');
      inner = queue.run(() async => log.add('inner'));
      await gate.future;
      log.add('outer end');
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(log, ['outer start'], reason: 'inner waits for outer to end');
    gate.complete();
    await Future.wait([outer, inner]);
    expect(log, ['outer start', 'outer end', 'inner']);
  });
}
