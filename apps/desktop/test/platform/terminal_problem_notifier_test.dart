import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/terminal_problem_notifier.dart';

import '../support/fakes.dart';

/// The production window (the default).
const _window = Duration(seconds: 3);
const _tick = Duration(milliseconds: 1);

void main() {
  late RecordingNotifier notifier;

  TerminalProblemNotifier problems({Locale locale = const Locale('en')}) =>
      TerminalProblemNotifier(
        notifier: notifier,
        l10n: lookupAppLocalizations(locale),
      );

  setUp(() => notifier = RecordingNotifier());

  test('a burst of problems becomes one notification listing each pid '
      'once', () {
    fakeAsync((async) {
      final reporter = problems();
      reporter.report(4321);
      async.elapse(const Duration(seconds: 1));
      reporter.report(4400);
      reporter.report(4321);
      async.elapse(_window - const Duration(seconds: 1) - _tick);
      expect(notifier.shown, isEmpty, reason: 'waits for the burst to end');

      async.elapse(_tick);

      expect(notifier.shown, hasLength(1));
      expect(
        notifier.shown.single.title,
        'Processes from a terminal session may still be running',
      );
      expect(notifier.shown.single.body, 'Shell process IDs: 4321, 4400');
    });
  });

  test('a later problem gets its own notification', () {
    fakeAsync((async) {
      final reporter = problems();
      reporter.report(1001);
      async.elapse(_window);
      reporter.report(1002);
      async.elapse(_window);

      expect(notifier.shown.map((n) => n.body), [
        'Shell process ID: 1001',
        'Shell process ID: 1002',
      ]);
    });
  });

  test('Vietnamese', () {
    fakeAsync((async) {
      problems(locale: const Locale('vi')).report(77);
      async.elapse(_window);

      expect(
        notifier.shown.single.title,
        'Tiến trình của một phiên terminal có thể vẫn đang chạy',
      );
      expect(notifier.shown.single.body, 'Mã tiến trình shell: 77');
    });
  });

  test('a failing notifier is not an unhandled error', () {
    fakeAsync((async) {
      notifier.fail = true;
      final reporter = problems();
      reporter.report(5);
      async.elapse(_window);
      notifier.fail = false;
      reporter.report(6);
      async.elapse(_window);

      expect(notifier.shown.single.body, 'Shell process ID: 6');
    });
  });
}
