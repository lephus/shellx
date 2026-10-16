import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/terminal_sharing/sharing_paths.dart';
import 'package:shellx_desktop/src/terminal_sharing/term_binary.dart';

void main() {
  group('SharingPaths', () {
    test('macOS: bin and term in Application Support, helper in the app', () {
      final paths = SharingPaths.macos(
        home: '/Users/phu',
        executable: '/Applications/ShellX.app/Contents/MacOS/ShellX',
      );
      expect(
        paths.binary,
        '/Users/phu/Library/Application Support/ShellX/bin/shellx-term',
      );
      expect(paths.binDir, '/Users/phu/Library/Application Support/ShellX/bin');
      expect(
        paths.termDir,
        '/Users/phu/Library/Application Support/ShellX/term',
      );
      expect(
        paths.bundledBinary,
        '/Applications/ShellX.app/Contents/Helpers/shellx-term',
      );
    });

    test(
      'Windows: bin and term in LOCALAPPDATA, helper next to ShellX.exe',
      () {
        final paths = SharingPaths.windows(
          localAppData: r'C:\Users\Phú\AppData\Local',
          userProfile: r'C:\Users\Phú',
          executable: r'C:\Users\Phú\AppData\Local\Programs\ShellX\ShellX.exe',
        );
        expect(
          paths.binary,
          r'C:\Users\Phú\AppData\Local\ShellX\bin\shellx-term.exe',
        );
        expect(paths.termDir, r'C:\Users\Phú\AppData\Local\ShellX\term');
        expect(
          paths.bundledBinary,
          r'C:\Users\Phú\AppData\Local\Programs\ShellX\shellx-term.exe',
        );
      },
    );

    test('forPlatform needs the environment variables', () {
      expect(
        SharingPaths.forPlatform(
          windows: false,
          environment: {},
          executable: '/x',
        ),
        isNull,
      );
      expect(
        SharingPaths.forPlatform(
          windows: true,
          environment: {'LOCALAPPDATA': r'C:\L'},
          executable: r'C:\x',
        ),
        isNull,
      );
      expect(
        SharingPaths.forPlatform(
          windows: false,
          environment: {'HOME': '/Users/a'},
          executable: '/A.app/Contents/MacOS/A',
        )!.home,
        '/Users/a',
      );
    });
  });

  group('TermBinaryInstaller', () {
    late Directory dir;
    late List<(String, String)> chmods;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('shellx-bin-');
      chmods = [];
    });
    tearDown(() => dir.deleteSync(recursive: true));

    SharingPaths paths({bool windows = false}) {
      final bin = p.join(dir.path, 'bin');
      return SharingPaths(
        windows: windows,
        home: dir.path,
        binDir: bin,
        binary: p.join(bin, windows ? 'shellx-term.exe' : 'shellx-term'),
        termDir: p.join(dir.path, 'term'),
        bundledBinary: p.join(dir.path, 'app', 'shellx-term'),
      );
    }

    TermBinaryInstaller installer({bool windows = false}) =>
        TermBinaryInstaller(
          paths(windows: windows),
          chmod: (mode, path) async => chmods.add((mode, p.basename(path))),
        );

    void bundle(String content) {
      final file = File(p.join(dir.path, 'app', 'shellx-term'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test(
      'install copies the app\'s binary into bin, mode 755 on macOS',
      () async {
        bundle('v1');
        final i = installer();
        expect(await i.installedExists(), isFalse);
        expect(await i.isCurrent(), isFalse);
        await i.install();
        expect(File(i.paths.binary).readAsStringSync(), 'v1');
        expect(chmods.single.$1, '755');
        expect(await i.isCurrent(), isTrue);
        expect(
          Directory(i.paths.binDir).listSync(),
          hasLength(1),
        ); // No temp file left.
      },
    );

    test(
      'isCurrent compares content: a different build needs an update',
      () async {
        bundle('v1');
        final i = installer();
        await i.install();
        bundle('v2');
        expect(await i.isCurrent(), isFalse);
        await i.install();
        expect(File(i.paths.binary).readAsStringSync(), 'v2');
        expect(await i.isCurrent(), isTrue);
      },
    );

    test('install fails clearly when the app has no binary', () async {
      await expectLater(
        installer().install(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await installer().bundledExists(), isFalse);
    });

    test(
      'Windows: the old binary is renamed to .old-<n> before the copy',
      () async {
        bundle('v1');
        final i = installer(windows: true);
        await i.install();
        bundle('v2');
        await i.install();
        bundle('v3');
        await i.install();
        final names = Directory(
          i.paths.binDir,
        ).listSync().map((e) => p.basename(e.path)).toSet();
        expect(names, {
          'shellx-term.exe',
          'shellx-term.old-1.exe',
          'shellx-term.old-2.exe',
        });
        expect(File(i.paths.binary).readAsStringSync(), 'v3');
        expect(chmods, isEmpty);

        await i.cleanupOld();
        expect(
          Directory(i.paths.binDir).listSync().map((e) => p.basename(e.path)),
          ['shellx-term.exe'],
        );
      },
    );

    test('remove deletes the bin folder', () async {
      bundle('v1');
      final i = installer();
      await i.install();
      expect(await i.remove(), isTrue);
      expect(Directory(i.paths.binDir).existsSync(), isFalse);
      expect(await i.remove(), isTrue);
    });
  });
}
