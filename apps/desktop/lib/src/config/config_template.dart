import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'config_controller.dart';

/// D37: the file "Open configuration file" creates — every line a comment,
/// so it changes nothing until the user uncomments one. English, like the
/// CLI (A7 D11).
String configTemplate({required bool mac, required List<String> ghosttyFiles}) {
  final reload = mac ? 'Cmd+Shift+,' : 'Ctrl+Shift+,';
  final split = mac ? 'super+shift+t' : 'ctrl+shift+alt+t';
  final unbind = mac ? 'super+d' : 'ctrl+shift+d';
  final run = mac ? 'super+shift+l' : 'ctrl+shift+alt+l';
  final ghostty = ghosttyFiles.isEmpty
      ? ['#   (none found)']
      : [for (final f in ghosttyFiles) '#   $f'];
  return [
    '# ShellX configuration. Ghostty syntax: key = value; lines starting with # are comments.',
    '# Saved changes apply within a second; reload now with $reload.',
    '# Problems: Command palette → "Show configuration problems", or `shellx config check`.',
    '#',
    '# ShellX also reads fonts and colours from your Ghostty configuration:',
    ...ghostty,
    '# Turn that off with: ghostty-config = false',
    '',
    '# --- Text ---',
    '# font-family = JetBrains Mono',
    '# font-size = 13  (9–28)',
    '',
    '# --- Colours (hex) ---',
    '# theme = Dracula  (a file in the themes folder next to this file, or a Ghostty theme)',
    '# background = #0b1215',
    '# foreground = #d4e1e4',
    '# palette = 1=#f07178',
    '# cursor-color = #d4e1e4',
    '# selection-background = #5fd4e2',
    '# cursor-style = block  (block, bar, underline)',
    '',
    '# --- Terminal ---',
    '# scrollback-limit = 10000  (lines, for new panes)',
    '# window-padding-x = 10',
    '# window-padding-y = 6',
    '# macos-option-as-alt = false  (true, left, right)',
    '# confirm-close-surface = true  (false, always)',
    '# working-directory = home  (inherit, or an absolute path)',
    '',
    '# --- Keys (Ghostty keybind syntax; later lines win) ---',
    '# keybind = $split=new_split:down',
    '# keybind = ctrl+a>c=new_tab',
    '# keybind = $unbind=unbind',
    '# keybind = $run=run_command:Lint',
    '',
    '# --- Your commands (Command palette) ---',
    '# command = Lint = npm run lint',
    r'# snippet = Status = "git status\n"',
    '',
  ].join('\n');
}

/// The one template everywhere it is shown (opener, sheet, CLI): the
/// Ghostty files in play are the ones the last load actually read.
String shellxTemplate(T Function<T>(ProviderListenable<T> provider) read) {
  final paths = read(configPathsProvider);
  final state = read(shellxConfigProvider);
  return configTemplate(
    mac: read(configPlatformProvider) == TargetPlatform.macOS,
    ghosttyFiles: [
      for (final f in paths.ghostty)
        if (state.ghosttyUsed && state.files.contains(f)) f,
    ],
  );
}
