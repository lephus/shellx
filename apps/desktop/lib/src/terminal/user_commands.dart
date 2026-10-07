import 'package:xterm/core.dart';

import '../config/shellx_config.dart';
import 'terminal_tabs.dart';

enum CommandRun { ran, noTerminal }

/// D35: the selected tab's terminal pane that has the keyboard — with a
/// browser pane focused, the tab's active terminal pane (A6 makes
/// `focused` return it) — while its shell lives.
PaneSession? commandTarget(TerminalTabsState state) {
  final pane = state.selected?.focused;
  return pane == null || pane.exited ? null : pane;
}

/// D35: a command is pasted (A1's filtered paste, bracketed when the shell
/// asks) then Enter; a snippet only pasted.
CommandRun runUserCommand(TerminalTabsState state, UserCommand command) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  pane.terminal.paste(command.text);
  if (command.enter) pane.terminal.keyInput(TerminalKey.enter);
  return CommandRun.ran;
}

/// D31: `text:` / `csi:` / `esc:` bytes, raw.
CommandRun sendTextToFocused(TerminalTabsState state, String text) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  pane.terminal.sendUserText(text);
  return CommandRun.ran;
}
