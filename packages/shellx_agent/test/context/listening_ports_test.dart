import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

const _lsof = '''
p612
f12
n*:5173
f13
n[::1]:5173
p701
f4
n127.0.0.1:8080
f5
n127.0.0.1:8080->127.0.0.1:50000
''';

const _netstat = '''

Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1012
  TCP    127.0.0.1:5173         0.0.0.0:0              ABHÖREN         4321
  TCP    127.0.0.1:5173         127.0.0.1:50000        ESTABLISHED     4321
  TCP    [::]:3000              [::]:0                 LISTENING       4400
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING       0
  UDP    0.0.0.0:5353           *:*                                    2000
''';

void main() {
  test('lsof -Fpn: ports per pid, IPv4/IPv6 merged, peers ignored', () {
    expect(parseLsofListen(_lsof), {
      612: {5173},
      701: {8080},
    });
  });

  test('netstat -ano: listening = foreign port 0, whatever the state word '
      '(translated on some Windows languages, D7)', () {
    expect(parseNetstatListen(_netstat), {
      1012: {135},
      4321: {5173},
      4400: {3000},
    });
  });

  test('ps / CIM "pid ppid" lines', () {
    expect(parseParentTable('  1     0\n 100     1\n 200   100\nbad line\n'), {
      1: 0,
      100: 1,
      200: 100,
    });
  });

  test('ownerOf: nearest shell ancestor; cycles and dead parents end', () {
    final parents = {300: 200, 200: 100, 100: 1, 7: 8, 8: 7};
    expect(ownerOf(300, parents, {100: 1}), 1);
    expect(ownerOf(300, parents, {100: 1, 200: 2}), 2); // nested shell
    expect(ownerOf(100, parents, {100: 1}), 1); // the shell itself
    expect(ownerOf(7, parents, {100: 1}), isNull); // cycle
    expect(ownerOf(999, parents, {100: 1}), isNull); // unknown
  });

  group('MacPortProbe', () {
    test(
      'runs lsof and ps with the exact arguments and a 2 s timeout',
      () async {
        final calls = <String>[];
        final probe = MacPortProbe(
          run: (exe, args, {required timeout}) async {
            calls.add('$exe ${args.join(' ')} ${timeout.inSeconds}');
            return ProbeOutput(0, exe.endsWith('lsof') ? _lsof : '100 1\n');
          },
        );
        expect(await probe.listening(), hasLength(2));
        expect(await probe.parents(), {100: 1});
        expect(calls, [
          '/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpn 2',
          '/bin/ps -axo pid=,ppid= 2',
        ]);
      },
    );

    test('lsof exit 1 with no output means no ports (D6)', () async {
      final probe = MacPortProbe(
        run: (exe, args, {required timeout}) async => const ProbeOutput(1, ''),
      );
      expect(await probe.listening(), isEmpty);
    });

    test('another exit code is a PortProbeException', () async {
      final probe = MacPortProbe(
        run: (exe, args, {required timeout}) async => const ProbeOutput(2, ''),
      );
      expect(probe.listening(), throwsA(isA<PortProbeException>()));
      expect(probe.parents(), throwsA(isA<PortProbeException>()));
    });
  });

  test('WindowsPortProbe runs %SystemRoot%\\System32 netstat -ano and CIM '
      'through Windows PowerShell by absolute path (5 s), never wmic', () async {
    final calls = <List<Object>>[];
    final probe = WindowsPortProbe(
      environment: const {'SystemRoot': r'D:\Win'},
      run: (exe, args, {required timeout}) async {
        calls.add([exe, args, timeout.inSeconds]);
        return ProbeOutput(
          0,
          exe.endsWith('netstat.exe') ? _netstat : '4321 100\n',
        );
      },
    );
    expect(await probe.listening(), hasLength(3));
    expect(await probe.parents(), {4321: 100});
    expect(calls, [
      [
        r'D:\Win\System32\netstat.exe',
        ['-ano'],
        2,
      ],
      [
        r'D:\Win\System32\WindowsPowerShell\v1.0\powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId | "
              r"ForEach-Object { '{0} {1}' -f $_.ProcessId, $_.ParentProcessId }",
        ],
        5,
      ],
    ]);
  });

  test(
    r'WindowsPortProbe falls back to C:\Windows without SystemRoot',
    () async {
      final exes = <String>[];
      final probe = WindowsPortProbe(
        environment: const {},
        run: (exe, args, {required timeout}) async {
          exes.add(exe);
          return const ProbeOutput(0, '');
        },
      );
      await probe.listening();
      await probe.parents();
      expect(exes, [
        r'C:\Windows\System32\netstat.exe',
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      ]);
    },
  );

  test(
    'runWithTimeout returns the output, and kills a command that is too slow',
    () async {
      final echo = await runWithTimeout('/bin/echo', [
        'hi',
      ], timeout: const Duration(seconds: 2));
      expect((echo.exitCode, echo.stdout), (0, 'hi\n'));
      final started = DateTime.now();
      await expectLater(
        runWithTimeout('/bin/sleep', [
          '5',
        ], timeout: const Duration(milliseconds: 200)),
        throwsA(isA<PortProbeException>()),
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(2));
      await expectLater(
        runWithTimeout(
          '/no/such/tool',
          [],
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<PortProbeException>()),
      );
    },
    testOn: 'mac-os || linux',
  );
}
