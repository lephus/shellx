import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

import '../ui/theme/shellx_desktop_theme.dart';
import '../ui/theme/terminal_colors.dart';
import 'config_color.dart';
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_syntax.dart';
import 'shellx_config.dart';

/// What the terminal area draws with (A9 D13-D15).
@immutable
final class ResolvedTheme {
  const ResolvedTheme({
    required this.terminal,
    required this.background,
    required this.focusOutline,
    this.name,
  });

  /// No theme and no colour keys: today's colours exactly.
  static const ResolvedTheme defaults = ResolvedTheme(
    terminal: TerminalColors.theme,
    background: TerminalColors.background,
    focusOutline: ShellxDesktopColors.accent,
  );

  final TerminalTheme terminal;

  /// The terminal area behind and around panes (padding included).
  final Color background;

  /// A3 D16's pane outline, readable on [background] (D15).
  final Color focusOutline;

  /// The theme name or path in use; null for the built-in palette.
  final String? name;
}

bool _isPairPart(String part) {
  final t = part.trim();
  return t.startsWith('light:') || t.startsWith('dark:');
}

/// The `light:` / `dark:` sides of a pair value; an empty side is absent.
({String? light, String? dark}) _sides(String value) {
  String? light;
  String? dark;
  for (final part in value.split(',')) {
    final t = part.trim();
    if (t.startsWith('dark:')) dark = t.substring(5).trim();
    if (t.startsWith('light:')) light = t.substring(6).trim();
  }
  return (
    light: light == null || light.isEmpty ? null : light,
    dark: dark == null || dark.isEmpty ? null : dark,
  );
}

/// `light:A,dark:B` -> `B` (ShellX is dark-only), `light:A` (or
/// `light:A,dark:`) -> `A`; any other value as is.
String? themeNameFor(String value) {
  if (!value.split(',').any(_isPairPart)) return value.trim();
  final s = _sides(value);
  return s.dark ?? s.light;
}

bool _lightOnly(String value) {
  if (!value.split(',').any(_isPairPart)) return false;
  final s = _sides(value);
  return s.light != null && s.dark == null;
}

/// D15: `accent` when it reaches 3:1 on [background] (WCAG 1.4.11),
/// otherwise the more readable of the dark terminal colour and the title
/// text (in practice always `bgTerminal`).
Color focusOutlineFor(Color background) {
  const accent = ShellxDesktopColors.accent;
  if (contrastRatio(accent, background) >= 3) return accent;
  const dark = ShellxDesktopColors.bgTerminal;
  const light = ShellxDesktopColors.textTitle;
  return contrastRatio(dark, background) >= contrastRatio(light, background)
      ? dark
      : light;
}

final RegExp _digits = RegExp(r'^\d+$');

final class _ThemeColors {
  Color? background, foreground, cursor, selection;
  final Map<int, Color> palette = {};
}

void _applyThemeLine(ConfigEntry e, _ThemeColors c) {
  switch (e.key) {
    case 'background':
      c.background = parseConfigColor(e.value) ?? c.background;
    case 'foreground':
      c.foreground = parseConfigColor(e.value) ?? c.foreground;
    case 'cursor-color':
      c.cursor = parseConfigColor(e.value) ?? c.cursor;
    case 'selection-background':
      c.selection = parseConfigColor(e.value) ?? c.selection;
    case 'palette':
      final eq = e.value.indexOf('=');
      if (eq < 0) return;
      final indexText = e.value.substring(0, eq).trim();
      final index = _digits.hasMatch(indexText)
          ? int.tryParse(indexText)
          : null;
      final color = parseConfigColor(e.value.substring(eq + 1));
      if (index != null && index < 16 && color != null) {
        c.palette[index] = color;
      }
  }
}

/// Bounded, regular files only (through [ConfigFs]); a theme that is
/// missing, unreadable, too large or not UTF-8 counts as not found. Its own
/// syntax problems and unknown keys are not reported (D13).
Future<_ThemeColors?> _readTheme(String path, ConfigFs fs) async {
  try {
    final bytes = await fs.read(path);
    if (bytes == null) return null;
    final entries = parseConfigText(
      decodeConfigBytes(bytes),
      file: path,
      problems: [],
    );
    final colors = _ThemeColors();
    for (final e in entries) {
      _applyThemeLine(e, colors);
    }
    return colors;
  } on FormatException {
    return null;
  } on ConfigTooLarge {
    return null;
  } on FileSystemException {
    return null;
  }
}

