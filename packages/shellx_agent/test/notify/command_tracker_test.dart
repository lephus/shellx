import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final class _Clock {
  DateTime now = DateTime.utc(2026, 10, 5, 12);
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late _Clock clock;
  Duration? threshold;
  late CommandTracker tracker;

  setUp(() {
    clock = _Clock();
    threshold = const Duration(seconds: 30);
    tracker = CommandTracker(threshold: () => threshold, now: () => clock.now);
  });

  CompletedCommand? run(String? line, Duration took, int code) {
    if (line != null) expect(tracker.handle(CommandLineSeen(line)), isNull);
    expect(tracker.handle(const CommandStarted()), isNull);
    clock.advance(took);
    return tracker.handle(CommandFinished(code));
  }

  test('a command at or over the threshold is reported with line, code, '
      'duration', () {
    final done = run('npm test', const Duration(seconds: 30), 0)!;
    expect(done.commandLine, 'npm test');
    expect(done.exitCode, 0);
    expect(done.duration, const Duration(seconds: 30));
    expect(run('make', const Duration(minutes: 3), 2)!.exitCode, 2);
  });

  test('a shorter command is not reported', () {
    expect(run('ls', const Duration(seconds: 29), 0), isNull);
  });

  test('threshold null (off) reports nothing; zero reports everything', () {
    threshold = null;
    expect(run('sleep 100', const Duration(minutes: 5), 0), isNull);
    threshold = Duration.zero;
    expect(run('true', Duration.zero, 0), isNotNull);
  });

  test('the threshold is read when the command ends (a live change '
      'applies)', () {
    expect(tracker.handle(const CommandStarted()), isNull);
    clock.advance(const Duration(seconds: 15));
    threshold = const Duration(seconds: 10);
    expect(tracker.handle(const CommandFinished(0)), isNotNull);
  });

  test('D without a C before it is ignored, and so is a second D', () {
    threshold = Duration.zero;
    expect(tracker.handle(const CommandFinished(1)), isNull);
    expect(run('x', Duration.zero, 0), isNotNull);
    expect(tracker.handle(const CommandFinished(0)), isNull);
  });

  test('without an E the command line is null; an E is used once', () {
    threshold = Duration.zero;
    expect(run(null, Duration.zero, 0)!.commandLine, isNull);
    expect(run('first', Duration.zero, 0)!.commandLine, 'first');
    expect(run(null, Duration.zero, 0)!.commandLine, isNull);
    expect(run('   ', Duration.zero, 0)!.commandLine, isNull);
  });

  test('the last E before C wins; the unescaped line is kept as is', () {
    threshold = Duration.zero;
    tracker.handle(const CommandLineSeen('old'));
    expect(
      run('sleep 1; false', Duration.zero, 1)!.commandLine,
      'sleep 1; false',
    );
  });

  test('a throwing threshold getter reports nothing', () {
    tracker = CommandTracker(
      threshold: () => throw StateError('settings gone'),
      now: () => clock.now,
    );
    expect(run('x', const Duration(hours: 1), 0), isNull);
  });

  test('notifications do not disturb a running command', () {
    threshold = Duration.zero;
    tracker.handle(const CommandLineSeen('build'));
    tracker.handle(const CommandStarted());
    tracker.handle(const NotifyRequested(title: null, body: 'x'));
    expect(tracker.handle(const CommandFinished(0))!.commandLine, 'build');
  });
}
