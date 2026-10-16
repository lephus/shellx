import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/terminal_sharing/config_file_editor.dart';
import 'package:shellx_desktop/src/terminal_sharing/powershell.dart';
import 'package:shellx_desktop/src/terminal_sharing/sharing_paths.dart';
import 'package:shellx_desktop/src/terminal_sharing/shell_blocks.dart';
import 'package:shellx_desktop/src/terminal_sharing/term_binary.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

/// Fails on the [failOn]-th install (1-based), like a file it may not write.
class FailingEditor extends ConfigFileEditor {
  FailingEditor(this.failOn);
  final int failOn;
  int installs = 0;

  @override
  Future<ConfigEdit> install(ConfigTarget target) async {
    if (++installs == failOn) {
      throw FileSystemException('permission denied', target.path);
    }
    return super.install(target);
  }
}

class FakePowerShellProbe extends PowerShellProbe {
  FakePowerShellProbe(this.installs) : super(environment: const {});
  List<PowerShellInstall> installs;
  final List<PowerShellInstall> allowed = [];

  @override
  Future<List<PowerShellInstall>> find() async => installs;

  @override
  Future<bool> allowLocalScripts(PowerShellInstall install) async {
    allowed.add(install);
    return true;
  }
}

void main() {
  late Directory dir;
  late String home;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shellx-setup-');
    home = p.join(dir.path, 'home');
    Directory(home).createSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String inHome(String name) => p.join(home, name);

  SharingPaths paths({bool windows = false}) {
    final support = p.join(dir.path, 'support');
    return SharingPaths(
      windows: windows,
      home: home,
      binDir: p.join(support, 'bin'),
      binary: p.join(
        support,
        'bin',
        windows ? 'shellx-term.exe' : 'shellx-term',
      ),
      termDir: p.join(support, 'term'),
      bundledBinary: p.join(dir.path, 'app', 'shellx-term'),
    );
  }

  void bundle([String content = 'v1']) {
    final file = File(p.join(dir.path, 'app', 'shellx-term'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  TerminalSharingSetup setup({
    bool windows = false,
    ConfigFileEditor editor = const ConfigFileEditor(),
    PowerShellProbe? powerShell,
  }) {
    final ps = paths(windows: windows);
    return TerminalSharingSetup(
      paths: ps,
      binary: TermBinaryInstaller(ps, chmod: (_, _) async {}),
      editor: editor,
      powerShell: powerShell,
    );
  }

  group('macOS plan', () {
    test('only .zshrc (created) when there is no bash file', () async {
      final plan = await setup().prepare();
      expect(plan.files.map((f) => f.path), [inHome('.zshrc')]);
      expect(plan.files.single.exists, isFalse);
      expect(plan.bashSkipped, isTrue);
    });

    test(
      'bash files only when they exist; .bash_profile is never created',
      () async {
        File(inHome('.zshrc')).writeAsStringSync('');
        File(inHome('.bashrc')).writeAsStringSync('');
        final plan = await setup().prepare();
        expect(plan.files.map((f) => f.path), [
          inHome('.zshrc'),
          inHome('.bashrc'),
        ]);
        expect(plan.files.map((f) => f.target.block), [zshBlock, bashBlock]);
        expect(plan.bashSkipped, isFalse);
        expect(plan.files.every((f) => f.exists), isTrue);

        bundle();
        await setup().enable(plan);
        expect(File(inHome('.bash_profile')).existsSync(), isFalse);
      },
    );
  });

  group('enable', () {
    test('installs the binary, then the blocks, with backups', () async {
      bundle();
      File(inHome('.zshrc')).writeAsStringSync('export A=1\n');
      File(inHome('.bash_profile')).writeAsStringSync('. ~/.profile\n');
      File(inHome('.bashrc')).writeAsStringSync('alias x=y\n');
      final s = setup();
      await s.enable(await s.prepare());

      expect(File(paths().binary).readAsStringSync(), 'v1');
      expect(
        File(inHome('.zshrc')).readAsStringSync(),
        '${zshBlock}export A=1\n',
      );
      expect(
        File(inHome('.bash_profile')).readAsStringSync(),
        '$bashBlock. ~/.profile\n',
      );
      expect(
        File(inHome('.bashrc')).readAsStringSync(),
        '${bashBlock}alias x=y\n',
      );
      for (final name in ['.zshrc', '.bash_profile', '.bashrc']) {
        expect(File(inHome('$name.shellx-backup')).existsSync(), isTrue);
      }
      expect(await s.needsSetup(), isFalse);
    });

    test('enabling twice leaves one block per file', () async {
      bundle();
      File(inHome('.zshrc')).writeAsStringSync('x\n');
      final s = setup();
      await s.enable(await s.prepare());
      await s.enable(await s.prepare());
      expect(File(inHome('.zshrc')).readAsStringSync(), '${zshBlock}x\n');
    });

    test('no blocks are written when the binary cannot be installed', () async {
      File(inHome('.zshrc')).writeAsStringSync('x\n');
      final s = setup(); // No bundled binary.
      await expectLater(
        s.enable(await s.prepare()),
        throwsA(isA<SharingSetupException>()),
      );
      expect(File(inHome('.zshrc')).readAsStringSync(), 'x\n');
    });

    test('a failing file undoes every earlier step', () async {
      bundle();
      File(inHome('.zshrc')).writeAsStringSync('x\n');
      File(inHome('.bash_profile')).writeAsStringSync('y\n');
      final s = setup(editor: FailingEditor(2));
      await expectLater(
        s.enable(await s.prepare()),
        throwsA(isA<SharingSetupException>()),
      );
      expect(File(inHome('.zshrc')).readAsStringSync(), 'x\n');
      expect(File(inHome('.zshrc.shellx-backup')).existsSync(), isFalse);
      expect(File(inHome('.bash_profile')).readAsStringSync(), 'y\n');
      expect(Directory(paths().binDir).existsSync(), isFalse);
    });

    test('a created .zshrc is deleted again by undo', () async {
      bundle();
      final s = setup();
      final install = await s.enable(await s.prepare());
      expect(File(inHome('.zshrc')).existsSync(), isTrue);
      await install.undo();
      expect(File(inHome('.zshrc')).existsSync(), isFalse);
      expect(Directory(paths().binDir).existsSync(), isFalse);
    });
  });

  group('disable', () {
    test(
      'removes every block and bin, keeps the rest, calls stopServer between',
      () async {
        bundle();
        File(inHome('.zshrc')).writeAsStringSync('x\n');
        File(inHome('.bashrc')).writeAsStringSync('y\n');
        final s = setup();
        await s.enable(await s.prepare());
        final order = <String>[];
        final result = await s.disable(
          stopServer: () async {
            order.add('server');
            expect(File(inHome('.zshrc')).readAsStringSync(), 'x\n');
            expect(File(paths().binary).existsSync(), isTrue);
          },
        );
        expect(order, ['server']);
        expect(result.complete, isTrue);
        expect(File(inHome('.zshrc')).readAsStringSync(), 'x\n');
        expect(File(inHome('.bashrc')).readAsStringSync(), 'y\n');
        expect(Directory(paths().binDir).existsSync(), isFalse);
      },
    );

    test('also cleans a bash file created after enabling', () async {
      File(inHome('.bash_profile')).writeAsStringSync('${bashBlock}z\n');
      final result = await setup().disable();
      expect(result.complete, isTrue);
      expect(File(inHome('.bash_profile')).readAsStringSync(), 'z\n');
    });
  });

  group('needsSetup', () {
    test('binary missing, block missing, or block out of date', () async {
      bundle();
      final s = setup();
      expect(await s.needsSetup(), isTrue);
      await s.enable(await s.prepare());
      expect(await s.needsSetup(), isFalse);

      File(inHome('.zshrc')).writeAsStringSync('user removed it\n');
      expect(await s.needsSetup(), isTrue);

      File(
        inHome('.zshrc'),
      ).writeAsStringSync('# >>> ShellX >>>\nold\n# <<< ShellX <<<\n');
      expect(await s.needsSetup(), isTrue);

      await s.enable(await s.prepare());
      File(paths().binary).deleteSync();
      expect(await s.needsSetup(), isTrue);
    });

    test('a bash file created later needs setup again', () async {
      bundle();
      final s = setup();
      await s.enable(await s.prepare());
      File(inHome('.bashrc')).writeAsStringSync('');
      expect(await s.needsSetup(), isTrue);
    });
  });

  group('maintain', () {
    test(
      'on: replaces an outdated binary, leaves a missing one missing',
      () async {
        bundle('v1');
        final s = setup();
        await s.maintain(enabled: true);
        expect(File(paths().binary).existsSync(), isFalse);
        await s.enable(await s.prepare());
        bundle('v2');
        await s.maintain(enabled: true);
        expect(File(paths().binary).readAsStringSync(), 'v2');
      },
    );

    test('off: a bin left behind is removed', () async {
      bundle();
      final s = setup();
      await s.binary.install();
      await s.maintain(enabled: false);
      expect(Directory(paths().binDir).existsSync(), isFalse);
    });

    test('Windows on: stale .old copies are deleted', () async {
      bundle('v1');
      final s = setup(windows: true, powerShell: FakePowerShellProbe([]));
      await s.binary.install();
      bundle('v2');
      await s.maintain(enabled: true);
      expect(
        Directory(paths().binDir).listSync().map((e) => p.basename(e.path)),
        ['shellx-term.exe'],
      );
    });
  });

  group('Windows', () {
    PowerShellInstall install(
      String name,
      String profile,
      ScriptPolicy policy,
    ) => PowerShellInstall(
      name: name,
      executable: '$name.exe',
      profilePath: profile,
      policy: policy,
    );

    test(
      'plan: one profile per PowerShell, created with CRLF; Group Policy blocked ones skipped',
      () async {
        final pwsh = install(
          'pwsh',
          inHome(p.join('Documents', 'PowerShell', 'profile.ps1')),
          ScriptPolicy.allowed,
        );
        final win = install(
          'powershell',
          inHome(p.join('Documents', 'WindowsPowerShell', 'profile.ps1')),
          ScriptPolicy.blockedByGroupPolicy,
        );
        final probe = FakePowerShellProbe([pwsh, win]);
        final s = setup(windows: true, powerShell: probe);
        final plan = await s.prepare();
        expect(plan.files.map((f) => f.path), [pwsh.profilePath]);
        expect(plan.powerShells, [pwsh, win]);

        bundle();
        await s.enable(plan);
        expect(
          File(pwsh.profilePath).readAsStringSync(),
          powerShellBlock.replaceAll('\n', '\r\n'),
        );
        expect(File(paths(windows: true).binary).existsSync(), isTrue);
        expect(await s.needsSetup(), isFalse);

        final result = await s.cleanup();
        expect(result.complete, isTrue);
        expect(File(pwsh.profilePath).readAsStringSync(), '');
        expect(Directory(paths(windows: true).binDir).existsSync(), isFalse);
      },
    );

    test('cleanup also deletes the term folder', () async {
      final term = Directory(paths(windows: true).termDir)
        ..createSync(recursive: true);
      File(p.join(term.path, 'endpoint')).writeAsStringSync('v=1');
      await setup(windows: true, powerShell: FakePowerShellProbe([])).cleanup();
      expect(term.existsSync(), isFalse);
    });

    test('allowLocalScripts goes to the probe', () async {
      final blocked = install('powershell', r'C:\p.ps1', ScriptPolicy.blocked);
      final probe = FakePowerShellProbe([blocked]);
      final s = setup(windows: true, powerShell: probe);
      expect(await s.allowLocalScripts(blocked), isTrue);
      expect(probe.allowed, [blocked]);
    });
  });

  group('fix wave', () {
    test(
      'binary install failing after bin was created leaves no bin',
      () async {
        bundle();
        final ps = paths();
        final s = TerminalSharingSetup(
          paths: ps,
          binary: TermBinaryInstaller(
            ps,
            chmod: (_, _) async => throw const FileSystemException('chmod'),
          ),
        );
        await expectLater(
          s.enable(await s.prepare()),
          throwsA(
            isA<SharingSetupException>().having(
              (e) => e.path,
              'path',
              ps.binary,
            ),
          ),
        );
        expect(Directory(ps.binDir).existsSync(), isFalse);
        expect(File(inHome('.zshrc')).existsSync(), isFalse);
      },
    );

    test('a failing file is named in the error', () async {
      bundle();
      File(inHome('.bash_profile')).writeAsStringSync('y\n');
      final s = setup(editor: FailingEditor(2));
      await expectLater(
        s.enable(await s.prepare()),
        throwsA(
          isA<SharingSetupException>().having(
            (e) => e.path,
            'path',
            inHome('.bash_profile'),
          ),
        ),
      );
    });

    test(
      'a dangling bash symlink counts as missing; a dangling .zshrc is refused by name',
      () async {
        bundle();
        Link(inHome('.bashrc')).createSync(p.join(dir.path, 'nowhere'));
        final s = setup();
        final plan = await s.prepare();
        expect(plan.files.map((f) => f.path), [inHome('.zshrc')]);
        expect(plan.bashSkipped, isTrue);
        await s.enable(plan);
        await s.disable();
        File(
          inHome('.zshrc'),
        ).deleteSync(); // Created by enable, kept by disable.

        Link(
          inHome('.zshrc'),
        ).createSync(p.join(dir.path, 'dotfiles', 'zshrc'));
        await expectLater(
          s.enable(await s.prepare()),
          throwsA(
            isA<SharingSetupException>().having(
              (e) => e.path,
              'path',
              inHome('.zshrc'),
            ),
          ),
        );
        expect(Directory(paths().binDir).existsSync(), isFalse);
      },
      skip: Platform.isWindows ? 'symlinks need privileges on Windows' : false,
    );

    test('enable reports the files it changed', () async {
      bundle();
      File(inHome('.bashrc')).writeAsStringSync('');
      final s = setup();
      final install = await s.enable(await s.prepare());
      expect(install.editedFiles, [inHome('.zshrc'), inHome('.bashrc')]);
    });

    test(
      'Windows disable also cleans remembered profiles PowerShell no longer reports',
      () async {
        final profile = inHome('profile.ps1');
        File(profile).writeAsStringSync('${powerShellBlock}Set-Alias x y\n');
        final s = setup(windows: true, powerShell: FakePowerShellProbe([]));
        final result = await s.disable(knownFiles: [profile]);
        expect(result.complete, isTrue);
        expect(File(profile).readAsStringSync(), 'Set-Alias x y\n');
        final cleaned = await s.cleanup(knownFiles: [profile]);
        expect(cleaned.complete, isTrue);
      },
    );

    test(
      'a block that could not be removed is reported, so complete is false',
      () async {
        File(inHome('.zshrc')).writeAsStringSync('${zshBlock}x\n');
        await Process.run('/bin/chmod', ['444', inHome('.zshrc')]);
        final result = await setup().disable();
        expect(result.complete, isFalse);
        expect(result.failedFiles, [inHome('.zshrc')]);
      },
      skip: Platform.isWindows ? 'POSIX modes' : false,
    );
  });
}
