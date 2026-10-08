import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'config_color.dart';
import 'config_files.dart';
import 'config_paths.dart';
import 'config_problem.dart';
import 'config_syntax.dart';
import 'keybind_actions.dart' show KeyAction;
import 'keybind_trigger.dart' show KeyChord, parseKeyChord;
import 'keybindings.dart' show checkTrigger;

const EdgeInsets kDefaultTerminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6);
const int kScrollbackDefault = 10000;
const int kScrollbackMin = 1000;
const int kScrollbackMax = 100000;
const double kFontSizeMin = 9;
const double kFontSizeMax = 28;
const double kPaddingMax = 64;
const double kCellHeightMin = -10;
const double kCellHeightMax = 50;
const int kMaxUserCommands = 200;
const int kMaxCommandName = 64;
const int kMaxCommandText = 16384;

enum CursorShape { block, bar, underline }

/// D19. `both` = Ghostty's `true`.
enum OptionAsAlt { off, both, left, right }

/// D20. `whenRunning` = Ghostty's `true`.
enum ConfirmClose { whenRunning, never, always }

/// A12 D13 `agent-resume`: after a restart, `ask` shows a button to
/// resume the agent that was running; `off` shows nothing.
enum AgentResume { ask, off }

/// `font-weight`: the bundled terminal font's face for normal text.
enum TerminalFontWeight { light, regular }

enum WorkingDirectoryKind { home, inherit, path }

@immutable
final class WorkingDirectory {
  const WorkingDirectory.home() : kind = WorkingDirectoryKind.home, path = null;
  const WorkingDirectory.inherit()
    : kind = WorkingDirectoryKind.inherit,
      path = null;
  const WorkingDirectory.at(String this.path)
    : kind = WorkingDirectoryKind.path;

  final WorkingDirectoryKind kind;
  final String? path;
}

/// D35: a `command` (paste + Enter) or a `snippet` (paste only).
@immutable
final class UserCommand {
  const UserCommand({
    required this.name,
    required this.text,
    required this.enter,
    required this.origin,
  });
  final String name;
  final String text;
  final bool enter;
  final ConfigEntry origin;
}

/// A raw `keybind` value, resolved in `keybindings.dart` (D22).
@immutable
final class KeybindEntry {
  const KeybindEntry(this.value, this.origin);
  final String value;
  final ConfigEntry origin;
}

/// D4: what ShellX takes from a Ghostty file.
const Set<String> kGhosttyKeys = {
  'font-family',
  'font-size',
  'theme',
  'background',
  'foreground',
  'palette',
  'cursor-color',
  'cursor-style',
  'selection-background',
  'macos-option-as-alt',
  'font-thicken',
};

/// The effective configuration (spec §3.1). Defaults = today's behaviour.
@immutable
final class ShellxConfig {
  const ShellxConfig({
    this.fontFamilies = const [],
    this.fontFamilyOrigins = const [],
    this.fontSize,
    this.fontWeight = TerminalFontWeight.light,
    this.theme,
    this.background,
    this.foreground,
    this.cursorColor,
    this.selectionBackground,
    this.palette = const {},
    this.cursorShape = CursorShape.block,
    this.scrollbackLimit = kScrollbackDefault,
    this.cellHeightPercent = 0,
    this.cursorBlink = false,
    this.padding = kDefaultTerminalPadding,
    this.optionAsAlt = OptionAsAlt.off,
    this.confirmClose = ConfirmClose.whenRunning,
    this.agentResume = AgentResume.ask,
    this.prStatus = false,
    this.agentEventCommand = '',
    this.workingDirectory = const WorkingDirectory.home(),
    this.keybinds = const [],
    this.commands = const [],
    this.ghosttyConfig = true,
    this.globalHotkey,
    this.origins = const {},
  });

  static const ShellxConfig defaults = ShellxConfig();

  final List<String> fontFamilies;

  /// The line of each [fontFamilies] entry (font probe problems, D11).
  final List<ConfigEntry> fontFamilyOrigins;
  final double? fontSize;

  /// `font-weight` (or Ghostty's `font-thicken = true`, which means
  /// regular): the bundled font's face, Light by default.
  final TerminalFontWeight fontWeight;
  final String? theme;
  final Color? background;
  final Color? foreground;
  final Color? cursorColor;
  final Color? selectionBackground;
  final Map<int, Color> palette;
  final CursorShape cursorShape;
  final int scrollbackLimit;

  /// `adjust-cell-height`: percent added to the line height (−10…50).
  final double cellHeightPercent;

