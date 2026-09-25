import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

ProcessRunner fakeRun(String stdout, {int exitCode = 0, List<String>? calls}) {
  return (executable, arguments) async {
    calls?.add('$executable ${arguments.join(' ')}');
    return ProcessResult(1, exitCode, stdout, '');
  };
}

Future<bool> fakeFileExists(String path) async => true;

void main() {
  group('buildSessionEnvironment', () {
    test('sets TERM, COLORTERM, SHELLX and keeps the base environment', () {
      final env = buildSessionEnvironment({
        'HOME': '/Users/me',
        'TERM': 'dumb',
      });
      expect(env['HOME'], '/Users/me');
      expect(env['TERM'], 'xterm-256color');
      expect(env['COLORTERM'], 'truecolor');
      expect(env['SHELLX'], '1');
    });

    test('defaults LANG only when unset or empty', () {
      expect(buildSessionEnvironment({})['LANG'], 'en_US.UTF-8');
      expect(buildSessionEnvironment({'LANG': ''})['LANG'], 'en_US.UTF-8');
      expect(
        buildSessionEnvironment({'LANG': 'vi_VN.UTF-8'})['LANG'],
        'vi_VN.UTF-8',
      );
    });

    test('does not modify the base map', () {
      final base = {'PATH': '/bin'};
      buildSessionEnvironment(base);
      expect(base, {'PATH': '/bin'});
    });
  });

  group('PlatformShellResolver on macOS', () {
    test('reads the login shell with dscl and runs it with -l', () async {
      final calls = <String>[];
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('UserShell: /opt/homebrew/bin/fish\n', calls: calls),
        fileExists: fakeFileExists,
      );
      final shell = await resolver.resolve();
      expect(calls, ['dscl . -read /Users/phu UserShell']);
      expect(
        shell,
        const ShellCommand(
          executable: '/opt/homebrew/bin/fish',
          arguments: ['-l'],
          name: 'fish',
        ),
      );
    });

    test('accepts the value on the line after the key', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('UserShell:\n /bin/bash\n'),
        fileExists: fakeFileExists,
      );
      expect((await resolver.resolve()).executable, '/bin/bash');
    });

    test('falls back to /bin/zsh -l when dscl fails', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('', exitCode: 56),
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });

    test('falls back when the output has no absolute path', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('No such key: UserShell\n'),
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });

    test('falls back when the runner throws or USER is missing', () async {
      final throwing = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: (_, _) async => throw const ProcessException('dscl', []),
      );
      expect(await throwing.resolve(), PlatformShellResolver.macFallback);
      final noUser = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {},
      );
      expect(await noUser.resolve(), PlatformShellResolver.macFallback);
    });

    test('uses LOGNAME when USER is absent', () async {
      final calls = <String>[];
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'LOGNAME': 'alice'},
        run: fakeRun('UserShell: /bin/bash\n', calls: calls),
        fileExists: fakeFileExists,
      );
      final shell = await resolver.resolve();
      expect(calls, ['dscl . -read /Users/alice UserShell']);
      expect(shell.executable, '/bin/bash');
    });

    test('uses id -un when USER and LOGNAME are absent', () async {
      final calls = <String>[];
      var callIndex = 0;
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {},
        run: (executable, arguments) async {
          calls.add('$executable ${arguments.join(' ')}');
          if (callIndex == 0) {
            // id -un call
            callIndex++;
            return ProcessResult(1, 0, 'bob\n', '');
          } else {
            // dscl call
            return ProcessResult(1, 0, 'UserShell: /bin/zsh\n', '');
          }
        },
        fileExists: fakeFileExists,
      );
      final shell = await resolver.resolve();
      expect(calls, ['id -un', 'dscl . -read /Users/bob UserShell']);
      expect(shell.executable, '/bin/zsh');
    });

    test('falls back when id -un returns empty', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {},
        run: fakeRun(''),
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });

    test(
      'accepts dscl output with leading whitespace before UserShell:',
      () async {
        final resolver = PlatformShellResolver(
          operatingSystem: 'macos',
          environment: {'USER': 'phu'},
          run: fakeRun('  UserShell: /bin/zsh\n'),
          fileExists: fakeFileExists,
        );
        expect((await resolver.resolve()).executable, '/bin/zsh');
      },
    );

    test('falls back when the UserShell path does not exist', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('UserShell: /nonexistent/shell\n'),
        fileExists: (path) async => false,
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });
  });

  group('PlatformShellResolver on Windows', () {
    test('prefers pwsh.exe when it is on PATH', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'windows',
        environment: {},
        isOnPath: (exe) async => exe == 'pwsh.exe',
      );
      expect(
        await resolver.resolve(),
        const ShellCommand(executable: 'pwsh.exe', arguments: [], name: 'pwsh'),
      );
    });

    test('uses powershell.exe otherwise', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'windows',
        environment: {},
        isOnPath: (_) async => false,
      );
      expect(
        await resolver.resolve(),
        const ShellCommand(
          executable: 'powershell.exe',
          arguments: [],
          name: 'powershell',
        ),
      );
    });
  });

  test('other operating systems use /bin/sh', () async {
    final resolver = PlatformShellResolver(
      operatingSystem: 'linux',
      environment: {},
    );
    expect(
      await resolver.resolve(),
      const ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh'),
    );
  });
}
