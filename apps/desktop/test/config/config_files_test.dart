import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';

import '../support/memory_config_fs.dart';

void main() {
  late MemoryConfigFs fs;
  setUp(() => fs = MemoryConfigFs());

  Future<(ConfigChain, List<ConfigProblem>)> load(
    String path, {
    bool quiet = false,
    bool Function(String key)? keep,
    bool windows = false,
    bool? caseInsensitive,
  }) async {
    final problems = <ConfigProblem>[];
    final chain = await loadConfigChain(
      path,
      fs: fs,
      home: '/home/me',
      problems: problems,
      quiet: quiet,
      keep: keep,
      windows: windows,
      caseInsensitive: caseInsensitive,
    );
    return (chain, problems);
  }

  test('a missing root file is readable and empty', () async {
    final (chain, problems) = await load('/c/config');
    expect(chain.readable, isTrue);
    expect(chain.entries, isEmpty);
    expect(chain.files, ['/c/config']);
    expect(problems, isEmpty);
  });

  test('includes are read after the whole file, relative to it (D6)', () async {
    fs
      ..write(
        '/c/config',
        'font-size = 10\nconfig-file = more\nfont-size = 11\n',
      )
      ..write('/c/more', 'font-size = 12\n');
    final (chain, problems) = await load('/c/config');
    expect([for (final e in chain.entries) e.value], ['10', '11', '12']);
    expect(chain.entries.last.file, '/c/more');
    expect(chain.files, ['/c/config', '/c/more']);
    expect(problems, isEmpty);
  });

  test('"~/" expands; "?" makes a missing include silent', () async {
    fs
      ..write('/c/config', 'config-file = ~/x\nconfig-file = ?nope\n')
      ..write('/home/me/x', 'theme = a\n');
    final (chain, problems) = await load('/c/config');
    expect(chain.entries.single.value, 'a');
    expect(chain.files, contains('/c/nope'));
    expect(problems, isEmpty);
  });

  test('a missing include is a warning at its line', () async {
    fs.write('/c/config', '\nconfig-file = gone\n');
    final (_, problems) = await load('/c/config');
    final p = problems.single;
    expect(
      (p.line, p.code, p.severity, p.value),
      (2, ConfigProblemCode.includeMissing, ConfigSeverity.warning, 'gone'),
    );
  });

  test('a loop is reported once and skipped', () async {
    fs
      ..write('/c/a', 'config-file = b\nfont-size = 1\n')
      ..write('/c/b', 'config-file = a\nfont-size = 2\n');
    final (chain, problems) = await load('/c/a');
    expect([for (final e in chain.entries) e.value], ['1', '2']);
    expect(problems.single.code, ConfigProblemCode.includeCycle);
    expect(problems.single.file, '/c/b');
  });

  test('more than 4 levels is includeDepth', () async {
    for (var i = 0; i < 6; i++) {
      fs.write('/c/f$i', 'config-file = f${i + 1}\nfont-size = $i\n');
    }
    final (chain, problems) = await load('/c/f0');
    expect([for (final e in chain.entries) e.value], ['0', '1', '2', '3', '4']);
    expect(problems.single.code, ConfigProblemCode.includeDepth);
    expect(problems.single.file, '/c/f4');
  });

  test(
    'an unreadable, too large or non-UTF-8 root is not readable (D8)',
    () async {
      fs.unreadable.add('/c/config');
      fs.write('/c/config', 'font-size = 1\n');
      var (chain, problems) = await load('/c/config');
      expect(chain.readable, isFalse);
      expect(problems.single.code, ConfigProblemCode.unreadable);
      expect(problems.single.severity, ConfigSeverity.error);

      fs.unreadable.clear();
      fs.write('/c/config', 'a' * (kConfigMaxBytes + 1));
      (chain, problems) = await load('/c/config');
      expect(chain.readable, isFalse);
      expect(problems.single.code, ConfigProblemCode.tooLarge);

      fs.writeBytes('/c/config', [0x61, 0xC3, 0x28]);
      (chain, problems) = await load('/c/config');
      expect(chain.readable, isFalse);
      expect(problems.single.code, ConfigProblemCode.notUtf8);
    },
  );

  test('quiet (Ghostty): syntax and include problems are dropped, '
      'read problems are warnings, keep filters keys', () async {
    fs
      ..write(
        '/g/config',
        'oops\nfont-size = 3\nwindow-padding-x = 9\nconfig-file = nope\n',
      )
      ..unreadable.add('/g/locked');
    final (chain, problems) = await load(
      '/g/config',
      quiet: true,
      keep: (k) => k == 'font-size',
    );
    expect([for (final e in chain.entries) e.key], ['font-size']);
    expect(problems, isEmpty);
    fs.write('/g/locked', 'x = 1');
    final (locked, lockedProblems) = await load('/g/locked', quiet: true);
    expect(locked.readable, isFalse);
    expect(lockedProblems.single.severity, ConfigSeverity.warning);
  });

  test('expandConfigPath on Windows', () {
    expect(
      expandConfigPath(
        r'..\themes\x',
        baseDir: r'C:\Users\me\AppData\Roaming\ShellX',
        home: r'C:\Users\me',
        windows: true,
      ),
      r'C:\Users\me\AppData\Roaming\themes\x',
    );
    expect(
      expandConfigPath(
        r'~\y',
        baseDir: r'C:\a',
        home: r'C:\Users\me',
        windows: true,
      ),
      r'C:\Users\me\y',
    );
  });

  test('IoConfigFs stamps a missing file as missing', () async {
    final stamp = await const IoConfigFs().stamp(
      '/definitely/not/here/shellx-a9',
    );
    expect(stamp.exists, isFalse);
  });

  group('review fixes', () {
    test(
      'an empty config-file resets the includes collected so far (D5)',
      () async {
        fs
          ..write(
            '/c/config',
            'config-file = a\nconfig-file =\nconfig-file = b\nfont-size = 1\n',
          )
          ..write('/c/a', 'font-size = 2\n')
          ..write('/c/b', 'font-size = 3\n');
        final (chain, _) = await load('/c/config');
        expect([for (final e in chain.entries) e.value], ['1', '3']);
        expect(chain.files, ['/c/config', '/c/b']);
      },
    );

    test('a bad include is a warning at the including line; the rest applies '
        '(I3)', () async {
      fs
        ..write(
          '/c/config',
          'font-size = 1\nconfig-file = locked\nconfig-file = big\n'
              'config-file = bin\nconfig-file = ok\n',
        )
        ..write('/c/locked', 'x = 1')
        ..unreadable.add('/c/locked')
        ..write('/c/big', 'a' * (kConfigMaxBytes + 1))
        ..writeBytes('/c/bin', [0x61, 0xC3, 0x28])
        ..write('/c/ok', 'font-size = 9\n');
      final (chain, problems) = await load('/c/config');
      expect(chain.readable, isTrue);
      expect([for (final e in chain.entries) e.value], ['1', '9']);
      expect(
        [for (final p in problems) (p.file, p.line, p.code, p.severity)],
        [
          (
            '/c/config',
            2,
            ConfigProblemCode.unreadable,
            ConfigSeverity.warning,
          ),
          ('/c/config', 3, ConfigProblemCode.tooLarge, ConfigSeverity.warning),
          ('/c/config', 4, ConfigProblemCode.notUtf8, ConfigSeverity.warning),
        ],
      );
    });

    test(
      'a file already loaded is skipped; fan-out is capped at 64 files (I2)',
      () async {
        final dup = StringBuffer();
        for (var i = 0; i < 200; i++) {
          dup.writeln('config-file = x');
        }
        fs
          ..write('/c/config', dup.toString())
          ..write('/c/x', 'font-size = 1\n');
        var (chain, problems) = await load('/c/config');
        expect(chain.entries, hasLength(1));
        expect(chain.files, ['/c/config', '/c/x']);
        expect(problems, isEmpty);

        final many = StringBuffer();
        for (var i = 0; i < 100; i++) {
          many.writeln('config-file = f$i');
          fs.write('/c/f$i', 'font-size = $i\n');
        }
        fs.write('/c/config', many.toString());
        (chain, problems) = await load('/c/config');
        expect(chain.files, hasLength(kConfigMaxFiles));
        expect(chain.files.toSet(), hasLength(kConfigMaxFiles));
        expect(problems.single.code, ConfigProblemCode.includeLimit);
      },
    );

    test(
      'paths are compared normalised, case-insensitively on Windows/macOS',
      () async {
        fs
          ..write('/c/config', 'config-file = a\nconfig-file = ./sub/../a\n')
          ..write('/c/a', 'font-size = 1\n');
        var (chain, problems) = await load('/c/config');
        expect(chain.entries, hasLength(1));
        expect(chain.files, ['/c/config', '/c/a']);
        expect(problems, isEmpty);

        fs.write('/c/config', 'config-file = A\n');
        fs.write('/c/A', 'font-size = 1\nconfig-file = CONFIG\n');
        (chain, problems) = await load('/c/config', caseInsensitive: true);
        expect(problems.single.code, ConfigProblemCode.includeCycle);
      },
    );

    test('Windows: both separators and letter case are one path', () async {
      fs
        ..write(r'C:\c\config', 'config-file = a\\x\nconfig-file = A/X\n')
        ..write(r'C:\c\a\x', 'font-size = 1\n');
      final (chain, problems) = await load(r'C:\c\config', windows: true);
      expect(chain.entries, hasLength(1));
      expect(problems, isEmpty);
    });

    test('UTF-16 root and a CRLF+BOM include load', () async {
      fs
        ..writeBytes('/c/config', [
          0xFF,
          0xFE,
          for (final u in 'config-file = inc\nfont-size = 1\n'.codeUnits) ...[
            u,
            0,
          ],
        ])
        ..writeBytes('/c/inc', [
          0xEF,
          0xBB,
          0xBF,
          ...'font-size = 2\r\ntheme = t\r\n'.codeUnits,
        ]);
      final (chain, problems) = await load('/c/config');
      expect([for (final e in chain.entries) e.value], ['1', '2', 't']);
      expect(problems, isEmpty);
    });

    test('NUL in an include path is a warning, not a crash; NUL in a value '
        'parses', () async {
      fs.write('/c/config', 'config-file = a\x00b\ntheme = x\x00y\n');
      final (chain, problems) = await load('/c/config');
      expect(chain.entries.single.value, 'x\x00y');
      expect(problems.single.code, ConfigProblemCode.unreadable);
      expect(problems.single.severity, ConfigSeverity.warning);
    });

    test('an optional include with ~ is silent', () async {
      fs.write('/c/config', 'config-file = ?~/missing\n');
      final (chain, problems) = await load('/c/config');
      expect(problems, isEmpty);
      expect(chain.files, contains('/home/me/missing'));
    });

    test('a 10k-line file and one huge line are fine', () async {
      final b = StringBuffer();
      for (var i = 0; i < 10000; i++) {
        b.writeln('font-size = $i');
      }
      fs.write('/c/config', b.toString());
      var (chain, _) = await load('/c/config');
      expect(chain.entries, hasLength(10000));
      fs.write('/c/config', 'theme = ${'x' * 200000}\n');
      (chain, _) = await load('/c/config');
      expect(chain.entries.single.value, hasLength(200000));
    });

    test('problems are capped at 100 plus one summary', () async {
      final b = StringBuffer();
      for (var i = 0; i < 500; i++) {
        b.writeln('no equals here $i');
      }
      fs.write('/c/config', b.toString());
      final (_, problems) = await load('/c/config');
      expect(problems, hasLength(kConfigMaxProblems + 1));
      expect(problems.last.code, ConfigProblemCode.problemLimit);
      expect(problems.last.detail, '500');
    });

    test('expandConfigPath rejects an empty home for ~', () {
      expect(
        () => expandConfigPath('~/x', baseDir: '/c', home: ''),
        throwsArgumentError,
      );
      expect(expandConfigPath('y', baseDir: '/c', home: ''), '/c/y');
    });
  });

  group('IoConfigFs.read (I1)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('shellx-a9-'));
    tearDown(() => dir.deleteSync(recursive: true));
    const io = IoConfigFs();

    test(
      'missing is null; a regular file and a symlink to one are read',
      () async {
        expect(await io.read('${dir.path}/none'), isNull);
        File('${dir.path}/f').writeAsStringSync('a = 1');
        Link('${dir.path}/l').createSync('${dir.path}/f');
        expect(await io.read('${dir.path}/f'), isNotNull);
        expect(await io.read('${dir.path}/l'), isNotNull);
      },
      skip: Platform.isWindows,
    );

    test('a directory is unreadable, not missing', () async {
      await expectLater(io.read(dir.path), throwsA(isA<FileSystemException>()));
    });

    test('a file over the cap throws ConfigTooLarge', () async {
      File(
        '${dir.path}/big',
      ).writeAsBytesSync(List.filled(kConfigMaxBytes + 1, 0x61));
      await expectLater(
        io.read('${dir.path}/big'),
        throwsA(isA<ConfigTooLarge>()),
      );
      File(
        '${dir.path}/ok',
      ).writeAsBytesSync(List.filled(kConfigMaxBytes, 0x61));
      expect((await io.read('${dir.path}/ok'))!.length, kConfigMaxBytes);
    });

    test('a FIFO does not block', () async {
      final r = await Process.run('mkfifo', ['${dir.path}/fifo']);
      expect(r.exitCode, 0);
      await expectLater(
        io.read('${dir.path}/fifo').timeout(const Duration(seconds: 5)),
        throwsA(isA<FileSystemException>()),
      );
    }, skip: Platform.isWindows);

    test('/dev/zero does not hang', () async {
      await expectLater(
        io.read('/dev/zero').timeout(const Duration(seconds: 5)),
        throwsA(anyOf(isA<ConfigTooLarge>(), isA<FileSystemException>())),
      );
    }, skip: !File('/dev/zero').existsSync());

    test(r'\\.\ and \\?\ device paths and NUL are rejected up front', () async {
      for (final bad in [r'\\.\COM1', r'\\?\C:\x', 'a\x00b']) {
        await expectLater(
          io.read(bad),
          throwsA(isA<FileSystemException>()),
          reason: bad,
        );
      }
    });
  });
}
