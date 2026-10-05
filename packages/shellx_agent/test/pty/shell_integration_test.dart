import 'dart:convert';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_agent/src/pty/shell_hook_scripts.dart';
import 'package:test/test.dart';

const esc = '\x1b';
const bel = '\x07';

void main() {
  late Directory temp;
  late ShellIntegration integration;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('shellx-hooks-test-');
    integration = ShellIntegration(directory: '${temp.path}/hooks');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('apply', () {
    test('zsh: ZDOTDIR points at the hook dir, the user value is kept in '
        'SHELLX_USER_ZDOTDIR, the command is unchanged', () {
      const zsh = ShellCommand(
        executable: '/bin/zsh',
        arguments: ['-l'],
        name: 'zsh',
      );
      final launch = integration.apply(zsh, {
        'HOME': '/Users/u',
        'ZDOTDIR': '/Users/u/.config/zsh',
      });
      expect(launch.command, zsh);
      expect(launch.environment['ZDOTDIR'], '${temp.path}/hooks/zsh');
      expect(launch.environment['SHELLX_USER_ZDOTDIR'], '/Users/u/.config/zsh');
      expect(launch.environment['HOME'], '/Users/u');
      expect(
        File('${temp.path}/hooks/zsh/.zshenv').readAsStringSync(),
        contains('ShellX session hook'),
      );
      final noUserDir = integration.apply(zsh, {'HOME': '/Users/u'});
      expect(noUserDir.environment.containsKey('SHELLX_USER_ZDOTDIR'), isFalse);
    });

    test('bash: --rcfile <hook> -i; a login shell is marked for the rc', () {
      final login = integration.apply(
        const ShellCommand(
          executable: '/bin/bash',
          arguments: ['-l'],
          name: 'bash',
        ),
        {'HOME': '/h'},
      );
      expect(login.command.executable, '/bin/bash');
      expect(login.command.name, 'bash');
      expect(login.command.arguments, [
        '--rcfile',
        '${temp.path}/hooks/bash/rc.bash',
        '-i',
      ]);
      expect(login.environment['SHELLX_BASH_LOGIN'], '1');
      final plain = integration.apply(
        const ShellCommand(executable: 'bash', arguments: [], name: 'bash'),
        {'SHELLX_BASH_LOGIN': 'stale'},
      );
      expect(plain.environment.containsKey('SHELLX_BASH_LOGIN'), isFalse);
      expect(File('${temp.path}/hooks/bash/rc.bash').existsSync(), isTrue);
    });

    test('PowerShell: -NoExit -Command dot-sources the hook (quotes '
        'doubled)', () {
      final quoted = ShellIntegration(directory: "${temp.path}/it's");
      for (final exe in ['pwsh.exe', 'powershell.exe', '/usr/local/bin/pwsh']) {
        final launch = quoted.apply(
          ShellCommand(
            executable: exe,
            arguments: const ['-NoLogo'],
            name: 'p',
          ),
          const {},
        );
        expect(launch.command.arguments, [
          '-NoLogo',
          '-NoExit',
          '-Command',
          "try { . '${temp.path}/it''s/pwsh/hook.ps1' } catch { }",
        ]);
      }
      expect(File("${temp.path}/it's/pwsh/hook.ps1").existsSync(), isTrue);
    });

    test('other shells and non-interactive commands are left alone', () {
      for (final command in const [
        ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh'),
        ShellCommand(executable: '/opt/fish', arguments: ['-l'], name: 'fish'),
        ShellCommand(executable: '/bin/zsh', arguments: ['-c', 'x'], name: 'z'),
        ShellCommand(executable: '/bin/bash', arguments: ['s.sh'], name: 'b'),
        ShellCommand(
          executable: 'pwsh.exe',
          arguments: ['-NoProfile'],
          name: 'pwsh',
        ),
      ]) {
        final env = {'A': '1'};
        final launch = integration.apply(command, env);
        expect(launch.command, command);
        expect(launch.environment, env);
      }
    });

    test('a deleted or edited hook file is written again before the next '
        'start', () {
      const zsh = ShellCommand(executable: 'zsh', arguments: [], name: 'zsh');
      integration.apply(zsh, const {});
      final file = File('${temp.path}/hooks/zsh/.zshenv');
      final original = file.readAsStringSync();
      file.deleteSync();
      integration.apply(zsh, const {});
      expect(file.readAsStringSync(), original);
      file.writeAsStringSync('broken');
      integration.apply(zsh, const {});
      expect(file.readAsStringSync(), original);
    });

    test('an unwritable directory starts the shell unchanged', () {
      File('${temp.path}/file').writeAsStringSync('not a directory');
      final broken = ShellIntegration(directory: '${temp.path}/file');
      const zsh = ShellCommand(executable: 'zsh', arguments: [], name: 'zsh');
      final launch = broken.apply(zsh, const {'HOME': '/h'});
      expect(launch.command, zsh);
      expect(launch.environment, const {'HOME': '/h'});
    });

    test('the hook files are ASCII', () {
      for (final script in [zshHookEnv, bashHookRc, powerShellHook]) {
        expect(script.codeUnits.every((c) => c < 0x80), isTrue);
      }
    });
  });

  group('real shells (interactive, no tty)', () {
    late Directory home;

    setUp(() {
      home = Directory('${temp.path}/home')..createSync();
    });

    /// Runs [shell] with the hook, typing [lines]; returns all output.
    Future<String> run(
      ShellCommand shell,
      List<String> lines, {
      Map<String, String> extraEnv = const {},
      bool pty = false,
    }) async {
      final launch = integration.apply(shell, {
        'HOME': home.path,
        'PATH': '/usr/bin:/bin',
        'TERM': 'dumb',
        'BASH_SILENCE_DEPRECATION_WARNING': '1',
        ...extraEnv,
      });
      // With [pty], macOS `script` gives the shell a real terminal (bash-preexec
      // needs one); lines are then typed one by one.
      final process = await Process.start(
        pty ? '/usr/bin/script' : launch.command.executable,
        [
          if (pty) ...['-q', '/dev/null', launch.command.executable],
          ...launch.command.arguments,
        ],
        environment: launch.environment,
        includeParentEnvironment: false,
        workingDirectory: home.path,
      );
      final out = StringBuffer();
      final done = Future.wait([
        process.stdout.transform(utf8.decoder).forEach(out.write),
        process.stderr.transform(utf8.decoder).forEach(out.write),
      ]);
      if (pty) {
        await Future<void>.delayed(const Duration(seconds: 1));
        for (final line in [...lines, 'exit']) {
          process.stdin.write('$line\r');
          await process.stdin.flush();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } else {
        process.stdin.write('${lines.join('\n')}\nexit\n');
        await process.stdin.close();
      }
      await process.exitCode.timeout(const Duration(seconds: 20));
      await done;
      return out.toString();
    }

    final hasZsh = File('/bin/zsh').existsSync();
    final hasBash = File('/bin/bash').existsSync();

    test(
      'zsh: E, C and D;1 for `sleep 1; false`, the user files still load, '
      'ZDOTDIR and HISTFILE are the user\'s again, shellx notify works',
      () async {
        File('${home.path}/.zshenv').writeAsStringSync('USER_ZSHENV=1\n');
        File('${home.path}/.zshrc').writeAsStringSync(
          'alias hi="echo ALIAS'
          '-OK"\n'
          'export PATH="/opt/userbin:\$PATH"\n'
          'HISTFILE=\${ZDOTDIR:-\$HOME}/.zsh_history\n',
        );
        final out = await run(
          const ShellCommand(
            executable: '/bin/zsh',
            arguments: ['-i'],
            name: 'zsh',
          ),
          [
            'hi',
            'echo "P=[\$PATH] E=[\$USER_ZSHENV] Z=[\${ZDOTDIR-unset}]"',
            'echo "H=[\$HISTFILE]"',
            'sleep 1; false',
            'shellx notify x',
          ],
        );
        expect(out, contains('ALIAS-OK'));
        expect(out, contains('P=[/opt/userbin:/usr/bin:/bin] E=[1] Z=[unset]'));
        expect(out, contains('H=[${home.path}/.zsh_history]'));
        expect(
          out,
          contains('$esc]633;E;sleep 1\\x3b false$bel$esc]133;C$bel'),
        );
        expect(out, contains('$esc]133;D;1$bel'));
        expect(out, contains('$esc]777;notify;;x$bel'));
      },
      skip: hasZsh ? null : 'no /bin/zsh',
    );

    test(
      "zsh: a user ZDOTDIR is honoured and restored",
      () async {
        final zdot = Directory('${home.path}/.config/zsh')
          ..createSync(recursive: true);
        File('${zdot.path}/.zshrc').writeAsStringSync('FROM_ZDOTDIR=yes\n');
        final out = await run(
          const ShellCommand(
            executable: '/bin/zsh',
            arguments: ['-i', '-l'],
            name: 'zsh',
          ),
          ['echo "F=[\$FROM_ZDOTDIR] Z=[\$ZDOTDIR]"', 'true'],
          extraEnv: {'ZDOTDIR': zdot.path},
        );
        expect(out, contains('F=[yes] Z=[${zdot.path}]'));
        expect(out, contains('$esc]133;D;0$bel'));
      },
      skip: hasZsh ? null : 'no /bin/zsh',
    );

    test('an existing shellx command wins over the hook function', () async {
      final bin = Directory('${home.path}/bin')..createSync();
      final real = File('${bin.path}/shellx')
        ..writeAsStringSync(
          '#!/bin/sh\necho REAL'
          '-SHELLX "\$@"\n',
        );
      await Process.run('chmod', ['+x', real.path]);
      for (final shell in [
        if (hasZsh)
          const ShellCommand(
            executable: '/bin/zsh',
            arguments: ['-i'],
            name: 'zsh',
          ),
        if (hasBash)
          const ShellCommand(
            executable: '/bin/bash',
            arguments: ['-i'],
            name: 'bash',
          ),
      ]) {
        final out = await run(
          shell,
          [
            'export PATH="${bin.path}:\$PATH"; hash -r 2>/dev/null',
            'shellx notify x',
          ],
          extraEnv: {'PATH': '${bin.path}:/usr/bin:/bin'},
        );
        expect(out, contains('REAL-SHELLX notify x'), reason: shell.name);
        expect(out, isNot(contains(']777;')), reason: shell.name);
      }
    });

    test('bash: E, C and D;1, ~/.bashrc loads, a user PROMPT_COMMAND keeps '
        'working, an empty line is no command, shellx notify works', () async {
      File('${home.path}/.bashrc').writeAsStringSync(
        'shopt -s expand_aliases\n'
        'alias hi="echo ALIAS'
        '-OK"\n'
        'PROMPT_COMMAND="echo PC'
        '-RAN;"\n',
      );
      final out = await run(
        const ShellCommand(
          executable: '/bin/bash',
          arguments: [],
          name: 'bash',
        ),
        ['hi', '', 'sleep 1; false', 'shellx notify hello there'],
      );
      expect(out, contains('ALIAS-OK'));
      expect(out, contains('PC-RAN'));
      expect(out, contains('$esc]633;E;sleep 1\\x3b false$bel$esc]133;C$bel'));
      expect(out, contains('$esc]133;D;1$bel'));
      expect(out, contains('$esc]777;notify;;hello there$bel'));
      // hi, sleep, shellx, exit: one C each; the empty line is none.
      expect(']133;C'.allMatches(out), hasLength(4));
    }, skip: hasBash ? null : 'no /bin/bash');

    test('bash: an array PROMPT_COMMAND (bash 5.1+) gets start and end as its '
        'first and last elements, once (this machine has bash 3.2 only: the '
        'generated array is checked, not bash 5.1 running it)', () async {
      File('${home.path}/.bashrc').writeAsStringSync(
        'PROMPT_COMMAND=(user_one user_two)\n'
        'user_one() { :; }; user_two() { :; }\n',
      );
      final out = await run(
        const ShellCommand(
          executable: '/bin/bash',
          arguments: [],
          name: 'bash',
        ),
        ['true', 'true', r'echo "PC=[${PROMPT_COMMAND[*]}]"'],
      );
      expect(
        out,
        contains(
          'PC=[__shellx_prompt_start user_one user_two __shellx_prompt_end]',
        ),
      );
    }, skip: hasBash ? null : 'no /bin/bash');

    test('bash: a PROMPT_COMMAND appended to later (scalar, then array) is '
        'wrapped again: real commands keep their own line, the appended '
        'prompt command is never reported', () async {
      File('${home.path}/.bashrc').writeAsStringSync(
        'PROMPT_COMMAND=user_one\n'
        'user_one() { :; }; user_two() { :; }; user_three() { :; }\n',
      );
      final out = await run(
        const ShellCommand(
          executable: '/bin/bash',
          arguments: [],
          name: 'bash',
        ),
        [
          r'PROMPT_COMMAND="$PROMPT_COMMAND; user_two"',
          'sleep 0.1; false',
          'echo after'
              '-scalar',
          'PROMPT_COMMAND+=(user_three)',
          'true',
          r'echo "PC=[${PROMPT_COMMAND[*]}]"',
        ],
      );
      expect(out, isNot(contains(']633;E;user_')));
      expect(
        out,
        contains('$esc]633;E;sleep 0.1\\x3b false$bel$esc]133;C$bel'),
      );
      expect(out, contains('$esc]133;D;1$bel'));
      expect(out, contains(']633;E;echo after-scalar'));
      // bash 3.2 here: the rebuilt array is checked, bash 5.1 does not run it.
      expect(
        out,
        contains(
          'PC=[__shellx_prompt_start user_one; user_two user_three '
          '__shellx_prompt_end]',
        ),
      );
    }, skip: hasBash ? null : 'no /bin/bash');

    final bashPreexec =
        '${Directory.current.path}/../../term/tests/fixtures/bash-preexec.sh';

    test(
      'bash with bash-preexec in ~/.bashrc: ShellX uses preexec/precmd '
      'functions; both ShellX and the user hooks see every command',
      () async {
        File('${home.path}/.bashrc').writeAsStringSync(
          "source '$bashPreexec'\n"
          'preexec() { echo "PRE""EXEC[\$1]"; }\n'
          'precmd() { echo "PRE""CMD"; }\n',
        );
        final out = await run(
          const ShellCommand(
            executable: '/bin/bash',
            arguments: [],
            name: 'bash',
          ),
          ['echo one', 'false', 'echo three', 'echo three'],
          pty: true,
        );
        for (final line in ['echo one', 'false', 'echo three']) {
          expect(out, contains('$esc]633;E;$line$bel$esc]133;C$bel'));
          expect(out, contains('PREEXEC[$line]'));
        }
        expect(out, contains('$esc]133;D;1$bel'));
        // echo one, false, echo three twice, exit.
        expect(']633;E;'.allMatches(out), hasLength(5));
        expect('PREEXEC['.allMatches(out), hasLength(5));
        expect(out, isNot(contains(']633;E;__bp')));
      },
      skip: hasBash && File('/usr/bin/script').existsSync() && Platform.isMacOS
          ? null
          : 'needs /bin/bash and macOS script(1) for a pty',
    );

    test('bash with set -u or extdebug in ~/.bashrc: no errors, every command '
        'runs and is reported, nothing inside functions', () async {
      for (final rc in [
        'set -u\n',
        'shopt -s extdebug\nf() { local x=1; echo in'
            '-f; return 3; }\n',
      ]) {
        File('${home.path}/.bashrc').writeAsStringSync(rc);
        final out = await run(
          const ShellCommand(
            executable: '/bin/bash',
            arguments: [],
            name: 'bash',
          ),
          [
            'echo one',
            if (rc.contains('extdebug')) 'f' else 'false',
            r'PROMPT_COMMAND="$PROMPT_COMMAND; true"',
            'echo after',
          ],
        );
        expect(out, isNot(contains('unbound variable')), reason: rc);
        expect(out, contains('after\n'), reason: rc);
        expect(out, contains(']633;E;echo after'), reason: rc);
        expect(
          out,
          contains(rc.contains('extdebug') ? ']133;D;3' : ']133;D;1'),
          reason: rc,
        );
        if (rc.contains('extdebug')) expect(out, contains('in-f'));
        for (final inner in [']633;E;local', ']633;E;return', ']633;E;true']) {
          expect(out, isNot(contains(inner)), reason: rc);
        }
      }
    }, skip: hasBash ? null : 'no /bin/bash');

    test(
      'bash -l: the login files load instead of ~/.bashrc',
      () async {
        File('${home.path}/.bash_profile').writeAsStringSync(
          'echo PROFILE'
          '-RAN\n',
        );
        File('${home.path}/.bashrc').writeAsStringSync(
          'echo BASHRC'
          '-RAN\n',
        );
        final out = await run(
          const ShellCommand(
            executable: '/bin/bash',
            arguments: ['-l'],
            name: 'bash',
          ),
          ['true'],
        );
        expect(out, contains('PROFILE-RAN'));
        expect(out, isNot(contains('BASHRC-RAN')));
        expect(out, contains('$esc]133;D;0$bel'));
      },
      skip: hasBash ? null : 'no /bin/bash',
    );

    test(
      'bash: a user DEBUG trap is left alone (no hook)',
      () async {
        File('${home.path}/.bashrc').writeAsStringSync("trap 'true' DEBUG\n");
        final out = await run(
          const ShellCommand(
            executable: '/bin/bash',
            arguments: [],
            name: 'bash',
          ),
          [
            'echo still'
                '-fine',
          ],
        );
        expect(out, contains('still-fine'));
        expect(out, isNot(contains(']133;')));
      },
      skip: hasBash ? null : 'no /bin/bash',
    );
  }, testOn: 'mac-os || linux');
}
