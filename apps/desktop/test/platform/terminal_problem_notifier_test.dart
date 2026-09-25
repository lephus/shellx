import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/terminal_problem_notifier.dart';

import '../support/fakes.dart';

const _window = Duration(milliseconds: 40);
const _afterWindow = Duration(milliseconds: 150);

void main() {
  late RecordingNotifier notifier;

  TerminalProblemNotifier problems({Locale locale = const Locale('en')}) =>
      TerminalProblemNotifier(
        notifier: notifier,
        l10n: lookupAppLocalizations(locale),
        window: _window,
      );

  setUp(() => notifier = RecordingNotifier());

  test('a burst of problems becomes one notification listing each pid '
      'once', () async {
    final reporter = problems();
    reporter.report(4321);
    reporter.report(4400);
    reporter.report(4321);
    expect(notifier.shown, isEmpty, reason: 'waits for the burst to end');

    await Future<void>.delayed(_afterWindow);

    expect(notifier.shown, hasLength(1));
    expect(
      notifier.shown.single.title,
      'Processes from a terminal session may still be running',
    );
    expect(notifier.shown.single.body, 'Shell process IDs: 4321, 4400');
  });

  test('a later problem gets its own notification', () async {
    final reporter = problems();
    reporter.report(1001);
    await Future<void>.delayed(_afterWindow);
    reporter.report(1002);
    await Future<void>.delayed(_afterWindow);

    expect(notifier.shown.map((n) => n.body), [
      'Shell process ID: 1001',
      'Shell process ID: 1002',
    ]);
  });

  test('Vietnamese', () async {
    problems(locale: const Locale('vi')).report(77);
    await Future<void>.delayed(_afterWindow);

    expect(
      notifier.shown.single.title,
      'Tiến trình của một phiên terminal có thể vẫn đang chạy',
    );
    expect(notifier.shown.single.body, 'Mã tiến trình shell: 77');
  });

  test('a failing notifier is not an unhandled error', () async {
    notifier.fail = true;
    final reporter = problems();
    reporter.report(5);
    await Future<void>.delayed(_afterWindow);
    notifier.fail = false;
    reporter.report(6);
    await Future<void>.delayed(_afterWindow);

    expect(notifier.shown.single.body, 'Shell process ID: 6');
  });
}
