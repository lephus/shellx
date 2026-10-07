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
  }) async {
    final problems = <ConfigProblem>[];
    final chain = await loadConfigChain(
      path,
      fs: fs,
      home: '/home/me',
      problems: problems,
      quiet: quiet,
      keep: keep,
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
}
