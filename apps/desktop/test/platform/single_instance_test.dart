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
}
