import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_terminal.dart';
import 'paste_sender.dart';
import 'terminal_tabs.dart';

/// A10 D13: one sender for the window, so pastes into a pane queue up
/// whether they come from the keyboard, the menu or a drop.
final pasteSenderProvider = Provider<PasteSender>((ref) => PasteSender());

/// Pane [paneId]'s terminal as [PasteSender] writes to it. It is alive
/// while the pane is still in a tab, has not exited and still has the
/// terminal it had when the user pasted (a reconnect replaces the
/// session).
final class PanePasteSink implements PasteSink {
  PanePasteSink(this._tabs, this._paneId, this._terminal);

  /// Reads the current tabs (`ref.read(terminalTabsProvider)`).
  final TerminalTabsState Function() _tabs;
  final int _paneId;
  final DesktopTerminal _terminal;

  @override
  bool get alive {
    final pane = _tabs().tabOfSession(_paneId)?.panes[_paneId];
    return pane != null && !pane.exited && identical(pane.terminal, _terminal);
  }

  @override
  bool get bracketed => _terminal.bracketedPasteMode;

  @override
  void paste(String text) => _terminal.paste(text);

  @override
  void send(String data) => _terminal.sendUserText(data);
}
