@TestOn('mac-os || linux')
library;

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  test('output, exit code, missing executable, timeout', () async {
    final ok = await runCommand('/bin/sh', [
      '-c',
      'printf out; printf err >&2; exit 3',
    ]);
    expect(
      (ok.exitCode, ok.stdout, ok.stderr, ok.timedOut),
      (3, 'out', 'err', false),
    );
    final missing = await runCommand('/nonexistent/tool', const []);
    expect(missing.exitCode, 127);
    final slow = await runCommand('/bin/sh', [
      '-c',
      'sleep 5',
    ], timeout: const Duration(milliseconds: 200));
    expect(slow.timedOut, isTrue);
    expect(slow.exitCode, -1);
  });

  test('the ShellX socket credentials never reach a helper', () async {
    final r = await runCommand(
      '/bin/sh',
      ['-c', r'printf "%s|%s|%s" "$SHELLX_CLI_TOKEN" "$SHELLX_SOCKET" "$KEEP"'],
      parentEnvironment: {
        'SHELLX_CLI_TOKEN': 'secret',
        'SHELLX_SOCKET': '/tmp/s',
        'KEEP': 'yes',
      },
    );
    expect(r.stdout, '||yes');
  });

  test(
    'a child that ignores SIGTERM is still gone at the timeout (M3)',
    () async {
      final watch = Stopwatch()..start();
      final r = await runCommand('/bin/sh', [
        '-c',
        'trap "" TERM; sleep 30',
      ], timeout: const Duration(milliseconds: 200));
      expect(r.timedOut, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test('partial output survives a timeout (L7)', () async {
    final r = await runCommand('/bin/sh', [
      '-c',
      'printf partial; sleep 30',
    ], timeout: const Duration(milliseconds: 500));
    expect(r.timedOut, isTrue);
    expect(r.stdout, 'partial');
  });

  test('an empty executable is exit 127 (L7)', () async {
    final r = await runCommand('', const []);
    expect(r.exitCode, 127);
  });
}
