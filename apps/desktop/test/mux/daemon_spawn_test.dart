import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/mux/daemon_spawn.dart';

void main() {
  test('macOS: the same binary with --daemon, detached from this process '
      '(the UI quitting must not end it)', () async {
    String? exe;
    List<String>? args;
    ProcessStartMode? mode;
    await spawnDaemon(
      windows: false,
      executable: '/Applications/ShellX.app/Contents/MacOS/ShellX',
      start: (e, a, m) async {
        exe = e;
        args = a;
        mode = m;
      },
    );
    expect(exe, '/Applications/ShellX.app/Contents/MacOS/ShellX');
    expect(args, ['--daemon']);
    expect(mode, ProcessStartMode.detached);
  });

  test('Windows: shellx-mux.exe from the runtime copy, detached', () async {
    String? exe;
    List<String>? args;
    ProcessStartMode? mode;
    String? copied;
    await spawnDaemon(
      windows: true,
      executable: r'C:\Program Files\ShellX\ShellX.exe',
      localAppData: r'C:\Users\u\AppData\Local',
      version: '1.6.0',
      prepareRuntime:
          ({
            required String installDir,
            required String localAppData,
            required String version,
          }) async {
            copied = '$installDir|$localAppData|$version';
            return r'C:\Users\u\AppData\Local\ShellX\mux\1.6.0\shellx-mux.exe';
          },
      start: (e, a, m) async {
        exe = e;
        args = a;
        mode = m;
      },
    );
    expect(copied, r'C:\Program Files\ShellX|C:\Users\u\AppData\Local|1.6.0');
    expect(exe, endsWith('shellx-mux.exe'));
    expect(args, ['--daemon']);
    expect(mode, ProcessStartMode.detached);
  });

  test(
    'a failed start is an error the launcher reports as StartFailed',
    () async {
      await expectLater(
        spawnDaemon(
          windows: false,
          executable: '/x',
          start: (_, _, _) async => throw const ProcessException('/x', []),
        ),
        throwsA(isA<ProcessException>()),
      );
    },
  );
}
