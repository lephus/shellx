import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/link_resolver.dart';

void main() {
  group('absoluteOf (A10 D7)', () {
    final r = LinkResolver(home: '/Users/me', windows: false);

    test('home, absolute, relative to the pane folder', () {
      expect(r.absoluteOf('~/a.txt'), '/Users/me/a.txt');
      expect(r.absoluteOf('/etc/hosts'), '/etc/hosts');
      expect(
        r.absoluteOf('src/a.dart', cwd: '/work/app'),
        '/work/app/src/a.dart',
      );
      expect(r.absoluteOf('../x.md', cwd: '/work/app'), '/work/x.md');
      expect(r.absoluteOf('./x', cwd: '/work/app'), '/work/app/x');
    });

    test('no folder known: a relative path has no answer', () {
      expect(r.absoluteOf('src/a.dart'), isNull);
      expect(r.absoluteOf('src/a.dart', cwd: 'relative/cwd'), isNull);
    });

    test('control characters and an empty path have no answer', () {
      expect(r.absoluteOf('/tmp/a\nb'), isNull);
      expect(r.absoluteOf('/tmp/a\x00'), isNull);
      expect(r.absoluteOf(''), isNull);
    });

    test('the result is never something `open` could take for an option', () {
      for (final t in ['-rf', '--help', '-a', '../-x']) {
        final a = r.absoluteOf(t, cwd: '/work');
        expect(a == null || a.startsWith('/'), isTrue, reason: t);
      }
    });

    test('no home: ~ has no answer', () {
      expect(
        LinkResolver(home: null, windows: false).absoluteOf('~/a'),
        isNull,
      );
    });

    test('Windows paths', () {
      final w = LinkResolver(home: r'C:\Users\me', windows: true);
      expect(w.absoluteOf(r'C:\a\..\b.txt'), r'C:\b.txt');
      expect(
        w.absoluteOf(r'src\a.dart', cwd: r'C:\work'),
        r'C:\work\src\a.dart',
      );
    });
  });

  group('resolve against the real file system', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('links'));
    tearDown(() => dir.delete(recursive: true));

    test('a file, a folder, a missing one, a link', () async {
      File('${dir.path}/a.txt').writeAsStringSync('x');
      Directory('${dir.path}/sub').createSync();
      Link('${dir.path}/ln').createSync('${dir.path}/a.txt');
      final r = LinkResolver(home: dir.path, windows: false);
      final file = await r.resolve('a.txt', cwd: dir.path);
      expect(file!.isDirectory, isFalse);
      expect((await r.resolve('sub', cwd: dir.path))!.isDirectory, isTrue);
      expect(await r.resolve('nope.txt', cwd: dir.path), isNull);
      expect(await r.resolve('ln', cwd: dir.path), isNotNull);
    }, testOn: '!windows');
  });

  test('answers are remembered for two seconds', () async {
    var asked = 0;
    var now = DateTime(2026, 10, 7, 9);
    final r = LinkResolver(
      home: '/h',
      windows: false,
      now: () => now,
      typeOf: (_) async {
        asked++;
        return FileSystemEntityType.file;
      },
    );
    await r.resolve('/a');
    await r.resolve('/a');
    expect(asked, 1);
    now = now.add(const Duration(seconds: 3));
    await r.resolve('/a');
    expect(asked, 2);
  });

  test('a file system error means not there', () async {
    final r = LinkResolver(
      home: '/h',
      windows: false,
      typeOf: (_) async => throw const FileSystemException('denied'),
    );
    expect(await r.resolve('/a'), isNull);
  });

  test('toString never shows the path', () async {
    final r = LinkResolver(
      home: '/h',
      windows: false,
      typeOf: (_) async => FileSystemEntityType.file,
    );
    expect(
      (await r.resolve('/secret/a'))!.toString(),
      isNot(contains('secret')),
    );
  });

  test('UNC paths have no answer (a stat would reach the network)', () {
    final w = LinkResolver(home: r'C:\Users\me', windows: true);
    expect(w.absoluteOf(r'\\server\share\a.txt'), isNull);
    expect(w.absoluteOf('//server/share/a.txt'), isNull);
    expect(w.absoluteOf(r'\\?\C:\a'), isNull);
  });

  group('a dead mount never hangs (A10 D7)', () {
    test(
      'a stat that never answers is "not there" after the timeout',
      () async {
        var asked = 0;
        final r = LinkResolver(
          home: '/h',
          windows: false,
          statTimeout: const Duration(milliseconds: 40),
          typeOf: (_) {
            asked++;
            return Completer<FileSystemEntityType>().future;
          },
        );
        expect(await r.resolve('/mnt/dead/a'), isNull);
        expect(await r.resolve('/mnt/dead/a'), isNull);
        expect(asked, 1, reason: 'the answer is remembered');
      },
    );

    test('callers of the same path share one stat in flight', () async {
      var asked = 0;
      final done = Completer<FileSystemEntityType>();
      final r = LinkResolver(
        home: '/h',
        windows: false,
        typeOf: (_) {
          asked++;
          return done.future;
        },
      );
      final a = r.resolve('/a');
      final b = r.resolve('/a');
      done.complete(FileSystemEntityType.file);
      expect(await a, isNotNull);
      expect(await b, isNotNull);
      expect(asked, 1);
    });

    test('a hung stat is not asked again while it is in flight', () async {
      var asked = 0;
      var now = DateTime(2026, 10, 7, 9);
      final r = LinkResolver(
        home: '/h',
        windows: false,
        now: () => now,
        statTimeout: const Duration(milliseconds: 20),
        typeOf: (_) {
          asked++;
          return Completer<FileSystemEntityType>().future;
        },
      );
      await r.resolve('/mnt/dead/a');
      now = now.add(const Duration(seconds: 5));
      await r.resolve('/mnt/dead/a');
      expect(asked, 1, reason: 'still waiting for the first');
    });
  });

  test('hover asks the file system at most once per 80 ms', () async {
    var asked = 0;
    var now = DateTime(2026, 10, 7, 9);
    final r = LinkResolver(
      home: '/h',
      windows: false,
      now: () => now,
      typeOf: (_) async {
        asked++;
        return FileSystemEntityType.file;
      },
    );
    expect(await r.resolve('/a', throttle: true), isNotNull);
    expect(await r.resolve('/b', throttle: true), isNull, reason: 'too soon');
    expect(asked, 1);
    expect(
      await r.resolve('/b'),
      isNotNull,
      reason: 'a click is never throttled',
    );
    now = now.add(const Duration(milliseconds: 100));
    expect(await r.resolve('/c', throttle: true), isNotNull);
    expect(asked, 3);
  });
}
