import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';

/// These strings are pinned: `term/src/api/config_path.rs` (Task 13) must
/// print the same for the same environment (spec D39).
void main() {
  test('macOS without XDG', () {
    final paths = configPathsFor(
      windows: false,
      env: const {},
      home: '/Users/me',
    );
    expect(paths.shellx, '/Users/me/.config/shellx/config');
    expect(paths.shellxDir, '/Users/me/.config/shellx');
    expect(paths.ghostty, [
      '/Users/me/.config/ghostty/config.ghostty',
      '/Users/me/.config/ghostty/config',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/config.ghostty',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/config',
    ]);
    expect(paths.themeDirs, [
      '/Users/me/.config/shellx/themes',
      '/Users/me/.config/ghostty/themes',
      '/Users/me/Library/Application Support/com.mitchellh.ghostty/themes',
      '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
    ]);
  });

  test('XDG_CONFIG_HOME wins (absolute only)', () {
    final paths = configPathsFor(
      windows: false,
      env: const {'XDG_CONFIG_HOME': '/x/cfg'},
      home: '/Users/me',
    );
    expect(paths.shellx, '/x/cfg/shellx/config');
    expect(paths.ghostty.first, '/x/cfg/ghostty/config.ghostty');
    final relative = configPathsFor(
      windows: false,
      env: const {'XDG_CONFIG_HOME': 'cfg'},
      home: '/Users/me',
    );
    expect(relative.shellx, '/Users/me/.config/shellx/config');
  });

  test('Windows: %APPDATA%\\ShellX\\config; Ghostty only under XDG', () {
    final paths = configPathsFor(
      windows: true,
      env: const {'APPDATA': r'C:\Users\me\AppData\Roaming'},
      home: r'C:\Users\me',
    );
    expect(paths.shellx, r'C:\Users\me\AppData\Roaming\ShellX\config');
    expect(paths.ghostty, [
      r'C:\Users\me\.config\ghostty\config.ghostty',
      r'C:\Users\me\.config\ghostty\config',
    ]);
    expect(paths.themeDirs, [
      r'C:\Users\me\AppData\Roaming\ShellX\themes',
      r'C:\Users\me\.config\ghostty\themes',
    ]);
    final noAppData = configPathsFor(
      windows: true,
      env: const {},
      home: r'C:\Users\me',
    );
    expect(noAppData.shellx, r'C:\Users\me\AppData\Roaming\ShellX\config');
  });

  group('the shared absolute-path rule (Rust mirrors this table)', () {
    const windowsTable = <String, bool>{
      r'C:\': true,
      r'C:\x': true,
      'C:/x': true,
      r'c:\Users\me': true,
      r'\\server\share': true,
      r'\\server\share\x': true,
      r'\x': false,
      '/x': false,
      'C:x': false,
      'C:': false,
      r'\\.\pipe\x': false,
      r'\\?\C:\x': false,
      r'\\server': false,
      r'\\server\': false,
      r'\\.\share': false,
      r'\\?\share': false,
      '//server/share': false,
      r'~\x': false,
      '~': false,
      r'.\x': false,
      'x': false,
      '': false,
    };
    const posixTable = <String, bool>{
      '/': true,
      '/x': true,
      '/Users/me': true,
      'x': false,
      './x': false,
      '~/x': false,
      '~': false,
      r'C:\x': false,
      '': false,
    };

    test('Windows', () {
      for (final MapEntry(:key, :value) in windowsTable.entries) {
        expect(
          isAbsoluteConfigPath(key, windows: true),
          value,
          reason: 'windows "$key"',
        );
      }
    });

    test('POSIX', () {
      for (final MapEntry(:key, :value) in posixTable.entries) {
        expect(
          isAbsoluteConfigPath(key, windows: false),
          value,
          reason: 'posix "$key"',
        );
      }
    });

    test('Windows XDG_CONFIG_HOME / APPDATA must pass it', () {
      for (final xdg in [r'\cfg', '/cfg', 'C:cfg', r'\\.\cfg', 'cfg']) {
        final paths = configPathsFor(
          windows: true,
          env: {'XDG_CONFIG_HOME': xdg, 'APPDATA': r'\AppData'},
          home: r'C:\Users\me',
        );
        expect(
          paths.shellx,
          r'C:\Users\me\AppData\Roaming\ShellX\config',
          reason: xdg,
        );
        expect(
          paths.ghostty.first,
          r'C:\Users\me\.config\ghostty\config.ghostty',
        );
      }
      final drive = configPathsFor(
        windows: true,
        env: const {'XDG_CONFIG_HOME': 'D:/cfg'},
        home: r'C:\Users\me',
      );
      expect(drive.shellx, r'D:\cfg\shellx\config');
      expect(drive.ghostty.first, r'D:\cfg\ghostty\config.ghostty');
      final unc = configPathsFor(
        windows: true,
        env: const {'APPDATA': r'\\srv\home\me'},
        home: r'C:\Users\me',
      );
      expect(unc.shellx, r'\\srv\home\me\ShellX\config');
    });

    test('an empty or relative home is refused', () {
      for (final (windows, home) in [
        (false, ''),
        (false, 'Users/me'),
        (true, ''),
        (true, r'\Users\me'),
        (true, r'C:Users\me'),
      ]) {
        expect(
          () => configPathsFor(windows: windows, env: const {}, home: home),
          throwsArgumentError,
          reason: home,
        );
      }
    });

    test('expandConfigPath follows it', () {
      for (final bad in [r'\x', '/x', 'C:x', r'\\.\pipe\x', r'\\?\C:\x']) {
        expect(
          () => expandConfigPath(
            bad,
            baseDir: r'C:\c',
            home: r'C:\Users\me',
            windows: true,
          ),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(
        expandConfigPath(
          r'\\srv\share\a\..\b',
          baseDir: r'C:\c',
          home: r'C:\Users\me',
          windows: true,
        ),
        r'\\srv\share\b',
      );
      expect(
        expandConfigPath(
          'D:/x',
          baseDir: r'C:\c',
          home: r'C:\Users\me',
          windows: true,
        ),
        r'D:\x',
      );
      expect(
        () => expandConfigPath(
          r'~\x',
          baseDir: r'C:\c',
          home: r'\Users\me',
          windows: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => expandConfigPath('~/x', baseDir: '/c', home: 'me'),
        throwsArgumentError,
      );
      expect(expandConfigPath('/x/../y', baseDir: '/c', home: '/h'), '/y');
    });
  });
}
