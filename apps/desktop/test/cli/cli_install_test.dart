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
      expect(script, contains("ln -sf '/c/shellx' '$link'"));
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
      expect(script, contains(r"""ln -sf '/U/o'\\''b \"x\"\\y/shellx'"""));
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
      expect(calls.single, contains("rm -f '$link'"));
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

    // No Path value yet.
    final empty = MemoryRegistry({});
    await WindowsPathInstaller(paths, reg: empty, broadcast: () {}).install();
    expect(empty.values['Path'], r'C:\L\ShellX\cli');
  });
}