  /// `cursor-style-blink` (ShellX file only, A11 D16).
  final bool cursorBlink;
  final EdgeInsets padding;
  final OptionAsAlt optionAsAlt;
  final ConfirmClose confirmClose;

  /// `agent-resume` (ShellX file only, A12 D13).
  final AgentResume agentResume;

  /// `pr-status` (ShellX file only, A12 D16): off by default.
  final bool prStatus;

  /// `agent-event-command` (the main ShellX file only, A12 D17): a command
  /// line for ShellX to run on agent events, once the user allowed it.
  final String agentEventCommand;
  final WorkingDirectory workingDirectory;
  final List<KeybindEntry> keybinds;
  final List<UserCommand> commands;
  final bool ghosttyConfig;

  /// `global-hotkey` (ShellX file only, A11 D22): one chord with a modifier
  /// that shows or hides the window from any app; null: off (the default).
  final KeyChord? globalHotkey;

  /// Key → the line that set its effective value (`shellx config show`).
  final Map<String, ConfigEntry> origins;
}

bool? _bool(String v) => switch (v) {
  'true' => true,
  'false' => false,
  _ => null,
};

/// D4: the last valid `ghostty-config` line of the ShellX chain (an empty
/// value resets to the default, true).
bool ghosttyEnabled(List<ConfigEntry> shellx) {
  var enabled = true;
  for (final e in shellx) {
    if (e.key != 'ghostty-config') continue;
    if (e.value.isEmpty) {
      enabled = true;
    } else {
      enabled = _bool(e.value) ?? enabled;
    }
  }
  return enabled;
}

/// D4/D7: Ghostty lines (only [kGhosttyKeys], none when [ghosttyEnabled]
/// is false) then ShellX lines, as one sequence; later lines win, list keys
/// accumulate, empty resets.
ShellxConfig buildShellxConfig({
  required List<ConfigEntry> ghostty,
  required List<ConfigEntry> shellx,
  required List<ConfigProblem> problems,
  required bool macos,
  required String home,
  bool windows = false,
  String? mainFile,
}) {
  final b = _Builder(
    problems,
    macos: macos,
    home: home,
    windows: windows,
    mainFile: mainFile,
  );
  if (ghosttyEnabled(shellx)) {
    for (final e in ghostty) {
      if (kGhosttyKeys.contains(e.key)) b.apply(e, fromGhostty: true);
    }
  }
  for (final e in shellx) {
    b.apply(e, fromGhostty: false);
  }
  return b.build();
}

final RegExp _digits = RegExp(r'^\d+$');
final RegExp _decimal = RegExp(r'^-?(\d+\.?\d*|\.\d+)$');

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

final class _Builder {
  _Builder(
    this.problems, {
    required this.macos,
    required this.home,
    required this.windows,
    this.mainFile,
  });

  /// The root of the ShellX chain; null: every ShellX line counts as its
  /// own (a single value being checked, a test).
  final String? mainFile;
  final List<ConfigProblem> problems;
  final bool macos;
  final String home;
  final bool windows;

  var families = <String>[];
  var familyOrigins = <ConfigEntry>[];
  var familiesFromGhostty = false;
  double? fontSize;
  var fontWeight = TerminalFontWeight.light;
  String? theme;
  Color? background, foreground, cursorColor, selectionBackground;
  final palette = <int, Color>{};
  var cursorShape = CursorShape.block;
  var scrollback = kScrollbackDefault;
  var cellHeight = 0.0;
  var cursorBlink = false;
  var padX = (kDefaultTerminalPadding.left, kDefaultTerminalPadding.right);
  var padY = (kDefaultTerminalPadding.top, kDefaultTerminalPadding.bottom);
  var optionAsAlt = OptionAsAlt.off;
  var confirmClose = ConfirmClose.whenRunning;
  var agentResume = AgentResume.ask;
  var prStatus = false;
  var agentEventCommand = '';
  WorkingDirectory workingDirectory = const WorkingDirectory.home();
  final keybinds = <KeybindEntry>[];
  final commands = <UserCommand>[];
  var commandLimitReported = false;
  var ghosttyConfig = true;
  KeyChord? globalHotkey;
  final origins = <String, ConfigEntry>{};

  ConfigSeverity _bad(bool fromGhostty) =>
      fromGhostty ? ConfigSeverity.warning : ConfigSeverity.error;

  void _problem(
    ConfigEntry e,
    ConfigSeverity severity,
    ConfigProblemCode code, {
    String? value,
    String? hint,
    String? detail,
  }) => problems.add(
    ConfigProblem(
      file: e.file,
      line: e.line,
      severity: severity,
      code: code,
      key: e.key,
      value: value ?? e.value,
      hint: hint,
      detail: detail,
    ),
  );

