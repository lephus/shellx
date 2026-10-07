import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/cli/cli_install.dart';
import 'package:shellx_desktop/src/terminal_sharing/sharing_paths.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_install'));
  tearDown(() => dir.delete(recursive: true));

  test('paths (D7): <support>/cli beside bin, the same bundled binary as '
      'terminal sharing', () {
    final m = CliPaths.macos(
      home: '/Users/me',
      executable: '/Applications/ShellX.app/Contents/MacOS/ShellX',
    );
    expect(m.dir, '/Users/me/Library/Application Support/ShellX/cli');
    expect(m.binary, '/Users/me/Library/Application Support/ShellX/cli/shellx');
    expect(
      m.bundledBinary,
      '/Applications/ShellX.app/Contents/Helpers/shellx-term',
    );
    expect(m.systemLink, '/usr/local/bin/shellx');
    expect(m.windows, isFalse);
    final w = CliPaths.windows(
      localAppData: r'C:\Users\me\AppData\Local',
      executable: r'C:\Program Files\ShellX\ShellX.exe',
    );
    expect(w.dir, r'C:\Users\me\AppData\Local\ShellX\cli');
    expect(w.binary, r'C:\Users\me\AppData\Local\ShellX\cli\shellx.exe');
    expect(w.bundledBinary, r'C:\Program Files\ShellX\shellx-term.exe');
    expect(w.systemLink, '');
    expect(w.windows, isTrue);
    // Built from SharingPaths: one formula for the bundled binary.
    final sharing = SharingPaths.macos(
      home: '/Users/me',
      executable: '/Applications/ShellX.app/Contents/MacOS/ShellX',
    );
    expect(CliPaths.of(sharing).bundledBinary, sharing.bundledBinary);
    expect(
      CliPaths.forPlatform(
        windows: false,
        environment: const {},
        executable: '/x',
      ),
      isNull,
    );
  });

  test('environment (D8, D29, amendment): PATH first, SHELLX_SOCKET, '
      'SHELLX_CLI_TOKEN', () {
    final mac = cliSessionEnvironment(
      {'PATH': '/usr/bin', 'HOME': '/h'},
      cliDir: '/c',
      socket: '/s',
      token: 'ab' * 32,
      windows: false,
    );
    expect(mac['PATH'], '/c:/usr/bin');
    expect(mac['SHELLX_SOCKET'], '/s');
    expect(mac['SHELLX_CLI_TOKEN'], 'ab' * 32);
    expect(mac['HOME'], '/h');
    final win = cliSessionEnvironment(
      {'Path': r'C:\Windows'},
      cliDir: r'C:\c',
      socket: r'\\.\pipe\x',
      token: 't',
      windows: true,
    );
    expect(win['Path'], r'C:\c;C:\Windows');
    expect(win.containsKey('PATH'), isFalse);
    expect(win['SHELLX_CLI_TOKEN'], 't');
    expect(
      cliSessionEnvironment(
        {},
        cliDir: '/c',
        socket: '/s',
        token: 't',
        windows: false,
      )['PATH'],
      '/c',
    );
    expect(
      cliSessionEnvironment(
        {},
        cliDir: r'C:\c',
        socket: 'p',
        token: 't',
        windows: true,
      )['Path'],
      r'C:\c',
    );
  });

  test('final M1: without a running host the shells get the folder on PATH '
      'but no address or token (not even inherited ones)', () {
    final env = cliSessionEnvironment(
      {'PATH': '/usr/bin', 'SHELLX_SOCKET': '/old', 'SHELLX_CLI_TOKEN': 'old'},
      cliDir: '/c',
      socket: null,
      token: null,
      windows: false,
    );
    expect(env['PATH'], '/c:/usr/bin');
    expect(env.containsKey('SHELLX_SOCKET'), isFalse);
    expect(env.containsKey('SHELLX_CLI_TOKEN'), isFalse);
  });

  test('the per-launch token: 32 random bytes as 64 hex digits', () {
    final a = generateCliToken();
    final b = generateCliToken();
    expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(a, isNot(b));
  });

  test('installs a copy named shellx when different; idempotent', () async {
    final bundled = File('${dir.path}/app/shellx-term')
      ..createSync(recursive: true)
      ..writeAsStringSync('v1');
    final paths = CliPaths.forTest(
      dir: '${dir.path}/cli',
      binary: '${dir.path}/cli/shellx',
      bundled: bundled.path,
    );
    final modes = <String>[];
    final i = CliBinaryInstaller(
      paths,
      chmod: (mode, path) async => modes.add(mode),
    );
    expect(await i.ensureCurrent(), isTrue);
    expect(File(paths.binary).readAsStringSync(), 'v1');
    expect(modes, ['755']);
    expect(await i.ensureCurrent(), isFalse); // already current
    bundled.writeAsStringSync('v2');
    expect(await i.ensureCurrent(), isTrue);
    expect(File(paths.binary).readAsStringSync(), 'v2');
    // No temp file left beside it.
    expect(Directory(paths.dir).listSync().map((e) => e.path), [paths.binary]);
    await i.remove();
    expect(Directory(paths.dir).existsSync(), isFalse);
  });

  test('no bundled binary (a dev build): nothing copied', () async {
    final paths = CliPaths.forTest(
      dir: '${dir.path}/cli',
      binary: '${dir.path}/cli/shellx',
      bundled: '${dir.path}/missing',
    );
    final i = CliBinaryInstaller(paths, chmod: (_, _) async {});
    expect(await i.ensureCurrent(), isFalse);
    expect(Directory(paths.dir).existsSync(), isFalse);
  });

  group('macOS PATH install (D8)', () {
    late CliPaths paths;
    late String link;
    setUp(() {
      link = '${dir.path}/bin/shellx';
      paths = CliPaths.forTest(
        dir: '/c',
        binary: '/c/shellx',
        bundled: '/b',
        systemLink: link,
      );
    });

    test('direct symlink when the folder is writable', () async {
      Directory('${dir.path}/bin').createSync();
      final direct = MacPathInstaller(
        paths,
        run: (exe, args) async => throw StateError('no prompt'),
        writable: (_) async => true,
      );
      expect(await direct.installed, isFalse);
      expect(await direct.install(), PathInstallResult.installed);
      expect(Link(link).targetSync(), '/c/shellx');
      expect(await direct.installed, isTrue);
      // Again: still ours, nothing changes.
      expect(await direct.install(), PathInstallResult.installed);
      expect(await direct.uninstall(), PathInstallResult.installed);
      expect(Link(link).existsSync(), isFalse);
    });

    test('admin prompt otherwise: fixed, quoted paths; cancel maps to '
        'cancelled, other errors to failed', () async {
      final calls = <List<String>>[];
      var outcome = const ProcessOutcome(
        exitCode: 1,
        stderr: '0:1: execution error: User canceled. (-128)',
      );
      final prompt = MacPathInstaller(
        paths,
        run: (exe, args) async {
          calls.add([exe, ...args]);
          return outcome;
        },
        writable: (_) async => false,
      );
      expect(await prompt.install(), PathInstallResult.cancelled);
      expect(calls.single.first, '/usr/bin/osascript');
      expect(calls.single[1], '-e');
      final script = calls.single.last;
      expect(script, startsWith('do shell script "'));
      expect(script, endsWith('" with administrator privileges'));
      // I1: never -f: a file that appeared meanwhile makes ln fail.
      expect(script, contains("ln -sh '/c/shellx' '$link'"));
      expect(script, isNot(contains('ln -sf')));
      expect(script, contains("mkdir -p '${dir.path}/bin'"));

      outcome = const ProcessOutcome(exitCode: 1, stderr: 'boom');
      expect(await prompt.install(), PathInstallResult.failed);
      outcome = const ProcessOutcome(exitCode: 0);
      expect(await prompt.install(), PathInstallResult.installed);
    });

    test('a path with quotes and backslashes is quoted for the shell and '
        'for AppleScript', () async {
      final odd = CliPaths.forTest(
        dir: '/c',
        binary: '/U/o\'b "x"\\y/shellx',
        bundled: '/b',
        systemLink: link,
      );
      String? script;
      final prompt = MacPathInstaller(
        odd,
        run: (exe, args) async {
          script = args.last;
          return const ProcessOutcome(exitCode: 0);
        },
        writable: (_) async => false,
      );
      await prompt.install();
      // Shell: '/U/o'\''b "x"\y/shellx'; then AppleScript escapes \ and ".
      expect(script, contains(r"""ln -sh '/U/o'\\''b \"x\"\\y/shellx'"""));
    });

    test('never replaces someone else\'s shellx', () async {
      Directory('${dir.path}/bin').createSync();
      File(link).writeAsStringSync('other tool');
      final installer = MacPathInstaller(
        paths,
        run: (exe, args) async => throw StateError('no prompt'),
        writable: (_) async => true,
      );
      expect(await installer.installed, isFalse);
      expect(await installer.install(), PathInstallResult.failed);
      expect(File(link).readAsStringSync(), 'other tool');
      // Not ours: uninstall leaves it.
      expect(await installer.uninstall(), PathInstallResult.installed);
      expect(File(link).readAsStringSync(), 'other tool');

      File(link).deleteSync();
      Link(link).createSync('/elsewhere/shellx');
      expect(await installer.install(), PathInstallResult.failed);
      expect(await installer.uninstall(), PathInstallResult.installed);
      expect(Link(link).targetSync(), '/elsewhere/shellx');
    });

    test('uninstall through the admin prompt when the folder is not '
        'writable', () async {
      Directory('${dir.path}/bin').createSync();
      Link(link).createSync('/c/shellx');
      final calls = <String>[];
      final installer = MacPathInstaller(
        paths,
        run: (exe, args) async {
          calls.add(args.last);
          return const ProcessOutcome(exitCode: 1, stderr: '(-128)');
        },
        writable: (_) async => false,
      );
      expect(await installer.uninstall(), PathInstallResult.cancelled);
      // M2: ownership checked again as root, right before the removal
      // (AppleScript escapes the quotes).
      expect(
        calls.single,
        contains(
          r'[ \"$(readlink '
          "'$link'"
          r')\" = '
          "'/c/shellx'"
          " ] && "
          "rm -f '$link'",
        ),
      );
      expect(calls.single, endsWith('with administrator privileges'));
    });
  });

  test('Windows PATH install edits HKCU Path once and broadcasts', () async {
    final reg = MemoryRegistry({'Path': r'C:\Tools;%USERPROFILE%\bin'});
    var broadcasts = 0;
    final paths = CliPaths.forTest(
      dir: r'C:\L\ShellX\cli',
      binary: r'C:\L\ShellX\cli\shellx.exe',
      bundled: 'x',
      systemLink: '',
      windows: true,
    );
    final w = WindowsPathInstaller(
      paths,
      reg: reg,
      broadcast: () => broadcasts++,
    );
    expect(await w.installed, isFalse);
    expect(await w.install(), PathInstallResult.installed);
    expect(await w.install(), PathInstallResult.installed);
    expect(reg.values['Path'], r'C:\Tools;%USERPROFILE%\bin;C:\L\ShellX\cli');
    expect(await w.installed, isTrue);
    expect(await w.uninstall(), PathInstallResult.installed);
    expect(reg.values['Path'], r'C:\Tools;%USERPROFILE%\bin');
    expect(await w.uninstall(), PathInstallResult.installed);
    expect(broadcasts, 2);

    // Case and a trailing backslash do not make it a second entry; every
    // copy goes on uninstall.
    reg.values['Path'] = r'c:\l\shellx\CLI\;C:\Tools;C:\L\ShellX\cli';
    expect(await w.installed, isTrue);
    await w.install();
    expect(reg.values['Path'], r'c:\l\shellx\CLI\;C:\Tools;C:\L\ShellX\cli');
    await w.uninstall();
    expect(reg.values['Path'], r'C:\Tools');

    // M4: everything else stays byte for byte, empty segments included.
    reg.values['Path'] = r';C:\Tools;;C:\L\ShellX\cli;%X%;';
    await w.uninstall();
    expect(reg.values['Path'], r';C:\Tools;;%X%;');
    // Always a separator of our own, so removing it restores the value.
    await w.install();
    expect(reg.values['Path'], r';C:\Tools;;%X%;;C:\L\ShellX\cli');
    await w.uninstall();
    expect(reg.values['Path'], r';C:\Tools;;%X%;');
    reg.values['Path'] = r'C:\A;;C:\B';
    await w.install();
    expect(reg.values['Path'], r'C:\A;;C:\B;C:\L\ShellX\cli');

    // No Path value yet.
    final empty = MemoryRegistry({});
    await WindowsPathInstaller(paths, reg: empty, broadcast: () {}).install();
    expect(empty.values['Path'], r'C:\L\ShellX\cli');
  });

  group('M10: is /usr/local/bin on the login shell\'s PATH?', () {
    LoginPathCheck check(
      String shell,
      ProcessOutcome outcome, {
      List<List<String>>? calls,
    }) => LoginPathCheck(
      shell: shell,
      linkDir: '/usr/local/bin',
      run: (exe, args) async {
        calls?.add([exe, ...args]);
        return outcome;
      },
    );

    test('on the PATH: no hint; runs the shell as a login shell', () async {
      final calls = <List<String>>[];
      final hint = await check(
        '/bin/zsh',
        const ProcessOutcome(
          exitCode: 0,
          stdout: '\x1e/opt/x:/usr/local/bin:/usr/bin\x1e',
        ),
        calls: calls,
      ).missing();
      expect(hint, isNull);
      expect(calls.single, [
        '/bin/zsh',
        '-lc',
        r"printf '\036%s\036' "
            r'"$PATH"',
      ]);
    });

    test('profile noise around the marked PATH is ignored', () async {
      // A profile that prints a banner naming /usr/local/bin: only the
      // marked PATH counts.
      final hint = await check(
        '/bin/zsh',
        const ProcessOutcome(
          exitCode: 0,
          stdout: 'motd /usr/local/bin:\n\x1e/usr/bin:/bin\x1e\nbye',
        ),
      ).missing();
      expect(hint?.file, '~/.zprofile');
      // Noise before, PATH has it: no hint.
      expect(
        await check(
          '/bin/zsh',
          const ProcessOutcome(
            exitCode: 0,
            stdout: 'hello\n\x1e/usr/local/bin:/bin\x1e',
          ),
        ).missing(),
        isNull,
      );
      // No markers (the shell printed something else): unknown, no hint.
      expect(
        await check(
          '/bin/zsh',
          const ProcessOutcome(exitCode: 0, stdout: '/usr/bin:/bin'),
        ).missing(),
        isNull,
      );
    });

    test(
      'missing: the exact line and the file for zsh / bash / other',
      () async {
        const out = ProcessOutcome(
          exitCode: 0,
          stdout: '\x1e/usr/bin:/bin\x1e',
        );
        final zsh = (await check('/bin/zsh', out).missing())!;
        expect(zsh.file, '~/.zprofile');
        expect(zsh.line, 'export PATH="/usr/local/bin:\$PATH"');
        expect(
          (await check('/opt/homebrew/bin/bash', out).missing())!.file,
          '~/.bash_profile',
        );
        // An unknown shell (fish…) is not run: zsh is asked instead.
        final calls = <List<String>>[];
        final other = (await check(
          '/usr/local/bin/fish',
          out,
          calls: calls,
        ).missing())!;
        expect(calls.single.first, '/bin/zsh');
        expect(other.file, '~/.zprofile');
      },
    );

    test('the shell failed or timed out: unknown, no hint', () async {
      expect(
        await check('/bin/zsh', const ProcessOutcome(exitCode: 1)).missing(),
        isNull,
      );
      final slow = LoginPathCheck(
        shell: '/bin/zsh',
        linkDir: '/usr/local/bin',
        run: (exe, args) => throw const ProcessTimeout(),
      );
      expect(await slow.missing(), isNull);
    });

    test('the real runner is bounded: a hung shell is killed', () async {
      final run = boundedProcessRunner(const Duration(milliseconds: 200));
      final watch = Stopwatch()..start();
      await expectLater(
        run('/bin/sleep', ['5']),
        throwsA(isA<ProcessTimeout>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      final ok = await run('/bin/echo', ['hi']);
      expect(ok.stdout.trim(), 'hi');
    });

    test('the bound covers the output too: a child that keeps stdout open '
        'after its parent exits is a timeout', () async {
      final run = boundedProcessRunner(const Duration(milliseconds: 300));
      final watch = Stopwatch()..start();
      await expectLater(
        run('/bin/sh', ['-c', '/bin/sleep 5 & exit 0']),
        throwsA(isA<ProcessTimeout>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a process killed by a signal is an outcome, not a timeout', () async {
      final run = boundedProcessRunner(const Duration(seconds: 2));
      // SIGHUP: Dart reports -1, the old timeout sentinel.
      final r = await run('/bin/sh', ['-c', r'kill -HUP $$']);
      expect(r.exitCode, -1);
    });
  });
}
