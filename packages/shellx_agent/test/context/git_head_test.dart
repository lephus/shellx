import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

/// In-memory [GitFiles]: counts `entry` calls; [gate] holds every `entry`.
final class _Files implements GitFiles {
  _Files(this.entries, this.contents);
  final Map<String, GitEntry> entries;
  final Map<String, String> contents;
  int entryCalls = 0;
  Completer<void>? gate;

  @override
  Future<GitEntry> entry(String path) async {
    entryCalls++;
    final answer = entries[path] ?? GitEntry.none; // taken before the gate
    await gate?.future;
    return answer;
  }

  @override
  Future<String> readSmall(String path, int limit) async {
    final content = contents[path];
    if (content == null) throw FileSystemException('missing', path);
    return content;
  }
}

void main() {
  test('parseGitHead: branch, other refs, detached SHA-1/SHA-256, junk', () {
    expect(parseGitHead('ref: refs/heads/main\n'), 'main');
    expect(parseGitHead('ref: refs/heads/feat/a2'), 'feat/a2');
    expect(parseGitHead('ref: refs/remotes/origin/x'), 'remotes/origin/x');
    expect(parseGitHead('${'a1b2c3d4' * 5}\n'), 'a1b2c3d');
    expect(parseGitHead('b' * 64), 'bbbbbbb');
    expect(parseGitHead('hello'), isNull);
    expect(parseGitHead('ref: refs/heads/${'x' * 300}')!.length, 200);
  });

  group('on disk', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('shellx-git-'));
    tearDown(() => temp.deleteSync(recursive: true));

    String repo(String name, String head) {
      final git = Directory('${temp.path}/$name/.git')
        ..createSync(recursive: true);
      File('${git.path}/HEAD').writeAsStringSync(head);
      return '${temp.path}/$name';
    }

    test('a repo and a deep subdirectory give its branch; HEAD is re-read '
        'on every lookup', () async {
      final root = repo('app', 'ref: refs/heads/main\n');
      final deep = Directory('$root/a/b/c')..createSync(recursive: true);
      final reader = GitHeadReader();
      expect(await reader.branchFor(root), 'main');
      expect(await reader.branchFor(deep.path), 'main');
      File('$root/.git/HEAD').writeAsStringSync('ref: refs/heads/dev\n');
      expect(await reader.branchFor(deep.path), 'dev');
    });

    test('detached HEAD gives the short SHA', () async {
      final root = repo('det', '0123456789abcdef0123456789abcdef01234567\n');
      expect(await GitHeadReader().branchFor(root), '0123456');
    });

    test('a worktree follows an absolute gitdir: file', () async {
      final root = repo('main', 'ref: refs/heads/main\n');
      final wtGit = Directory('$root/.git/worktrees/wt')
        ..createSync(recursive: true);
      File('${wtGit.path}/HEAD').writeAsStringSync('ref: refs/heads/feature\n');
      final wt = Directory('${temp.path}/wt')..createSync();
      File('${wt.path}/.git').writeAsStringSync('gitdir: ${wtGit.path}\n');
      expect(await GitHeadReader().branchFor(wt.path), 'feature');
    });

    test('a submodule follows a relative gitdir: file', () async {
      final root = repo('super', 'ref: refs/heads/main\n');
      final modGit = Directory('$root/.git/modules/lib')
        ..createSync(recursive: true);
      File('${modGit.path}/HEAD').writeAsStringSync('ref: refs/heads/pin\n');
      final src = Directory('$root/lib/src')..createSync(recursive: true);
      File('$root/lib/.git').writeAsStringSync('gitdir: ../.git/modules/lib\n');
      expect(await GitHeadReader().branchFor(src.path), 'pin');
    });

    test('an unreadable HEAD gives null and never throws', () async {
      final root = repo('locked', 'ref: refs/heads/main\n');
      final head = '$root/.git/HEAD';
      Process.runSync('chmod', ['000', head]);
      addTearDown(() => Process.runSync('chmod', ['644', head]));
      expect(await GitHeadReader().branchFor(root), isNull);
    }, testOn: 'mac-os || linux');
  });

  test(
    'not a repo: walks to the root once, then answers from the cache',
    () async {
      final files = _Files({}, {});
      final reader = GitHeadReader(files: files, windows: false);
      expect(await reader.branchFor('/a/b'), isNull);
      expect(files.entryCalls, 3); // /a/b/.git, /a/.git, /.git
      expect(await reader.branchFor('/a/b'), isNull);
      expect(files.entryCalls, 3);
      expect(await reader.branchFor('/a/b', refresh: true), isNull);
      expect(files.entryCalls, 6);
    },
  );

  test('concurrent lookups of one directory share one walk', () async {
    final files = _Files(
      {'/r/.git': GitEntry.directory},
      {'/r/.git/HEAD': 'ref: refs/heads/main'},
    )..gate = Completer<void>();
    final reader = GitHeadReader(files: files, windows: false);
    final first = reader.branchFor('/r/src');
    final second = reader.branchFor('/r/src');
    files.gate!.complete();
    expect(await Future.wait([first, second]), ['main', 'main']);
    expect(files.entryCalls, 2); // /r/src/.git, /r/.git
  });

  test('Windows paths: backslashes, drive root ends the walk', () async {
    final files = _Files(
      {r'C:\r\.git': GitEntry.directory},
      {r'C:\r\.git\HEAD': 'ref: refs/heads/win'},
    );
    final reader = GitHeadReader(files: files, windows: true);
    expect(await reader.branchFor(r'C:\r\src'), 'win');
    expect(await reader.branchFor(r'D:\x'), isNull);
    expect(files.entryCalls, 4); // C:\r\src, C:\r; D:\x, D:\ (root ends it)
  });

  test('a lookup slower than 500 ms gives null', () {
    fakeAsync((async) {
      final files = _Files({}, {})..gate = Completer<void>();
      final reader = GitHeadReader(files: files, windows: false);
      String? result = 'pending';
      reader.branchFor('/slow/mount').then((b) => result = b);
      async.elapse(const Duration(milliseconds: 499));
      expect(result, 'pending');
      async.elapse(const Duration(milliseconds: 2));
      expect(result, isNull);
    });
  });

  test('a refresh during a slow walk keeps the newer answer cached', () async {
    final files = _Files(
      {'/r/.git': GitEntry.directory},
      {'/r/.git/HEAD': 'ref: refs/heads/main'},
    )..gate = Completer<void>();
    final reader = GitHeadReader(
      files: files,
      windows: false,
      timeout: const Duration(seconds: 5),
    );
    final old = reader.branchFor('/r');
    final oldGate = files.gate!;
    files.gate = null;
    files.entries['/r/.git'] = GitEntry.none; // the repo vanishes
    expect(await reader.branchFor('/r', refresh: true), isNull);
    oldGate.complete(); // the stale walk saw the repo
    expect(await old, 'main');
    await Future<void>.delayed(Duration.zero);
    final calls = files.entryCalls;
    expect(await reader.branchFor('/r'), isNull); // newer answer still cached
    expect(files.entryCalls, calls);
  });

  test('a hung walk is shared: five lookups over time, one walk', () {
    fakeAsync((async) {
      final files = _Files({}, {})..gate = Completer<void>();
      final reader = GitHeadReader(files: files, windows: false);
      final results = <String?>[];
      for (var i = 0; i < 5; i++) {
        reader.branchFor('/hung').then(results.add);
        async.elapse(const Duration(milliseconds: 600));
      }
      expect(results, everyElement(isNull));
      expect(results, hasLength(5));
      expect(files.entryCalls, 1);
    });
  });

  test('parseGitHead: first line only, control characters stripped, empty '
      'branch is null', () {
    expect(parseGitHead('ref: refs/heads/a\nignored'), 'a');
    expect(parseGitHead('ref: refs/heads/a\x1b[31mb'), 'a[31mb');
    expect(parseGitHead('ref: refs/heads/'), isNull);
    expect(parseGitHead('ref: refs/heads/\n'), isNull);
  });

  test('a gitdir: file pointing nowhere gives null; trailing separators '
      'share a cache key', () async {
    final files = _Files(
      {'/r/.git': GitEntry.file},
      {'/r/.git': 'gitdir: /nowhere'},
    );
    final reader = GitHeadReader(files: files, windows: false);
    expect(await reader.branchFor('/r/'), isNull);
    final calls = files.entryCalls;
    expect(await reader.branchFor('/r'), isNull);
    expect(files.entryCalls, calls);
  });
}
