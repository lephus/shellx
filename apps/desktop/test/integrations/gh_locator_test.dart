import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/gh_locator.dart';

void main() {
  late Set<String> present;
  late List<String> probed;
  late DateTime clock;

  GhLocator make({
    String path = '/usr/bin:/bin',
    bool windows = false,
    String? programFiles,
  }) => GhLocator(
    path: path,
    home: windows ? r'C:\Users\me' : '/Users/me',
    windows: windows,
    programFiles: programFiles,
    isExecutable: (p) async {
      probed.add(p);
      return present.contains(p);
    },
    now: () => clock,
  );

  setUp(() {
    present = {};
    probed = [];
    clock = DateTime.utc(2026, 10, 8);
  });

  test('finds gh on PATH', () async {
    present = {'/opt/tools/gh'};
    expect(await make(path: '/usr/bin:/opt/tools').find(), '/opt/tools/gh');
  });

  test('finds gh in each listed folder', () async {
    for (final dir in [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/Users/me/.local/bin',
    ]) {
      present = {'$dir/gh'};
      expect(await make().find(), '$dir/gh', reason: dir);
    }
  });

  test('looks nowhere else', () async {
    present = {'/tmp/gh', '/Users/me/gh', '/Users/me/bin/gh', './gh'};
    expect(await make().find(), isNull);
    for (final p in probed) {
      expect([
        '/usr/bin/gh',
        '/bin/gh',
        '/opt/homebrew/bin/gh',
        '/usr/local/bin/gh',
        '/Users/me/.local/bin/gh',
      ], contains(p));
    }
  });

  test('a relative or empty PATH entry is never searched', () async {
    present = {'gh', './gh', 'bin/gh', '/gh'};
    expect(await make(path: ':.:bin::./').find(), isNull);
    expect(probed.where((p) => !p.startsWith('/')), isEmpty);
  });

  test('PATH comes first', () async {
    present = {'/opt/homebrew/bin/gh', '/a/gh'};
    expect(await make(path: '/a').find(), '/a/gh');
  });

  test('the answer, found or not, is kept for 5 minutes', () async {
    final l = make();
    expect(await l.find(), isNull);
    final n = probed.length;
    present = {'/usr/local/bin/gh'};
    clock = clock.add(const Duration(minutes: 4, seconds: 59));
    expect(await l.find(), isNull);
    expect(probed.length, n); // not probed again
    clock = clock.add(const Duration(seconds: 2));
    expect(await l.find(), '/usr/local/bin/gh');
    present = {};
    expect(await l.find(), '/usr/local/bin/gh'); // cached again
  });

  test('Windows: gh.exe on PATH and in Program Files', () async {
    present = {r'C:\Program Files\GitHub CLI\gh.exe'};
    expect(
      await make(
        path: r'C:\Windows;C:\bin',
        windows: true,
        programFiles: r'C:\Program Files',
      ).find(),
      r'C:\Program Files\GitHub CLI\gh.exe',
    );
    present = {r'C:\bin\gh.exe'};
    expect(
      await make(
        path: r'C:\Windows;C:\bin',
        windows: true,
        programFiles: r'C:\Program Files',
      ).find(),
      r'C:\bin\gh.exe',
    );
    // Never a .cmd or .bat: they would need a shell.
    present = {r'C:\bin\gh.cmd', r'C:\bin\gh.bat', r'C:\bin\gh'};
    expect(await make(path: r'C:\bin', windows: true).find(), isNull);
  });
}
