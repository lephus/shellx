import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

List<int> marked(
  Map<String, String> vars, {
  String before = '',
  String after = '',
}) => utf8.encode(
  '$before\x1e${vars.entries.map((e) => '${e.key}=${e.value}').join('\x00')}\x00\x1e$after',
);

void main() {
  group('parseMarkedEnv', () {
    test(
      'only what is between the markers; values may hold = and newlines',
      () {
        final env = parseMarkedEnv(
          marked(
            {'PATH': '/usr/bin:/bin', 'MULTI': 'a\nb=c', 'EMPTY': ''},
            before: 'Welcome back!\nLast login: today\n',
            after: '\nbye',
          ),
        );
        expect(env, {'PATH': '/usr/bin:/bin', 'MULTI': 'a\nb=c', 'EMPTY': ''});
      },
    );

    test('no markers: null', () {
      expect(parseMarkedEnv(utf8.encode('PATH=/bin\x00')), isNull);
      expect(parseMarkedEnv(utf8.encode('one \x1e only')), isNull);
    });
  });

  test('cleanAgentEnv drops every SHELLX_* and per-shell noise (spec D6)', () {
    expect(
      cleanAgentEnv({
        'PATH': '/bin',
        'SHELLX_CLI_TOKEN': 't',
        'SHELLX_SOCKET': 's',
        'shellx_other': 'x',
        'PWD': '/x',
        'OLDPWD': '/y',
        'SHLVL': '2',
        '_': '/usr/bin/env',
        'HOME': '/Users/a',
      }),
      {'PATH': '/bin', 'HOME': '/Users/a'},
    );
  });

  group('resolve', () {
    final process = {
      'PATH': '/usr/bin',
      'SHELL': '/bin/zsh',
      'SHELLX_CLI_TOKEN': 'secret',
    };

    test(
      'interactive login first; markers make profile noise harmless',
      () async {
        final calls = <List<String>>[];
        final env = LoginShellEnv(
          processEnv: process,
          isWindows: false,
          isMacOS: true,
          run: (shell, args, environment, timeout) async {
            calls.add([shell, ...args]);
            expect(environment['SHELLX_RESOLVING_ENVIRONMENT'], '1');
            return (
              0,
              marked({
                'PATH': '/opt/homebrew/bin:/usr/bin',
                'SHELLX_CLI_TOKEN': 'x',
              }, before: 'banner'),
            );
          },
        );
        final r = await env.resolve();
        expect(r.source, LoginEnvSource.interactiveLogin);
        expect(r.vars, {'PATH': '/opt/homebrew/bin:/usr/bin'});
        expect(calls.single.take(4), ['/bin/zsh', '-i', '-l', '-c']);
      },
    );

    test('then -l -c, then the app environment', () async {
      var n = 0;
      final viaLogin = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async => n++ == 0
            ? (1, utf8.encode('no markers here'))
            : (0, marked({'PATH': '/login/bin'})),
      ).resolve();
      expect(viaLogin.source, LoginEnvSource.login);
      expect(viaLogin.vars['PATH'], '/login/bin');

      final fallback = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async =>
            throw TimeoutException('slow'),
      ).resolve();
      expect(fallback.source, LoginEnvSource.process);
      expect(fallback.vars, {'PATH': '/usr/bin', 'SHELL': '/bin/zsh'});
    });

    test('a non-zero exit with markers still counts', () async {
      final r = await LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async =>
            (3, marked({'PATH': '/x'})),
      ).resolve();
      expect(r.vars['PATH'], '/x');
    });

    test('cached until invalidate', () async {
      var n = 0;
      final env = LoginShellEnv(
        processEnv: process,
        isWindows: false,
        run: (shell, args, environment, timeout) async {
          n++;
          return (0, marked({'PATH': '/p$n'}));
        },
      );
      expect((await env.resolve()).vars['PATH'], '/p1');
      expect((await env.resolve()).vars['PATH'], '/p1');
      env.invalidate();
      expect((await env.resolve()).vars['PATH'], '/p2');
    });

    test(
      'an unknown or relative SHELL falls back to /bin/zsh on macOS',
      () async {
        final shells = <String>[];
        await LoginShellEnv(
          processEnv: {'SHELL': 'nu'},
          isWindows: false,
          isMacOS: true,
          run: (shell, args, environment, timeout) async {
            shells.add(shell);
            return (0, marked({'PATH': '/x'}));
          },
        ).resolve();
        expect(shells, ['/bin/zsh']);
      },
    );

    test('Windows: the app environment, no shell', () async {
      final r = await LoginShellEnv(
        processEnv: {'Path': r'C:\Windows', 'SHELLX_CLI_TOKEN': 't'},
        isWindows: true,
        run: (shell, args, environment, timeout) async =>
            fail('no shell on Windows'),
      ).resolve();
      expect(r.source, LoginEnvSource.process);
      expect(r.vars, {'Path': r'C:\Windows'});
    });
  });

  group('Windows: PATH from the registry (final review I-4)', () {
    /// `reg query <key> /v Path` as Windows prints it: a blank line, the key,
    /// the value as name, type and data between four spaces, a blank line.
    String reg(
      String type,
      String data, {
      String key = r'HKEY_CURRENT_USER\Environment',
    }) => '\r\n$key\r\n    Path    $type    $data\r\n\r\n';

    final machine = reg(
      'REG_EXPAND_SZ',
      r'%SystemRoot%\system32;%SystemRoot%;C:\Program Files\nodejs\;C:\Program Files\Git\cmd',
      key:
          r'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    );
    final user = reg(
      'REG_EXPAND_SZ',
      r'%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;C:\Users\Ann\AppData\Roaming\npm',
    );
    const missing =
        'ERROR: The system was unable to find the specified registry key or value.\r\n';

    // The environment of an app that started before Node was installed.
    const before = {
      'Path': r'C:\Windows\system32;C:\Windows;C:\Tools',
      'SystemRoot': r'C:\Windows',
      'USERPROFILE': r'C:\Users\Ann',
      'SHELLX_CLI_TOKEN': 'secret',
    };

    group('parseRegQueryPath', () {
      test('REG_EXPAND_SZ: the data, to be expanded', () {
        expect(parseRegQueryPath(user), (
          data:
              r'%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;C:\Users\Ann\AppData\Roaming\npm',
          expands: true,
        ));
        expect(
          parseRegQueryPath(machine)!.data,
          startsWith(r'%SystemRoot%\system32;%SystemRoot%;'),
        );
      });

      test('REG_SZ: the data as it is', () {
        expect(parseRegQueryPath(reg('REG_SZ', r'C:\a;C:\Program Files\b')), (
          data: r'C:\a;C:\Program Files\b',
          expands: false,
        ));
      });

      test('the name in any case, any line ending, spaces kept inside', () {
        expect(
          parseRegQueryPath(
            'HKEY_CURRENT_USER\\Environment\n'
            '    PATH    REG_SZ    C:\\My Tools;D:\\x\n',
          ),
          (data: r'C:\My Tools;D:\x', expands: false),
        );
      });

      test('a Path that is empty is an empty value', () {
        expect(parseRegQueryPath(reg('REG_SZ', '')), (
          data: '',
          expands: false,
        ));
      });

      test('no value, an error, another value, another type, garbage: null', () {
        for (final text in [
          '',
          '   \r\n',
          missing,
          '\r\nHKEY_CURRENT_USER\\Environment\r\n    TEMP    REG_EXPAND_SZ    C:\\tmp\r\n',
          reg('REG_DWORD', '0x1'),
          reg('REG_MULTI_SZ', r'a\0b'),
          'Path REG_SZ',
          r'PATH=C:\x',
          '\x00\x01\x02 garbage \ufffd\ufffd',
        ]) {
          expect(parseRegQueryPath(text), isNull, reason: text);
        }
      });
    });

    group('expandWindowsVars', () {
      test('%NAME% from the variables, without case; unknown names stay', () {
        const vars = {
          'SystemRoot': r'C:\Windows',
          'USERPROFILE': r'C:\Users\A',
        };
        expect(
          expandWindowsVars(r'%SYSTEMROOT%\system32;%userprofile%\bin', vars),
          r'C:\Windows\system32;C:\Users\A\bin',
        );
        expect(
          expandWindowsVars(r'%NVM_HOME%;%SystemRoot%', vars),
          r'%NVM_HOME%;C:\Windows',
        );
      });

      test('a lone percent sign, an empty pair and adjacent names', () {
        const vars = {'A': 'a', 'B': 'b'};
        expect(expandWindowsVars('100%;x', vars), '100%;x');
        expect(expandWindowsVars('%%;x', vars), '%%;x');
        expect(expandWindowsVars('%A%%B%', vars), 'ab');
      });

      test('what a value expands to is not expanded again', () {
        expect(expandWindowsVars('%A%', {'A': '%B%', 'B': 'b'}), '%B%');
      });
    });

    group('mergeRegistryPath', () {
      test('machine first, then the user, each expanded from the environment', () {
        expect(
          mergeRegistryPath(machine: machine, user: user, vars: before),
          r'C:\Windows\system32;C:\Windows;C:\Program Files\nodejs\;C:\Program Files\Git\cmd;'
          r'C:\Users\Ann\AppData\Local\Microsoft\WindowsApps;C:\Users\Ann\AppData\Roaming\npm;'
          r'C:\Tools',
        );
      });

      test('REG_SZ is not expanded', () {
        expect(
          mergeRegistryPath(
            machine: reg('REG_SZ', r'%SystemRoot%\x;C:\y'),
            vars: before,
          ),
          r'%SystemRoot%\x;C:\y;C:\Windows\system32;C:\Windows;C:\Tools',
        );
      });

      test('no user Path: the machine one alone', () {
        expect(
          mergeRegistryPath(machine: machine, user: missing, vars: const {}),
          r'%SystemRoot%\system32;%SystemRoot%;C:\Program Files\nodejs\;C:\Program Files\Git\cmd',
          reason: 'SystemRoot unknown here: the registry value stays literal',
        );
        expect(
          mergeRegistryPath(machine: machine, user: null, vars: before),
          startsWith(r'C:\Windows\system32;C:\Windows;C:\Program Files\nodejs'),
        );
      });

      test('no machine Path: the user one, then what the app had', () {
        expect(
          mergeRegistryPath(machine: null, user: user, vars: before),
          r'C:\Users\Ann\AppData\Local\Microsoft\WindowsApps;C:\Users\Ann\AppData\Roaming\npm;'
          r'C:\Windows\system32;C:\Windows;C:\Tools',
        );
      });

      test('neither: null, so the caller keeps the environment it has', () {
        expect(mergeRegistryPath(vars: before), isNull);
        expect(
          mergeRegistryPath(machine: missing, user: missing, vars: before),
          isNull,
        );
        expect(
          mergeRegistryPath(machine: 'garbage', user: '\x00', vars: before),
          isNull,
        );
      });

      test(
        'an entry is listed once: without case, with or without a final \\',
        () {
          expect(
            mergeRegistryPath(
              machine: reg('REG_SZ', r'C:\A\;c:\b;;  ;C:\C '),
              user: reg('REG_SZ', r'C:\a;C:\B\;D:\d'),
              vars: {'PATH': r'c:\C;D:\D\;E:\e'},
            ),
            r'C:\A\;c:\b;C:\C;D:\d;E:\e',
          );
        },
      );

      test('what the app had and the registry lacks is kept (the app was '
          'started from a shell)', () {
        expect(
          mergeRegistryPath(
            machine: reg('REG_SZ', r'C:\m'),
            vars: {'Path': r'C:\dev-shell\bin;C:\m'},
          ),
          r'C:\m;C:\dev-shell\bin',
        );
      });

      test('%PATH% inside a value expands to the app PATH, listed once', () {
        expect(
          mergeRegistryPath(
            machine: reg('REG_EXPAND_SZ', r'C:\m;%PATH%'),
            vars: {'Path': r'C:\old;C:\m'},
          ),
          r'C:\m;C:\old',
        );
      });
    });

    group('LoginShellEnv on Windows', () {
      LoginShellEnv windows(
        List<String> asked, {
        Future<String?> Function(String key)? answer,
        Map<String, String> env = before,
      }) => LoginShellEnv(
        processEnv: env,
        isWindows: true,
        run: (shell, args, environment, timeout) async =>
            fail('no shell on Windows'),
        registry: (key) async {
          asked.add(key);
          if (answer != null) return answer(key);
          return key.startsWith('HKCU') ? user : machine;
        },
      );

      test(
        'the first resolve is the app environment: no registry query',
        () async {
          final asked = <String>[];
          final r = await windows(asked).resolve();
          expect(asked, isEmpty);
          expect(r.source, LoginEnvSource.process);
          expect(r.vars['Path'], r'C:\Windows\system32;C:\Windows;C:\Tools');
          expect(r.vars.containsKey('SHELLX_CLI_TOKEN'), isFalse);
        },
      );

      test(
        'invalidate: the next resolve reads both keys and rebuilds PATH',
        () async {
          final asked = <String>[];
          final env = windows(asked);
          await env.resolve();
          env.invalidate();
          final r = await env.resolve();
          expect(
            asked,
            unorderedEquals([
              r'HKCU\Environment',
              r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
            ]),
          );
          expect(
            r.vars['Path'],
            contains(r'C:\Program Files\nodejs'),
            reason: 'the Node that was installed since the app started',
          );
          expect(r.vars.keys.where((k) => k.toUpperCase() == 'PATH'), ['Path']);
          expect(
            r.vars['SystemRoot'],
            r'C:\Windows',
            reason: 'the rest is kept',
          );
          expect(r.vars.containsKey('SHELLX_CLI_TOKEN'), isFalse);
          expect(r.source, LoginEnvSource.process);
        },
      );

      test('kept until the next invalidate', () async {
        final asked = <String>[];
        final env = windows(asked);
        env.invalidate();
        await env.resolve();
        await env.resolve();
        expect(asked, hasLength(2), reason: 'two keys, once');
        env.invalidate();
        await env.resolve();
        expect(asked, hasLength(4));
      });

      test('an app environment with no Path gets one', () async {
        final env = windows([], env: {'SystemRoot': r'C:\Windows'});
        env.invalidate();
        final r = await env.resolve();
        expect(r.vars['Path'], contains(r'C:\Program Files\nodejs'));
      });

      test('any failure falls back to the environment the app has', () async {
        for (final answer in <Future<String?> Function(String)>[
          (key) async => throw StateError('reg.exe broke'),
          (key) async => null,
          (key) async => 'garbage',
          (key) async => missing,
        ]) {
          final env = windows([], answer: answer);
          env.invalidate();
          final r = await env.resolve();
          expect(r.source, LoginEnvSource.process);
          expect(r.vars['Path'], r'C:\Windows\system32;C:\Windows;C:\Tools');
        }
      });

      test('one key that fails still gives the other', () async {
        final env = windows(
          [],
          answer: (key) async =>
              key.startsWith('HKCU') ? throw StateError('x') : machine,
        );
        env.invalidate();
        final r = await env.resolve();
        expect(
          r.vars['Path'],
          startsWith(r'C:\Windows\system32;C:\Windows;C:\Program Files\nodejs'),
        );
      });

      test('elsewhere invalidate asks no registry', () async {
        final env = LoginShellEnv(
          processEnv: const {'PATH': '/usr/bin'},
          isWindows: false,
          run: (shell, args, environment, timeout) async =>
              (0, marked({'PATH': '/opt/bin'})),
          registry: (key) async => fail('no registry off Windows'),
        );
        await env.resolve();
        env.invalidate();
        expect((await env.resolve()).vars['PATH'], '/opt/bin');
      });
    });
  });

  group('real shells', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('login_env'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String script(String name, String body) {
      final f = File('${tmp.path}/$name')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    test('a noisy profile that exits non-zero', () async {
      final shell = script('noisy', r'''
echo "Welcome to the noisy profile"
for last; do :; done
/bin/sh -c "$last"
echo "bye"
exit 3''');
      final r = await LoginShellEnv(
        shell: shell,
        processEnv: {'PATH': '/usr/bin:/bin', 'SHELL': shell},
        isWindows: false,
      ).resolve();
      expect(r.source, LoginEnvSource.interactiveLogin);
      expect(r.vars['PATH'], '/usr/bin:/bin');
    });

    test('a hanging shell gives up within the timeout', () async {
      final shell = script('hang', 'sleep 30');
      final sw = Stopwatch()..start();
      final r = await LoginShellEnv(
        shell: shell,
        processEnv: {'PATH': '/usr/bin:/bin'},
        isWindows: false,
        timeout: const Duration(milliseconds: 300),
      ).resolve();
      expect(r.source, LoginEnvSource.process);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('the user shell of this machine resolves a PATH', () async {
      final r = await LoginShellEnv().resolve();
      expect(envValue(r.vars, 'PATH'), isNotEmpty);
    });
  }, testOn: '!windows');
}