/// The files a theme [name] may live in; empty when the name is unsafe
/// (a bare name never leaves its directory: no separator, not `..`, no
/// NUL, and on Windows no drive colon).
List<String> _candidates(String name, ConfigPaths paths) {
  if (name.contains('\x00')) return const [];
  final ctx = paths.windows ? p.windows : p.posix;
  final tilde =
      name == '~' ||
      name.startsWith('~/') ||
      (paths.windows && name.startsWith(r'~\'));
  if (tilde || isAbsoluteConfigPath(name, windows: paths.windows)) {
    try {
      return [
        expandConfigPath(
          name,
          baseDir: paths.home,
          home: paths.home,
          windows: paths.windows,
        ),
      ];
    } on ArgumentError {
      return const [];
    } on FormatException {
      return const [];
    }
  }
  if (name.contains('/') ||
      name.contains(r'\') ||
      name == '..' ||
      (paths.windows && name.contains(':'))) {
    return const [];
  }
  return [for (final dir in paths.themeDirs) ctx.join(dir, name)];
}

List<Color> _basePalette() {
  const t = TerminalColors.theme;
  return [
    t.black,
    t.red,
    t.green,
    t.yellow,
    t.blue,
    t.magenta,
    t.cyan,
    t.white,
    t.brightBlack,
    t.brightRed,
    t.brightGreen,
    t.brightYellow,
    t.brightBlue,
    t.brightMagenta,
    t.brightCyan,
    t.brightWhite,
  ];
}

/// D13-D15: the theme file (if any) under the explicit colour keys, over
/// the A1 palette. [files] is every path looked at (the watcher's list).
Future<({ResolvedTheme theme, List<String> files})> resolveTheme(
  ShellxConfig config,
  ConfigPaths paths, {
  required ConfigFs fs,
  required List<ConfigProblem> problems,
}) async {
  final files = <String>[];
  final raw = config.theme;
  final at = config.origins['theme'];
  ConfigProblem themeProblem(
    ConfigSeverity severity,
    ConfigProblemCode code,
    String value, {
    String? hint,
  }) => ConfigProblem(
    file: at?.file ?? paths.shellx,
    line: at?.line ?? 0,
    severity: severity,
    code: code,
    key: 'theme',
    value: value,
    hint: hint,
  );

  _ThemeColors? fromTheme;
  String? used;
  final name = raw == null ? null : themeNameFor(raw);
  if (name != null && name.isNotEmpty && name.toLowerCase() != 'shellx') {
    if (_lightOnly(raw!)) {
      problems.add(
        themeProblem(
          ConfigSeverity.info,
          ConfigProblemCode.unsupportedValue,
          raw,
          hint: name,
        ),
      );
    }
    for (final path in _candidates(name, paths)) {
      files.add(path);
      fromTheme = await _readTheme(path, fs);
      if (fromTheme != null) {
        used = name;
        break;
      }
    }
    if (fromTheme == null) {
      problems.add(
        themeProblem(
          ConfigSeverity.warning,
          ConfigProblemCode.themeNotFound,
          name,
        ),
      );
    }
  }

  const base = TerminalColors.theme;
  final palette = _basePalette();
  fromTheme?.palette.forEach((i, c) => palette[i] = c);
  config.palette.forEach((i, c) => palette[i] = c);
  final background =
      config.background ?? fromTheme?.background ?? base.background;
  final foreground =
      config.foreground ?? fromTheme?.foreground ?? base.foreground;
  final cursor = config.cursorColor ?? fromTheme?.cursor ?? foreground;
  final selectionSource = config.selectionBackground ?? fromTheme?.selection;
  // xterm 4 paints the selection over the text: 40 % keeps it readable.
  final selection = selectionSource?.withAlpha(0x66) ?? base.selection;

  final terminal = TerminalTheme(
    cursor: cursor,
    selection: selection,
    foreground: foreground,
    background: background,
    black: palette[0],
    red: palette[1],
    green: palette[2],
    yellow: palette[3],
    blue: palette[4],
    magenta: palette[5],
    cyan: palette[6],
    white: palette[7],
    brightBlack: palette[8],
    brightRed: palette[9],
    brightGreen: palette[10],
    brightYellow: palette[11],
    brightBlue: palette[12],
    brightMagenta: palette[13],
    brightCyan: palette[14],
    brightWhite: palette[15],
    searchHitBackground: palette[3],
    searchHitBackgroundCurrent: palette[6],
    searchHitForeground: background,
  );

  final ratio = contrastRatio(foreground, background);
  if (ratio < 4.5) {
    final where =
        config.origins['foreground'] ??
        config.origins['background'] ??
        config.origins['theme'];
    problems.add(
      ConfigProblem(
        file: where?.file ?? paths.shellx,
        line: where?.line ?? 0,
        severity: ConfigSeverity.warning,
        code: ConfigProblemCode.lowContrast,
        // Truncated: 4.49 must not read as a passing "4.5".
        detail: ((ratio * 10).floor() / 10).toStringAsFixed(1),
      ),
    );
  }

  return (
    theme: ResolvedTheme(
      terminal: terminal,
      background: background,
      focusOutline: focusOutlineFor(background),
      name: used,
    ),
    files: files,
  );
}
