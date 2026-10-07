import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_color.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

const _shellx = '/home/me/.config/shellx/config';
const _ghostty = '/home/me/.config/ghostty/config';

List<ConfigEntry> lines(String text, {String file = _shellx}) =>
    parseConfigText(text, file: file, problems: []);

(ShellxConfig, List<ConfigProblem>) build(
  String shellx, {
  String ghostty = '',
  bool macos = true,
}) {
  final problems = <ConfigProblem>[];
  final config = buildShellxConfig(
    ghostty: lines(ghostty, file: _ghostty),
    shellx: lines(shellx),
    problems: problems,
    macos: macos,
    home: '/home/me',
  );
  return (config, problems);
}

void main() {
  test('font-thicken follows Ghostty: false by default, true or false from '
      'either file, anything else is a bad value', () {
    expect(build('font-thicken = true\n').$1.fontThicken, isTrue);
    expect(build('font-thicken = false\n').$1.fontThicken, isFalse);
    expect(build('', ghostty: 'font-thicken = true\n').$1.fontThicken, isTrue);
    final (c, problems) = build('font-thicken = heavy\n');
    expect(c.fontThicken, isFalse);
    expect(
      [for (final p in problems) (p.code, p.key, p.hint)],
      [(ConfigProblemCode.badValue, 'font-thicken', 'true, false')],
    );
  });

  test('nothing set: today\'s behaviour (criterion 1)', () {
    final (c, problems) = build('');
    expect(problems, isEmpty);
    expect(c.fontFamilies, isEmpty);
    expect(c.fontSize, isNull);
    expect(c.theme, isNull);
    expect(c.palette, isEmpty);
    expect(c.cursorShape, CursorShape.block);
    expect(c.scrollbackLimit, 10000);
    expect(c.padding, const EdgeInsets.fromLTRB(10, 6, 10, 6));
    expect(c.padding, ShellxSizes.terminalPadding);
    expect(c.optionAsAlt, OptionAsAlt.off);
    expect(c.fontThicken, isFalse);
    expect(c.confirmClose, ConfirmClose.whenRunning);
    expect(c.workingDirectory.kind, WorkingDirectoryKind.home);
    expect(c.keybinds, isEmpty);
    expect(c.commands, isEmpty);
    expect(c.ghosttyConfig, isTrue);
  });

  group('values (D7, D11–D21)', () {
    test('valid values', () {
      final (c, problems) = build('''
font-family = Fira Code
font-family = Symbols Nerd Font
font-size = 13.5
theme = Dracula
background = #282a36
foreground = f8f8f2
cursor-color = #fff
selection-background = #44475a
palette = 1=#ff5555
palette = 9 = #ff6e6e
cursor-style = bar
scrollback-limit = 20000
window-padding-x = 4,8
window-padding-y = 2
macos-option-as-alt = left
confirm-close-surface = always
working-directory = ~/work
''');
      expect(problems, isEmpty);
      expect(c.fontFamilies, ['Fira Code', 'Symbols Nerd Font']);
      expect(c.fontSize, 13.5);
      expect(c.theme, 'Dracula');
      expect(c.background, const Color(0xFF282A36));
      expect(c.foreground, const Color(0xFFF8F8F2));
      expect(c.cursorColor, const Color(0xFFFFFFFF));
      expect(c.selectionBackground, const Color(0xFF44475A));
      expect(c.palette, {
        1: const Color(0xFFFF5555),
        9: const Color(0xFFFF6E6E),
      });
      expect(c.cursorShape, CursorShape.bar);
      expect(c.scrollbackLimit, 20000);
      expect(c.padding, const EdgeInsets.fromLTRB(4, 2, 8, 2));
      expect(c.optionAsAlt, OptionAsAlt.left);
      expect(c.confirmClose, ConfirmClose.always);
      expect(c.workingDirectory.kind, WorkingDirectoryKind.path);
      expect(c.workingDirectory.path, '/home/me/work');
      expect(c.origins['font-size']!.line, 3);
      expect([for (final o in c.fontFamilyOrigins) o.line], [1, 2]);
    });

    test('bad values are errors with a literal hint; the key keeps its '
        'earlier value (D8)', () {
      final (c, problems) = build('''
font-size = 15
font-size = to
background = red
cursor-style = beam
confirm-close-surface = yes
working-directory = work
macos-option-as-alt = maybe
''');
      expect(c.fontSize, 15);
      expect(c.background, isNull);
      expect(
        [
          for (final p in problems)
            (p.line, p.code, p.severity, p.key, p.value, p.hint),
        ],
        [
          (
            2,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'font-size',
            'to',
            '9–28',
          ),
          (
            3,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'background',
            'red',
            '#RRGGBB',
          ),
          (
            4,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'cursor-style',
            'beam',
            'block, bar, underline',
          ),
          (
            5,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'confirm-close-surface',
            'yes',
            'true, false, always',
          ),
          (
            6,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'working-directory',
            'work',
            'home, inherit or an absolute path',
          ),
          (
            7,
            ConfigProblemCode.badValue,
            ConfigSeverity.error,
            'macos-option-as-alt',
            'maybe',
            'true, false, left, right',
          ),
        ],
      );
    });

    test('out of range: clamped with a warning', () {
      final (c, problems) = build(
        'font-size = 40\nscrollback-limit = 10\nwindow-padding-x = 100\n',
      );
      expect(c.fontSize, 28);
      expect(c.scrollbackLimit, 1000);
      expect(c.padding.left, 64);
      expect(
        [for (final p in problems) (p.code, p.severity, p.hint, p.detail)],
        [
          (ConfigProblemCode.outOfRange, ConfigSeverity.warning, '9–28', '28'),
          (
            ConfigProblemCode.outOfRange,
            ConfigSeverity.warning,
            '1000–100000',
            '1000',
          ),
          (ConfigProblemCode.outOfRange, ConfigSeverity.warning, '0–64', '64'),
        ],
      );
    });

    test('an empty value resets to the default; a list key is cleared', () {
      final (c, _) = build('''
font-size = 20
font-size =
font-family = A
font-family =
font-family = B
palette = 2=#00ff00
palette =
''');
      expect(c.fontSize, isNull);
      expect(c.fontFamilies, ['B']);
      expect(c.palette, isEmpty);
    });

    test('notes: block_hollow, blink, palette 16+, option-as-alt on Windows', () {
      final (c, problems) = build(
        'cursor-style = block_hollow\ncursor-style-blink = true\npalette = 20=#000000\nmacos-option-as-alt = true\n',
        macos: false,
      );
      expect(c.cursorShape, CursorShape.block);
      expect(c.optionAsAlt, OptionAsAlt.both);
      expect(
        [for (final p in problems) (p.code, p.severity)],
        [
          (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
          (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
          (ConfigProblemCode.unsupportedValue, ConfigSeverity.info),
          (ConfigProblemCode.notOnThisPlatform, ConfigSeverity.info),
        ],
      );
    });

    test('an unknown key in the ShellX file is a warning', () {
      final (_, problems) = build('copy-on-select = true\n');
      expect(problems.single.code, ConfigProblemCode.unknownKey);
      expect(problems.single.severity, ConfigSeverity.warning);
      expect(problems.single.key, 'copy-on-select');
    });

    test('inherit and home', () {
      expect(
        build('working-directory = inherit').$1.workingDirectory.kind,
        WorkingDirectoryKind.inherit,
      );
      expect(
        build('working-directory = home').$1.workingDirectory.kind,
        WorkingDirectoryKind.home,
      );
    });

    test('cursor-text and selection-foreground are notes (D14)', () {
      final (c, problems) = build(
        'cursor-text = #000000\nselection-foreground = #ffffff\n',
      );
      expect(c.origins, isEmpty);
      expect(
        [for (final p in problems) (p.line, p.code, p.severity, p.key)],
        [
          (
            1,
            ConfigProblemCode.unsupportedValue,
            ConfigSeverity.info,
            'cursor-text',
          ),
          (
            2,
            ConfigProblemCode.unsupportedValue,
            ConfigSeverity.info,
            'selection-foreground',
          ),
        ],
      );
      final (_, quiet) = build(
        '',
        ghostty: 'cursor-text = #000000\nselection-foreground = #ffffff\n',
      );
      expect(quiet, isEmpty);
    });

    test('working-directory uses the shared absolute-path rule', () {
      expect(
        build('working-directory = ~').$1.workingDirectory.path,
        '/home/me',
      );
      for (final bad in ['~user/x', './x', r'C:\x']) {
        final (c, problems) = build('working-directory = $bad');
        expect(c.workingDirectory.kind, WorkingDirectoryKind.home, reason: bad);
        expect(problems.single.code, ConfigProblemCode.badValue, reason: bad);
      }
      (ShellxConfig, List<ConfigProblem>) win(String value) {
        final problems = <ConfigProblem>[];
        final config = buildShellxConfig(
          ghostty: const [],
          shellx: lines('working-directory = $value'),
          problems: problems,
          macos: false,
          home: r'C:\Users\me',
          windows: true,
        );
        return (config, problems);
      }

      expect(win(r'D:/work').$1.workingDirectory.path, r'D:\work');
      expect(win(r'~\work').$1.workingDirectory.path, r'C:\Users\me\work');
      expect(win(r'\\srv\share').$1.workingDirectory.path, r'\\srv\share');
      for (final bad in [r'\work', '/work', 'C:work', r'\\.\pipe\x']) {
        final (c, problems) = win(bad);
        expect(c.workingDirectory.kind, WorkingDirectoryKind.home, reason: bad);
        expect(problems.single.code, ConfigProblemCode.badValue, reason: bad);
      }
    });
  });

  group('the Ghostty layer (D4)', () {
    test('only drawing/typing keys; the rest is silent; ShellX wins', () {
      final (c, problems) = build(
        'font-size = 15\n',
        ghostty: '''
font-family = JetBrains Mono
font-size = 12
theme = Dracula
window-padding-x = 30
scrollback-limit = 10000000
keybind = super+d=new_split:left
confirm-close-surface = false
macos-option-as-alt = true
whatever = 1
''',
      );
      expect(problems, isEmpty);
      expect(c.fontFamilies, ['JetBrains Mono']);
      expect(c.fontSize, 15);
      expect(c.theme, 'Dracula');
      expect(c.padding, kDefaultTerminalPadding);
      expect(c.scrollbackLimit, 10000);
      expect(c.keybinds, isEmpty);
      expect(c.confirmClose, ConfirmClose.whenRunning);
      expect(c.optionAsAlt, OptionAsAlt.both);
    });

    test('a bad value of a taken key is a warning at the Ghostty line', () {
      final (_, problems) = build('', ghostty: '\nbackground = nope\n');
      expect(
        (problems.single.file, problems.single.line, problems.single.severity),
        (_ghostty, 2, ConfigSeverity.warning),
      );
    });

    test('the first ShellX font-family replaces the Ghostty list (D11)', () {
      final (c, _) = build(
        'font-family = Menlo\nfont-family = Symbols\n',
        ghostty: 'font-family = Fira Code\nfont-family = Noto\n',
      );
      expect(c.fontFamilies, ['Menlo', 'Symbols']);
    });

    test('ghostty-config = false drops the Ghostty layer', () {
      final (c, problems) = build(
        'ghostty-config = false\n',
        ghostty: 'font-size = 12\nbackground = nope\n',
      );
      expect(problems, isEmpty);
      expect(c.fontSize, isNull);
      expect(c.ghosttyConfig, isFalse);
    });

    test('ghosttyEnabled reads the last valid ghostty-config line', () {
      expect(ghosttyEnabled(lines('')), isTrue);
      expect(ghosttyEnabled(lines('ghostty-config = false')), isFalse);
      expect(
        ghosttyEnabled(lines('ghostty-config = false\nghostty-config = nope')),
        isFalse,
      );
      expect(
        ghosttyEnabled(lines('ghostty-config = false\nghostty-config =')),
        isTrue,
      );
    });
  });

  group('commands and snippets (D35)', () {
    test('name = text; quoted text uses escapes; enter only for command', () {
      final (c, problems) = build(r'''
command = Lint = npm run lint
snippet = Status = "git status\n"
command = Deploy = make deploy -- a=b
''');
      expect(problems, isEmpty);
      expect(
        [for (final x in c.commands) (x.name, x.text, x.enter)],
        [
          ('Lint', 'npm run lint', true),
          ('Status', 'git status\n', false),
          ('Deploy', 'make deploy -- a=b', true),
        ],
      );
    });

    test('bad shapes, duplicates and the 200 limit', () {
      final many = [
        for (var i = 0; i < 201; i++) 'command = c$i = echo $i',
      ].join('\n');
      final (c, problems) = build('''
command = no text here
command = = echo
command = ${'n' * 65} = echo
command = Lint = a
snippet = Lint = b
$many
''');
      expect(c.commands.where((x) => x.name == 'Lint').single.text, 'b');
      expect(c.commands.first.name, 'Lint'); // replaced in place
      expect(c.commands, hasLength(200));
      expect(
        [for (final p in problems) p.code],
        [
          ConfigProblemCode.badValue,
          ConfigProblemCode.badValue,
          ConfigProblemCode.badValue,
          ConfigProblemCode.duplicate,
          ConfigProblemCode.commandLimit,
        ],
      );
      expect(problems[3].detail, '4');
    });

    test('a duplicate name replaces in place; one namespace', () {
      final (c, _) = build(
        'command = A = 1\nsnippet = B = 2\nsnippet = A = 3\n',
      );
      expect(
        [for (final x in c.commands) (x.name, x.text, x.enter)],
        [('A', '3', false), ('B', '2', false)],
      );
    });

    test('command text is bounded in UTF-8 bytes', () {
      final fits = 'a' * 16384;
      final cjk = '漢' * 5462; // 16386 bytes, 5462 chars
      final emoji = '😀' * 4097; // 16388 bytes
      final (c, problems) = build(
        'command = Ok = $fits\ncommand = Cjk = $cjk\ncommand = Em = $emoji\n',
      );
      expect([for (final x in c.commands) x.name], ['Ok']);
      expect(problems.map((p) => p.code), [
        ConfigProblemCode.badValue,
        ConfigProblemCode.badValue,
      ]);
    });

    test('an empty command line clears commands, not snippets', () {
      final (c, _) = build('command = A = a\nsnippet = B = b\ncommand =\n');
      expect([for (final x in c.commands) x.name], ['B']);
    });
  });

  test('numbers are decimal only; a pair reports once per line', () {
    final (c, problems) = build(
      'scrollback-limit = 0x2000\nscrollback-limit = +5000\n'
      'palette = 0x1=#ff0000\npalette = +1=#ff0000\nfont-size = 0x10\n'
      'window-padding-x = 99,99\nwindow-padding-y = 5,zz\n',
    );
    expect(c.scrollbackLimit, 10000);
    expect(c.palette, isEmpty);
    expect(c.fontSize, isNull);
    expect(
      [for (final p in problems) (p.line, p.code)],
      [
        (1, ConfigProblemCode.badValue),
        (2, ConfigProblemCode.badValue),
        (3, ConfigProblemCode.badValue),
        (4, ConfigProblemCode.badValue),
        (5, ConfigProblemCode.badValue),
        (6, ConfigProblemCode.outOfRange),
        (7, ConfigProblemCode.badValue),
      ],
    );
  });

  test('a discarded pair never reports a clamp (A9 Task 3 review)', () {
    final (c, problems) = build(
      'window-padding-x = 100,abc\nwindow-padding-y = 99,7\n',
    );
    expect(c.padding.left, kDefaultTerminalPadding.left);
    expect(c.padding.top, 64);
    expect(
      [for (final p in problems) (p.line, p.code)],
      [(1, ConfigProblemCode.badValue), (2, ConfigProblemCode.outOfRange)],
    );
  });

  test('keybind lines are kept in order for the resolver (Task 4)', () {
    final (c, _) = build(
      'keybind = super+t=new_tab\nkeybind = clear\nkeybind =\nkeybind = super+y=new_tab\n',
    );
    expect([for (final k in c.keybinds) k.value], ['super+y=new_tab']);
  });

  group('colours', () {
    test('parseConfigColor', () {
      expect(parseConfigColor('#1d1f21'), const Color(0xFF1D1F21));
      expect(parseConfigColor('1D1F21'), const Color(0xFF1D1F21));
      expect(parseConfigColor('#abc'), const Color(0xFFAABBCC));
      expect(parseConfigColor('red'), isNull);
      expect(parseConfigColor('#12345'), isNull);
    });

    test('contrastRatio (WCAG)', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        contrastRatio(const Color(0xFFD4E1E4), const Color(0xFF0B1215)),
        greaterThan(4.5),
      );
    });
  });
}