  void _badValue(ConfigEntry e, bool g, String hint) =>
      _problem(e, _bad(g), ConfigProblemCode.badValue, hint: hint);

  double? _ranged(
    ConfigEntry e,
    String raw,
    double min,
    double max,
    bool g, {
    bool integer = false,
  }) {
    final v = integer
        ? (_digits.hasMatch(raw) ? int.tryParse(raw)?.toDouble() : null)
        : (_decimal.hasMatch(raw) ? double.tryParse(raw) : null);
    final hint = '${_num(min)}–${_num(max)}';
    if (v == null || v.isNaN) {
      _badValue(e, g, hint);
      return null;
    }
    final clamped = v.clamp(min, max).toDouble();
    if (clamped != v) {
      _problem(
        e,
        ConfigSeverity.warning,
        ConfigProblemCode.outOfRange,
        value: raw,
        hint: hint,
        detail: _num(clamped),
      );
    }
    return clamped;
  }

  (double, double)? _pair(ConfigEntry e, bool g) {
    final parts = e.value.split(',');
    if (parts.length > 2) {
      _badValue(e, g, 'N or A,B (0–64)');
      return null;
    }
    final values = <double>[];
    final first = problems.length;
    (double, double)? result;
    for (final part in parts) {
      final v = _ranged(e, part.trim(), 0, kPaddingMax, g);
      if (v == null) {
        result = null;
        values.clear();
        break;
      }
      values.add(v);
    }
    if (values.isNotEmpty) result = (values.first, values.last);
    // One problem per line. A discarded pair reports only its bad value (a
    // clamp note on an earlier half would claim a value that is not used);
    // a kept pair reports its first clamp.
    if (result == null && problems.length > first) {
      final bad = problems.last;
      problems
        ..removeRange(first, problems.length)
        ..add(bad);
    } else if (problems.length > first + 1) {
      problems.removeRange(first + 1, problems.length);
    }
    return result;
  }

