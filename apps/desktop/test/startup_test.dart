import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/startup.dart';

final class _Exited implements Exception {
  const _Exited(this.code);
  final int code;
}

Matcher _exitedWith(int code) =>
    throwsA(isA<_Exited>().having((e) => e.code, 'code', code));

const _short = Duration(milliseconds: 50);

void main() {
  group('runGuardedStartup', () {
    late List<String> steps;
    late List<String> logs;

    Future<void> guarded(
      Future<void> Function() start, {
      Future<void> Function()? releaseLock,
      Future<void> Function()? showError,
    }) => runGuardedStartup(
      start: start,
      releaseLock:
          releaseLock ??
          () async {
            steps.add('release');
          },
      showError:
          showError ??
          () async {
            steps.add('show');
          },
      exit: (code) {
        steps.add('exit $code');
        throw _Exited(code);
      },
      log: logs.add,
      stepTimeout: _short,
    );

    setUp(() {
      steps = [];
      logs = [];
    });

    test('a successful start does nothing else', () async {
      await guarded(() async => steps.add('start'));
      expect(steps, ['start']);
      expect(logs, isEmpty);
    });

    test('a failed start releases the lock, shows the error and exits 1, '
        'logging the error type only', () async {
      await expectLater(
        guarded(() async => throw StateError('token=SECRET')),
        _exitedWith(1),
      );
      // The lock goes first: a relaunch while the error is still on screen
      // (Windows MessageBox blocks) must not be turned away.
      expect(steps, ['release', 'show', 'exit 1']);
      expect(logs, ['ShellX: startup failed: StateError']);
    });

    test('a synchronous throw is caught too', () async {
      await expectLater(
        guarded(() => throw const FormatException('SECRET')),
        _exitedWith(1),
      );
      expect(steps.last, 'exit 1');
    });

    test('failing or hanging cleanup still exits', () async {
      await expectLater(
        guarded(
          () async => throw StateError('x'),
          releaseLock: () => Completer<void>().future,
          showError: () async => throw Exception('notifications denied'),
        ),
        _exitedWith(1),
      );
      expect(steps, ['exit 1']);
      expect(logs, [
        'ShellX: startup failed: StateError',
        'ShellX: releasing the lock failed: TimeoutException',
        'ShellX: showing the startup error failed: _Exception',
      ]);
    });
  });

  group('runBounded', () {
    test('runs the step', () async {
      var ran = false;
      await runBounded(
        () async => ran = true,
        timeout: _short,
        label: 'x',
        log: (_) => fail('nothing to log'),
      );
      expect(ran, isTrue);
    });

    test('gives up after the timeout and never throws', () async {
      final logs = <String>[];
      await runBounded(
        () => Completer<void>().future,
        timeout: _short,
        label: 'removing the tray icon',
        log: logs.add,
      );
      await runBounded(
        () async => throw StateError('SECRET'),
        timeout: _short,
        label: 'releasing the lock',
        log: logs.add,
      );
      expect(logs, [
        'ShellX: removing the tray icon failed: TimeoutException',
        'ShellX: releasing the lock failed: StateError',
      ]);
    });
  });
}
