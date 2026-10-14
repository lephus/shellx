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
