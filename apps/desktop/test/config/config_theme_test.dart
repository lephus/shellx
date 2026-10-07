import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_color.dart';
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_paths.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/config_theme.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';

import '../support/memory_config_fs.dart';

final paths = configPathsFor(windows: false, env: const {}, home: '/home/me');
const dracula = '''
palette = 0=#21222c
palette = 1=#ff5555
background = #282a36
foreground = #f8f8f2
cursor-color = #f8f8f2
selection-background = #44475a
window-padding-x = 99
''';

ShellxConfig configOf(String text) => buildShellxConfig(
  ghostty: const [],
  shellx: parseConfigText(text, file: paths.shellx, problems: []),
  problems: [],
  macos: true,
  home: '/home/me',
);

void main() {
  late MemoryConfigFs fs;
  setUp(() => fs = MemoryConfigFs());

  Future<(ResolvedTheme, List<String>, List<ConfigProblem>)> resolve(
    String text,
  ) async {
    final problems = <ConfigProblem>[];
    final r = await resolveTheme(
      configOf(text),
      paths,
      fs: fs,
      problems: problems,
    );
    return (r.theme, r.files, problems);
  }

  test('no theme: A1 colours exactly', () async {
    final (theme, files, problems) = await resolve('');
    expect(problems, isEmpty);
    expect(files, isEmpty);
    expect(theme.terminal.background, TerminalColors.theme.background);
    expect(theme.terminal.red, TerminalColors.theme.red);
    expect(theme.terminal.selection, TerminalColors.theme.selection);
    expect(theme.terminal.cursor, TerminalColors.theme.cursor);
    expect(theme.background, TerminalColors.background);
    expect(theme.focusOutline, ShellxDesktopColors.accent);
  });

  test('search order: ShellX themes, then Ghostty themes (D13)', () async {
    fs
      ..write('/home/me/.config/ghostty/themes/Dracula', dracula)
      ..write(
        '/Applications/Ghostty.app/Contents/Resources/ghostty/themes/Dracula',
        'background = #000000\n',
      );
    var (theme, files, problems) = await resolve('theme = Dracula');
    expect(problems, isEmpty);
    expect(theme.background, const Color(0xFF282A36));
    expect(theme.terminal.black, const Color(0xFF21222C));
    expect(theme.terminal.red, const Color(0xFFFF5555));
    expect(
      theme.terminal.green,
      TerminalColors.theme.green,
    ); // not in the theme
    expect(theme.name, 'Dracula');
    expect(files, contains('/home/me/.config/ghostty/themes/Dracula'));
    expect(files, contains('/home/me/.config/shellx/themes/Dracula'));

    fs.write(
      '/home/me/.config/shellx/themes/Dracula',
      'background = #111111\n',
    );
    (theme, files, problems) = await resolve('theme = Dracula');
    expect(theme.background, const Color(0xFF111111));
  });

  test('explicit colours beat the theme; selection is drawn at 40 %', () async {
    fs.write('/t/dracula', dracula);
    final (theme, _, _) = await resolve(
      'theme = /t/dracula\nbackground = #000000\npalette = 1=#00ff00\n',
    );
    expect(theme.background, const Color(0xFF000000));
    expect(theme.terminal.red, const Color(0xFF00FF00));
    expect(theme.terminal.selection, const Color(0x6644475A));
    expect(theme.terminal.searchHitBackground, theme.terminal.yellow);
    expect(theme.terminal.searchHitForeground, theme.background);
  });

  test('light:/dark: picks dark; "ShellX" is the built-in palette', () async {
    expect(themeNameFor('light:Solarized Light,dark:Dracula'), 'Dracula');
    expect(themeNameFor('dark:A,light:B'), 'A');
    expect(themeNameFor('light:Only'), 'Only');
    expect(themeNameFor('Plain'), 'Plain');
    final (theme, files, problems) = await resolve('theme = ShellX');
    expect(problems, isEmpty);
    expect(files, isEmpty);
    expect(theme.background, TerminalColors.background);
  });

  test(
    'not found: a warning at the theme line, default colours kept',
    () async {
      final (theme, _, problems) = await resolve(
        '\ntheme = Nope\nforeground = #ffffff\n',
      );
      expect(theme.background, TerminalColors.background);
      expect(theme.terminal.foreground, const Color(0xFFFFFFFF));
      expect(
        (problems.single.code, problems.single.line, problems.single.value),
        (ConfigProblemCode.themeNotFound, 2, 'Nope'),
      );
    },
  );

  test('a theme file that is not UTF-8 counts as not found', () async {
    fs.writeBytes('/t/bin', [0xC3, 0x28]);
    final (_, _, problems) = await resolve('theme = /t/bin');
    expect(problems.single.code, ConfigProblemCode.themeNotFound);
  });

  test('a light background moves the focus outline off accent (D15)', () async {
    final (light, _, problems) = await resolve(
      'background = #fdf6e3\nforeground = #657b83\n',
    );
    expect(light.focusOutline, isNot(ShellxDesktopColors.accent));
    expect(
      focusOutlineFor(const Color(0xFFFDF6E3)),
      ShellxDesktopColors.bgTerminal,
    );
    // Solarized light text is 4.1:1 — a warning, still applied.
    expect(problems.single.code, ConfigProblemCode.lowContrast);
    expect(problems.single.severity, ConfigSeverity.warning);
    expect(problems.single.detail, '4.1');
  });

  test('default (no theme) equals the A1 theme in every field', () async {
    final (theme, _, _) = await resolve('');
    final a = theme.terminal;
    final d = TerminalColors.theme;
    expect(
      [
        a.cursor,
        a.selection,
        a.foreground,
        a.background,
        a.black,
        a.red,
        a.green,
        a.yellow,
        a.blue,
        a.magenta,
        a.cyan,
        a.white,
        a.brightBlack,
        a.brightRed,
        a.brightGreen,
        a.brightYellow,
        a.brightBlue,
        a.brightMagenta,
        a.brightCyan,
        a.brightWhite,
        a.searchHitBackground,
        a.searchHitBackgroundCurrent,
        a.searchHitForeground,
      ],
      [
        d.cursor,
        d.selection,
        d.foreground,
        d.background,
        d.black,
        d.red,
        d.green,
        d.yellow,
        d.blue,
        d.magenta,
        d.cyan,
        d.white,
        d.brightBlack,
        d.brightRed,
        d.brightGreen,
        d.brightYellow,
        d.brightBlue,
        d.brightMagenta,
        d.brightCyan,
        d.brightWhite,
        d.searchHitBackground,
        d.searchHitBackgroundCurrent,
        d.searchHitForeground,
      ],
    );
    expect(theme.focusOutline, ResolvedTheme.defaults.focusOutline);
  });

  test('a theme name never escapes its directory', () async {
    fs
      ..write('/home/me/.config/shellx/other', dracula)
      ..write('/home/me/.config/shellx/themes/../other', dracula);
    for (final name in ['../other', 'a/b', r'a\b', '..', 'x\x00y']) {
      final (theme, files, problems) = await resolve('theme = $name');
      expect(files, isEmpty, reason: name);
      expect(problems.single.code, ConfigProblemCode.themeNotFound);
      expect(theme.background, TerminalColors.background);
    }
    expect(fs.reads, 0);
  });

  test('~/ and absolute paths are allowed; a relative path is not', () async {
    fs.write('/home/me/my-theme', dracula);
    var (theme, files, _) = await resolve('theme = ~/my-theme');
    expect(files, ['/home/me/my-theme']);
    expect(theme.background, const Color(0xFF282A36));
    (theme, files, _) = await resolve('theme = ./my-theme');
    expect(files, isEmpty);
  });

  test('a theme file over 256 KiB or unreadable counts as not found', () async {
    fs.writeBytes('/t/big', List.filled(kConfigMaxBytes + 1, 0x23));
    fs.write('/t/locked', dracula);
    fs.unreadable.add('/t/locked');
    for (final path in ['/t/big', '/t/locked']) {
      final (_, _, problems) = await resolve('theme = $path');
      expect(problems.single.code, ConfigProblemCode.themeNotFound);
    }
  });

  test('light: only is used, with a note', () async {
    fs.write('/home/me/.config/shellx/themes/Day', dracula);
    final (theme, _, problems) = await resolve('theme = light:Day');
    expect(theme.background, const Color(0xFF282A36));
    expect(problems.single.code, ConfigProblemCode.unsupportedValue);
    expect(problems.single.severity, ConfigSeverity.info);
  });

  test('focus outline keeps 3:1 against every background', () {
    for (final c in const [
      Color(0xFF000000),
      Color(0xFFFFFFFF),
      Color(0xFF808080),
      Color(0xFF5FD4E2),
      Color(0xFF7FA0A8),
      Color(0xFFB0B0B0),
    ]) {
      expect(contrastRatio(focusOutlineFor(c), c), greaterThanOrEqualTo(3));
    }
  });

  test(
    'a bare name may contain ".." inside it; only ".." itself is refused',
    () async {
      fs.write('/home/me/.config/shellx/themes/x..y', dracula);
      final (theme, files, problems) = await resolve('theme = x..y');
      expect(problems, isEmpty);
      expect(files, ['/home/me/.config/shellx/themes/x..y']);
      expect(theme.background, const Color(0xFF282A36));
    },
  );

  test('the contrast ratio is shown truncated, never rounded up', () async {
    // #747474 on black is 4.49:1: rounding would print a passing "4.5".
    final (_, _, problems) = await resolve(
      'background = #000000\nforeground = #747474\n',
    );
    expect(problems.single.code, ConfigProblemCode.lowContrast);
    expect(problems.single.detail, '4.4');
  });

  test('an empty side of a light:/dark: pair is absent', () async {
    expect(themeNameFor('light:A,dark:'), 'A');
    expect(themeNameFor('light:,dark:B'), 'B');
    fs.write('/home/me/.config/shellx/themes/Day', dracula);
    final (theme, _, problems) = await resolve('theme = light:Day,dark:');
    expect(theme.name, 'Day');
    expect(theme.background, const Color(0xFF282A36));
    // Only the light side is set: the same note as `light:Day`.
    expect(
      (problems.single.code, problems.single.severity),
      (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
    );
  });

  test('light:/dark: selects the dark theme end to end', () async {
    fs
      ..write('/home/me/.config/shellx/themes/Day', 'background = #ffffff\n')
      ..write('/home/me/.config/shellx/themes/Night', dracula);
    final (theme, files, problems) = await resolve(
      'theme = light:Day,dark:Night',
    );
    expect(problems, isEmpty);
    expect(theme.name, 'Night');
    expect(theme.background, const Color(0xFF282A36));
    expect(files, ['/home/me/.config/shellx/themes/Night']);
  });

  test('the contrast warning points at the line that set the colour', () async {
    fs.write('/t/pale', 'background = #000000\nforeground = #333333\n');
    var (_, _, problems) = await resolve(
      'theme = /t/pale\n\nforeground = #444444\n',
    );
    expect(
      (problems.single.code, problems.single.line),
      (ConfigProblemCode.lowContrast, 3),
    );
    (_, _, problems) = await resolve('theme = /t/pale\nbackground = #000000\n');
    expect(problems.single.line, 2);
    (_, _, problems) = await resolve('\n\ntheme = /t/pale\n');
    expect(problems.single.line, 3);
  });

  group('Windows theme paths', () {
    final win = configPathsFor(
      windows: true,
      env: const {},
      home: r'C:\Users\me',
    );

    Future<(ResolvedTheme, List<String>)> resolveWin(String name) async {
      final r = await resolveTheme(
        buildShellxConfig(
          ghostty: const [],
          shellx: parseConfigText(
            'theme = $name',
            file: win.shellx,
            problems: [],
          ),
          problems: [],
          macos: false,
          home: r'C:\Users\me',
        ),
        win,
        fs: fs,
        problems: [],
      );
      return (r.theme, r.files);
    }

    test(r'~\, a drive path and a bare name are looked up', () async {
      fs
        ..write(r'C:\Users\me\t\Night', dracula)
        ..write(r'D:\themes\Night', dracula)
        ..write(r'C:\Users\me\AppData\Roaming\ShellX\themes\Night', dracula);
      var (theme, files) = await resolveWin(r'~\t\Night');
      expect(files, [r'C:\Users\me\t\Night']);
      expect(theme.background, const Color(0xFF282A36));
      (theme, files) = await resolveWin(r'D:\themes\Night');
      expect(files, [r'D:\themes\Night']);
      expect(theme.name, r'D:\themes\Night');
      (theme, files) = await resolveWin('Night');
      expect(files.first, r'C:\Users\me\AppData\Roaming\ShellX\themes\Night');
      expect(theme.name, 'Night');
    });

    test('a device path and a colon in a bare name are refused', () async {
      fs.write(r'\\.\C:\x', dracula);
      for (final name in [r'\\.\C:\x', r'\\?\C:\x', 'a:b', r'\x', 'C:x']) {
        final (theme, files) = await resolveWin(name);
        expect(files, isEmpty, reason: name);
        expect(theme.background, TerminalColors.background, reason: name);
      }
      expect(fs.reads, 0);
    });
  });
}