  void apply(ConfigEntry e, {required bool fromGhostty}) {
    final g = fromGhostty;
    final v = e.value;
    switch (e.key) {
      case 'font-family':
        if (!g && familiesFromGhostty) {
          families = [];
          familyOrigins = [];
          familiesFromGhostty = false;
        }
        if (v.isEmpty) {
          families = [];
          familyOrigins = [];
        } else {
          families.add(v);
          familyOrigins.add(e);
          if (g) familiesFromGhostty = true;
        }
      case 'font-size':
        if (v.isEmpty) {
          fontSize = null;
        } else {
          final size = _ranged(e, v, kFontSizeMin, kFontSizeMax, g);
          if (size == null) return;
          fontSize = size;
        }
      case 'theme':
        theme = v.isEmpty ? null : v;
      case 'background' ||
          'foreground' ||
          'cursor-color' ||
          'selection-background':
        Color? color;
        if (v.isNotEmpty) {
          color = parseConfigColor(v);
          if (color == null) return _badValue(e, g, '#RRGGBB');
        }
        switch (e.key) {
          case 'background':
            background = color;
          case 'foreground':
            foreground = color;
          case 'cursor-color':
            cursorColor = color;
          default:
            selectionBackground = color;
        }
      case 'palette':
        if (v.isEmpty) {
          palette.clear();
        } else {
          final eq = v.indexOf('=');
          final indexText = eq < 0 ? '' : v.substring(0, eq).trim();
          final index = _digits.hasMatch(indexText)
              ? int.tryParse(indexText)
              : null;
          final color = eq < 0 ? null : parseConfigColor(v.substring(eq + 1));
          if (index == null || color == null || index < 0 || index > 255) {
            return _badValue(e, g, 'N=#RRGGBB');
          }
          if (index > 15) {
            return _problem(
              e,
              ConfigSeverity.info,
              ConfigProblemCode.unsupportedValue,
              hint: '0–15',
            );
          }
          palette[index] = color;
        }
      case 'cursor-style':
        switch (v) {
          case '' || 'block':
            cursorShape = CursorShape.block;
          case 'bar':
            cursorShape = CursorShape.bar;
          case 'underline':
            cursorShape = CursorShape.underline;
          case 'block_hollow':
            cursorShape = CursorShape.block;
            _problem(
              e,
              ConfigSeverity.info,
              ConfigProblemCode.unsupportedValue,
              hint: 'block',
            );
          default:
            return _badValue(e, g, 'block, bar, underline');
        }
      case 'cursor-style-blink':
        final blink = v.isEmpty ? false : _bool(v);
        if (blink == null) return _badValue(e, g, 'true, false');
        cursorBlink = blink;
      case 'adjust-cell-height':
        if (v.isEmpty) {
          cellHeight = 0;
        } else {
          final raw = v.endsWith('%') ? v.substring(0, v.length - 1).trim() : v;
          final n = _ranged(e, raw, kCellHeightMin, kCellHeightMax, g);
          if (n == null) return;
          cellHeight = n;
        }
      case 'font-feature':
        // ShellX draws no ligatures: accepted so a shared file stays valid.
        _problem(
          e,
          ConfigSeverity.info,
          ConfigProblemCode.unsupportedValue,
          hint: 'no ligatures',
        );
        return;
      case 'scrollback-limit':
        if (v.isEmpty) {
          scrollback = kScrollbackDefault;
        } else {
          final lines = _ranged(
            e,
            v,
            kScrollbackMin.toDouble(),
            kScrollbackMax.toDouble(),
            g,
            integer: true,
          );
          if (lines == null) return;
          scrollback = lines.toInt();
        }
      case 'window-padding-x':
        if (v.isEmpty) {
          padX = (kDefaultTerminalPadding.left, kDefaultTerminalPadding.right);
        } else {
          final pair = _pair(e, g);
          if (pair == null) return;
          padX = pair;
        }
      case 'window-padding-y':
        if (v.isEmpty) {
          padY = (kDefaultTerminalPadding.top, kDefaultTerminalPadding.bottom);
        } else {
          final pair = _pair(e, g);
          if (pair == null) return;
          padY = pair;
        }
      case 'font-weight':
        final w = switch (v) {
          '' || 'light' => TerminalFontWeight.light,
          'regular' => TerminalFontWeight.regular,
          _ => null,
        };
        if (w == null) return _badValue(e, g, 'light, regular');
        fontWeight = w;
      case 'font-thicken':
        // Ghostty's key (heavier text) read as regular; ShellX's default is
        // already lighter than that, so false leaves [fontWeight] to the
        // other key's default.
        final on = v.isEmpty ? false : _bool(v);
        if (on == null) return _badValue(e, g, 'true, false');
        fontWeight = on ? TerminalFontWeight.regular : TerminalFontWeight.light;
      case 'macos-option-as-alt':
        final mode = switch (v) {
          '' || 'false' => OptionAsAlt.off,
          'true' => OptionAsAlt.both,
          'left' => OptionAsAlt.left,
          'right' => OptionAsAlt.right,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'true, false, left, right');
        optionAsAlt = mode;
        if (!macos && !g && mode != OptionAsAlt.off) {
          _problem(e, ConfigSeverity.info, ConfigProblemCode.notOnThisPlatform);
        }
      case 'confirm-close-surface':
        final mode = switch (v) {
          '' || 'true' => ConfirmClose.whenRunning,
          'false' => ConfirmClose.never,
          'always' => ConfirmClose.always,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'true, false, always');
        confirmClose = mode;
      case 'agent-resume':
        final mode = switch (v) {
          '' || 'ask' => AgentResume.ask,
          'off' => AgentResume.off,
          _ => null,
        };
        if (mode == null) return _badValue(e, g, 'ask, off');
        agentResume = mode;
      case 'pr-status':
        final on = v.isEmpty ? false : _bool(v);
        if (on == null) return _badValue(e, g, 'true, false');
        prStatus = on;
      case 'agent-event-command':
        // Only the user's own file: a file an agent can edit (an include,
        // through the `shellx-config` skill) must not choose what runs.
        final main = mainFile;
        if (main != null && e.file != main) {
          return _problem(
            e,
            ConfigSeverity.warning,
            ConfigProblemCode.unsupportedValue,
            value: '',
          );
        }
        if (v.length > 4096 || v.contains(RegExp(r'[\r\n]'))) {
          return _badValue(e, g, 'one line, up to 4096 characters');
        }
        agentEventCommand = v;
      case 'working-directory':
        if (v.isEmpty || v == 'home') {
          workingDirectory = const WorkingDirectory.home();
        } else if (v == 'inherit') {
          workingDirectory = const WorkingDirectory.inherit();
        } else {
          const hint = 'home, inherit or an absolute path';
          final tilde =
              v == '~' ||
              v.startsWith('~/') ||
              (windows && v.startsWith(r'~\'));
          if (!tilde && !isAbsoluteConfigPath(v, windows: windows)) {
            return _badValue(e, g, hint);
          }
          try {
            workingDirectory = WorkingDirectory.at(
              expandConfigPath(v, baseDir: home, home: home, windows: windows),
            );
          } on ArgumentError {
            return _badValue(e, g, hint); // no usable home for `~`
          }
        }
      case 'keybind':
        if (v.isEmpty) {
          keybinds.clear();
        } else {
          keybinds.add(KeybindEntry(v, e));
        }
      case 'command' || 'snippet':
        _command(e, enter: e.key == 'command');
      case 'cursor-text' || 'selection-foreground':
        // D14: xterm 4 can't draw them; a note from the ShellX file (the
        // Ghostty layer never takes them, see [kGhosttyKeys]).
        if (v.isNotEmpty) {
          _problem(e, ConfigSeverity.info, ConfigProblemCode.unsupportedValue);
        }
        return;
      case 'global-hotkey':
        if (v.isEmpty) {
          globalHotkey = null;
          break;
        }
        const hint = 'ctrl+alt+j';
        // One chord only: a sequence (`>`) is a keybind's.
        final chord = v.contains('>') ? null : parseKeyChord(v);
        if (chord == null) return _badValue(e, g, hint);
        final rule = checkTrigger(
          [chord],
          const KeyAction('open_settings'),
          mac: macos,
          optionAsAlt: OptionAsAlt.off,
        );
        // A global key needs a real modifier: Shift alone and a bare
        // function key would fire in every other app's typing.
        final code =
            rule.error ??
            (chord.hasCommandModifier
                ? null
                : ConfigProblemCode.plainKeyTrigger);
        if (code != null) {
          return _problem(e, _bad(g), code, hint: hint);
        }
        globalHotkey = chord;
      case 'ghostty-config':
        final on = v.isEmpty ? true : _bool(v);
        if (on == null) return _badValue(e, g, 'true, false');
        ghosttyConfig = on;
      default:
        if (!g) {
          _problem(e, ConfigSeverity.warning, ConfigProblemCode.unknownKey);
        }
        return;
    }
    origins[e.key] = e;
  }

  void _command(ConfigEntry e, {required bool enter}) {
    final v = e.value;
    if (v.isEmpty) {
      commands.removeWhere((c) => c.enter == enter);
      return;
    }
    const hint = 'name = text';
    final eq = v.indexOf('=');
    if (eq < 0) return _badValue(e, false, hint);
    final name = v.substring(0, eq).trim();
    var text = v.substring(eq + 1).trim();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      final decoded = decodeZigString(text.substring(1, text.length - 1));
      if (decoded == null) return _badValue(e, false, hint);
      text = decoded;
    }
    if (name.isEmpty ||
        name.length > kMaxCommandName ||
        text.isEmpty ||
        utf8.encode(text).length > kMaxCommandText) {
      return _badValue(e, false, '$hint, name ≤ 64, text ≤ 16 KiB');
    }
    final previous = commands.indexWhere((c) => c.name == name);
    if (previous >= 0) {
      _problem(
        e,
        ConfigSeverity.info,
        ConfigProblemCode.duplicate,
        detail: '${commands[previous].origin.line}',
      );
      // The later entry replaces the earlier one in place (file position
      // kept); commands and snippets share one namespace.
      commands[previous] = UserCommand(
        name: name,
        text: text,
        enter: enter,
        origin: e,
      );
      return;
    } else if (commands.length >= kMaxUserCommands) {
      if (!commandLimitReported) {
        commandLimitReported = true;
        _problem(e, ConfigSeverity.warning, ConfigProblemCode.commandLimit);
      }
      return;
    }
    commands.add(UserCommand(name: name, text: text, enter: enter, origin: e));
  }

  ShellxConfig build() => ShellxConfig(
    fontFamilies: List.unmodifiable(families),
    fontFamilyOrigins: List.unmodifiable(familyOrigins),
    fontSize: fontSize,
    fontWeight: fontWeight,
    theme: theme,
    background: background,
    foreground: foreground,
    cursorColor: cursorColor,
    selectionBackground: selectionBackground,
    palette: Map.unmodifiable(palette),
    cursorShape: cursorShape,
    scrollbackLimit: scrollback,
    cellHeightPercent: cellHeight,
    cursorBlink: cursorBlink,
    padding: EdgeInsets.fromLTRB(padX.$1, padY.$1, padX.$2, padY.$2),
    optionAsAlt: optionAsAlt,
    confirmClose: confirmClose,
    agentResume: agentResume,
    prStatus: prStatus,
    agentEventCommand: agentEventCommand,
    workingDirectory: workingDirectory,
    keybinds: List.unmodifiable(keybinds),
    commands: List.unmodifiable(commands),
    ghosttyConfig: ghosttyConfig,
    globalHotkey: globalHotkey,
    origins: Map.unmodifiable(origins),
  );
}
