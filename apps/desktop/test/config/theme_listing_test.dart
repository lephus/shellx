import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';
import 'package:shellx_desktop/src/config/theme_listing.dart';

/// Folders by path; [failing] folders throw like a denied read.
final class FakeConfigFs implements ConfigFs {
  FakeConfigFs({required this.dirs, this.failing = const {}});
  final Map<String, List<String>> dirs;
  final Set<String> failing;

  @override
  Future<List<String>> list(String dir) async {
    if (failing.contains(dir)) throw FileSystemException('denied', dir);
    return dirs[dir] ?? const [];
  }

  @override
  Future<Uint8List?> read(String path) async => null;

  @override
  Future<FileStamp> stamp(String path) async => const FileStamp.missing();
}

ConfigPaths fakePaths({required List<String> themeDirs}) => ConfigPaths(
  shellx: '/c/shellx',
  ghostty: const [],
  themeDirs: themeDirs,
  home: '/home/me',
  windows: false,
);

void main() {
  test('lists the files of every theme directory, ShellX first, no dotfiles '
      'or duplicates', () async {
    final fs = FakeConfigFs(
      dirs: {
        '/c/themes': ['Dracula', '.DS_Store', 'Nord'],
        '/g/themes': ['dracula', 'Solarized', 'Nord'],
      },
    );
    final paths = fakePaths(themeDirs: ['/c/themes', '/g/themes']);
    final list = await listThemes(paths, fs);
    expect(list.map((e) => e.name).toList(), [
      'ShellX',
      'Dracula',
      'dracula',
      'Nord',
      'Solarized',
    ]);
    // The first directory wins on an exact duplicate.
    expect(list.firstWhere((e) => e.name == 'Nord').source, '/c/themes');
  });

  test('a missing or unreadable directory is skipped, never thrown', () async {
    final fs = FakeConfigFs(dirs: {}, failing: {'/c/themes'});
    expect(
      await listThemes(fakePaths(themeDirs: ['/c/themes']), fs),
      hasLength(1),
    );
    expect(
      await listThemes(fakePaths(themeDirs: ['/c/themes', '/nope']), fs),
      hasLength(1),
    );
  });

  test('names with separators or NUL are dropped (a theme never leaves its '
      'directory)', () async {
    final fs = FakeConfigFs(
      dirs: {
        '/c/themes': ['ok', 'a/b', 'x\x00y', '..', r'c\d', '.', ''],
      },
    );
    final names = (await listThemes(
      fakePaths(themeDirs: ['/c/themes']),
      fs,
    )).map((e) => e.name);
    expect(names, ['ShellX', 'ok']);
  });

  test(
    'a theme file named like the built-in palette is not listed twice',
    () async {
      final fs = FakeConfigFs(
        dirs: {
          '/c/themes': ['shellx', 'Zed'],
        },
      );
      final names = (await listThemes(
        fakePaths(themeDirs: ['/c/themes']),
        fs,
      )).map((e) => e.name);
      expect(names, ['ShellX', 'Zed']);
    },
  );

  test('sorted without regard to case, at most 600 themes', () async {
    final fs = FakeConfigFs(
      dirs: {
        '/c/themes': ['b', 'A', 'c', for (var i = 0; i < 900; i++) 'theme-$i'],
      },
    );
    final list = await listThemes(fakePaths(themeDirs: ['/c/themes']), fs);
    expect(list, hasLength(601)); // 600 and the built-in one
    expect(list.take(3).map((e) => e.name), ['ShellX', 'A', 'b']);
  });

  test('the real file system: files and links to files, no folders', () async {
    final dir = Directory.systemTemp.createTempSync('shellx-themes-');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/Nord').writeAsStringSync('background = #000000\n');
    Directory('${dir.path}/sub').createSync();
    if (!Platform.isWindows) {
      Link('${dir.path}/Alias').createSync('${dir.path}/Nord');
      Link('${dir.path}/DirAlias').createSync('${dir.path}/sub');
    }
    final names = await const IoConfigFs().list(dir.path);
    expect(names..sort(), Platform.isWindows ? ['Nord'] : ['Alias', 'Nord']);
    expect(await const IoConfigFs().list('${dir.path}/missing'), isEmpty);
  });
}
