import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/match_scanner.dart';

/// A worker that fails on every text it is given.
void _crashingWorker((SendPort, String) args) {
  final (reply, _) = args;
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((_) => throw StateError('boom'));
}

void main() {
  test('finds the first match off the UI isolate', () async {
    final s = IsolateMatchScanner(r'b+');
    addTearDown(s.close);
    expect(await s.scan('aabbbc'), (start: 2, end: 5));
    expect(await s.scan('aaa'), isNull);
  });

  test('a worker that fails is an internal error, not "too slow"', () async {
    final s = IsolateMatchScanner(
      'a',
      limit: const Duration(seconds: 5),
      worker: _crashingWorker,
    );
    addTearDown(s.close);
    final watch = Stopwatch()..start();
    await expectLater(
      s.scan('a'),
      throwsA(
        isA<CliFailure>()
            .having((f) => f.code, 'code', MuxError.internal)
            .having((f) => f.message, 'message', isNot(contains('slow'))),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
  });
}
