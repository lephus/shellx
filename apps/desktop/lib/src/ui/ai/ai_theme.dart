import 'package:flutter/painting.dart';

import '../theme/shellx_desktop_theme.dart';

/// V2-1 §4.1: the AI pane's sizes (the demo's layout; colours, spacing and
/// type come from the desktop theme).
abstract final class AiSizes {
  static const double header = 34;
  static const double column = 760;
  static const double panel = 268;
  static const double composerMax = 140;

  /// Smoothness: a tool card shows this many first and last lines of its
  /// output; "Show all N lines" shows the rest (in a scrolled box).
  static const int outputLines = 200;

  /// Smoothness: one markdown block longer than this is shown as plain
  /// text (a parse that long would cost a frame).
  static const int markdownBlockMax = 20000;
}

/// Code, diffs, commands: the terminal's font.
const TextStyle kAiMono = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 12,
  height: 17 / 12,
  color: ShellxDesktopColors.textPrimary,
);
