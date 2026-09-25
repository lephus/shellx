import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/keep_awake.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';
import 'package:shellx_desktop/src/platform/wake_detector.dart';

final class _FakeProcess implements Process {
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 999;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

void main() {
  group('CaffeinateKeepAwake', () {
    test(
      'starts one caffeinate bound to the agent pid and kills it on disable',
      () async {
        final started = <List<String>>[];
        final processes = <_FakeProcess>[];
        final keepAwake = CaffeinateKeepAwake(
          agentPid: 4242,
          start: (exe, args) async {
            started.add([exe, ...args]);
            return processes.last;
          },
        );
        processes.add(_FakeProcess());
        await Future.wait([
          keepAwake.setEnabled(true),
          keepAwake.setEnabled(true),
        ]);
        expect(started, [
          ['/usr/bin/caffeinate', '-i', '-w', '4242'],
        ]);

        await keepAwake.setEnabled(false);
        expect(processes.single.killed, isTrue);

        processes.add(_FakeProcess());
        await keepAwake.setEnabled(true);
        expect(started, hasLength(2));
      },
    );

    test('recovers after a failed spawn', () async {
      final started = <List<String>>[];
      final processes = <_FakeProcess>[];
      var shouldThrow = true;
      final keepAwake = CaffeinateKeepAwake(
        agentPid: 4242,
        start: (exe, args) async {
          started.add([exe, ...args]);
          if (shouldThrow) {
            shouldThrow = false;
            throw const ProcessException('/usr/bin/caffeinate', [
              '-i',
              '-w',
              '4242',
            ], 'spawn failed');
          }
          return processes.last;
        },
      );

      await expectLater(
        keepAwake.setEnabled(true),
        throwsA(isA<ProcessException>()),
      );

      processes.add(_FakeProcess());
      await keepAwake.setEnabled(true);
      expect(started, hasLength(2));

      await keepAwake.setEnabled(false);
      expect(processes.single.killed, isTrue);
    });
  });

  test(
    'WindowsKeepAwake sets ES_CONTINUOUS|ES_SYSTEM_REQUIRED, then ES_CONTINUOUS',
    () async {
      final flags = <int>[];
      final keepAwake = WindowsKeepAwake(
        setState: (f) {
          flags.add(f);
          return 1;
        },
      );
      await keepAwake.setEnabled(true);
      await keepAwake.setEnabled(false);
      expect(flags, [0x80000001, 0x80000000]);
    },
  );

  test('WindowsKeepAwake throws when SetThreadExecutionState fails', () async {
    final keepAwake = WindowsKeepAwake(setState: (f) => 0);
    await expectLater(keepAwake.setEnabled(true), throwsA(isA<StateError>()));
  });

  test('SystemUrlOpener uses open on macOS and rundll32 on Windows', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> run(String exe, List<String> args) async {
      calls.add([exe, ...args]);
      return ProcessResult(0, 0, '', '');
    }

    await SystemUrlOpener(
      isWindows: false,
      run: run,
    ).open(SystemUrlOpener.fullDiskAccessPane);
    await SystemUrlOpener(
      isWindows: true,
      run: run,
    ).open(Uri.parse('https://download.shellx.pro/x.exe'));
    expect(calls, [
      [
        '/usr/bin/open',
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ],
      [
        'rundll32',
        'url.dll,FileProtocolHandler',
        'https://download.shellx.pro/x.exe',
      ],
    ]);
  });

  test(
    'WakeDetector fires only when the wall clock jumps past interval + tolerance',
    () {
      var now = DateTime(2026, 9, 25, 12);
      var wakes = 0;
      final detector = WakeDetector(onWake: () => wakes++, now: () => now);
      detector.start();
      now = now.add(const Duration(seconds: 5));
      detector.check();
      now = now.add(const Duration(seconds: 19));
      detector.check();
      expect(wakes, 0);
      now = now.add(const Duration(minutes: 42));
      detector.check();
      expect(wakes, 1);
      detector.stop();
    },
  );
}
