import 'dart:async';

import 'package:xterm/core.dart';

import '../config/shellx_config.dart';
import 'pane_paste.dart';
import 'paste_sender.dart';
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
///
/// The paste goes through [sender] (A10 D13: queued behind a paste already
/// running in the pane, sent in pieces when large); Enter follows once it
/// has been written, and only if the pane is still the same live session.
CommandRun runUserCommand(
  TerminalTabsState state,
  UserCommand command, {
  required PasteSender sender,
  required TerminalTabsState Function() tabs,
}) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  final sink = PanePasteSink(tabs, pane.id, pane.terminal);
  unawaited(() async {
    final outcome = await sender.send(pane.id, command.text, sink);
    if (command.enter && outcome == PasteOutcome.sent && sink.alive) {
      pane.terminal.keyInput(TerminalKey.enter);
    }
  }());
  return CommandRun.ran;
}

/// D31: `text:` / `csi:` / `esc:` bytes, raw.
CommandRun sendTextToFocused(TerminalTabsState state, String text) {
  final pane = commandTarget(state);
  if (pane == null) return CommandRun.noTerminal;
  pane.terminal.sendUserText(text);
  return CommandRun.ran;
}
