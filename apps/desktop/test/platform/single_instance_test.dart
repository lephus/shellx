import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/single_instance.dart';

Future<String> _probe(String lockPath) async {
  final result = await Process.run('dart', [
    'test/fixtures/lock_probe.dart',
    lockPath,
  ]);
  return (result.stdout as String).trim();
}

void main() {
  late Directory dir;

  setUp(
    () async => dir = await Directory.systemTemp.createTemp('shellx-lock-'),
  );
  tearDown(() async => dir.delete(recursive: true));

  test(
    'a second process cannot take the lock until the first releases it',
    () async {
      final lock = SingleInstanceLock(dir);
      expect(await lock.acquire(), isTrue);
      expect(await _probe(lock.lockPath), 'busy');
      await lock.release();
      expect(await _probe(lock.lockPath), 'acquired');
    },
  );

  test(
    'a second launch can ask the running instance to come forward',
    () async {
      final lock = SingleInstanceLock(dir);
      expect(await lock.acquire(), isTrue);
      final request = lock.activationRequests().first;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await SingleInstanceLock(dir).signalRunningInstance();
      await request.timeout(const Duration(seconds: 10));
      await lock.release();
    },
  );

  test('one second launch is one activation request', () async {
    final lock = SingleInstanceLock(dir);
    expect(await lock.acquire(), isTrue);
    var requests = 0;
    final first = Completer<void>();
    final subscription = lock.activationRequests().listen((_) {
      requests++;
      if (!first.isCompleted) first.complete();
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await SingleInstanceLock(dir).signalRunningInstance();
    // However slow the watcher is, the request arrives...
    await first.future.timeout(const Duration(seconds: 10));
    // ...and the rest of that launch's events (the signal file's creation
    // and its write may come separately) are all dropped.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(requests, 1);
    await subscription.cancel();
    await lock.release();
  });

  test('coalesceEvents passes the first event of a burst and drops the '
      'rest of it', () async {
    var now = DateTime(2026, 9, 26);
    final source = StreamController<void>(sync: true);
    final passed = <DateTime>[];
    coalesceEvents(
      source.stream,
      window: const Duration(seconds: 1),
      now: () => now,
    ).listen((_) => passed.add(now));
    final start = now;

    source.add(null); // create
    now = now.add(const Duration(milliseconds: 5));
    source.add(null); // modify, same launch
    now = start.add(const Duration(milliseconds: 999));
    source.add(null);
    now = start.add(const Duration(seconds: 1));
    source.add(null); // a later launch
    await source.close();

    expect(passed, [start, start.add(const Duration(seconds: 1))]);
  });

  test(
    'activation events require an exact file name match, not just a suffix',
    () async {
      final lock = SingleInstanceLock(dir);
      expect(await lock.acquire(), isTrue);
      final events = <void>[];
      final subscription = lock.activationRequests().listen(events.add);
      await File(
        '${dir.path}${Platform.pathSeparator}notactivate.signal',
      ).writeAsString('x', flush: true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(events, isEmpty);
      await subscription.cancel();
      await lock.release();
    },
  );

  File quitSignal() => File(
    '${dir.path}${Platform.pathSeparator}${SingleInstanceLock.quitFileName}',
  );

  test('the installer can ask the running instance to quit (A5a I1)', () async {
    final lock = SingleInstanceLock(dir);
    expect(await lock.acquire(), isTrue);
    final request = lock.quitRequests().first;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await quitSignal().writeAsString('1', flush: true);
    await request.timeout(const Duration(seconds: 10));
    await lock.release();
  });

  test('a quit signal is not an activation request, nor the reverse', () async {
    final lock = SingleInstanceLock(dir);
    expect(await lock.acquire(), isTrue);
    final activations = <void>[];
    final quits = <void>[];
    final a = lock.activationRequests().listen(activations.add);
    final q = lock.quitRequests().listen(quits.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await quitSignal().writeAsString('1', flush: true);
    await SingleInstanceLock(dir).signalRunningInstance();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((activations.isEmpty || quits.isEmpty) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(activations, hasLength(1));
    expect(quits, hasLength(1));
    await a.cancel();
    await q.cancel();
    await lock.release();
  });

  test('a quit signal left from an earlier run is deleted when the lock is '
      'taken, so it never quits the new instance (A5a I1)', () async {
    await quitSignal().writeAsString('old', flush: true);
    final lock = SingleInstanceLock(dir);
    expect(await lock.acquire(), isTrue);
    expect(quitSignal().existsSync(), isFalse);
    final quits = <void>[];
    final q = lock.quitRequests().listen(quits.add);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(quits, isEmpty);
    await q.cancel();
    await lock.release();
  });
}
