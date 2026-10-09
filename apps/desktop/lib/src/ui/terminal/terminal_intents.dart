import 'package:flutter/widgets.dart';

import '../../terminal/edit_line.dart';
import '../../terminal/pane_layout.dart';

// The window intents (A1–A4, A3; A9 adds the last group). The shortcut
// maps are built from the key bindings (A9 D24, `config/keybindings.dart`).

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

/// ⌘⇧N / Ctrl+Shift+N (A2 C5): a new workspace with a tab in it.
class NewWorkspaceIntent extends Intent {
  const NewWorkspaceIntent();
}

/// ⌘D / ⌘⇧D (A3 P3): split the focused pane of the selected tab.
class SplitPaneIntent extends Intent {
  const SplitPaneIntent(this.axis);
  final SplitAxis axis;
}

/// ⌘⌥arrows / Ctrl+Alt+arrows (D9).
class FocusPaneIntent extends Intent {
  const FocusPaneIntent(this.direction);
  final PaneDirection direction;
}

/// ⌘⇧↩ / Ctrl+Shift+Enter (D10).
class TogglePaneZoomIntent extends Intent {
  const TogglePaneZoomIntent();
}

/// ⌘⌃= / Ctrl+Shift+Alt+= (D11).
class EqualizePanesIntent extends Intent {
  const EqualizePanesIntent();
}

/// ⌘⌃arrows / Ctrl+Shift+Alt+arrows (D12).
class ResizePaneIntent extends Intent {
  const ResizePaneIntent(this.direction);
  final PaneDirection direction;
}

/// ⌘⇧I / Ctrl+Shift+I: open or close the notifications panel (A4 N5).
class ToggleNotificationsPanelIntent extends Intent {
  const ToggleNotificationsPanelIntent();
}

/// ⌘⇧U / Ctrl+Shift+U: the next tab with unread (A4 N5, D13).
class JumpToNextUnreadIntent extends Intent {
  const JumpToNextUnreadIntent();
}

class SelectTabIntent extends Intent {
  const SelectTabIntent(this.position);

  /// 1-based.
  final int position;
}

class NextTabIntent extends Intent {
  const NextTabIntent();
}

class PreviousTabIntent extends Intent {
  const PreviousTabIntent();
}

class CopySelectionIntent extends Intent {
  const CopySelectionIntent();
}

class PasteClipboardIntent extends Intent {
  const PasteClipboardIntent();
}

/// The whole buffer, scrollback included (Terminal.app, iTerm2, Windows
/// Terminal), not only the screen. From the keyboard it applies only while
/// the terminal has the focus; the terminal's own menu sets [fromMenu]
/// (the menu holds the focus while it is open).
class SelectAllIntent extends Intent {
  const SelectAllIntent({this.fromMenu = false});
  final bool fromMenu;
}

/// A10 D4: ⌘F — opens (or refocuses) the find bar of the focused pane.
class StartSearchIntent extends Intent {
  const StartSearchIntent();
}

/// A10 D4: ⌘G / ⌘⇧G — the next / previous match of the focused pane's bar.
class NavigateSearchIntent extends Intent {
  const NavigateSearchIntent({required this.next});
  final bool next;
}

/// A11 D11: a macOS line-editing key at the prompt (⌘←, ⌘⌫, ⌥⌫ …).
class EditLineIntent extends Intent {
  const EditLineIntent(this.op);
  final EditLineOp op;
}

/// A10 D4: closes the focused pane's find bar.
class EndSearchIntent extends Intent {
  const EndSearchIntent();
}

class FontBiggerIntent extends Intent {
  const FontBiggerIntent({this.step = 1});

  /// Points (A9 D12: `increase_font_size:N`).
  final double step;
}

class FontSmallerIntent extends Intent {
  const FontSmallerIntent({this.step = 1});

  /// Points (A9 D12: `decrease_font_size:N`).
  final double step;
}

class FontResetIntent extends Intent {
  const FontResetIntent();
}

class NextRegionIntent extends Intent {
  const NextRegionIntent();
}

class PreviousRegionIntent extends Intent {
  const PreviousRegionIntent();
}

/// A9 D23 `close_tab`: every pane of the selected tab (A3 D6's row ×).
class CloseWholeTabIntent extends Intent {
  const CloseWholeTabIntent();
}

/// A9 D9 ⌘⇧, / Ctrl+Shift+,.
class ReloadConfigIntent extends Intent {
  const ReloadConfigIntent();
}

/// A11 D10 ⌘, / Ctrl+,: the Settings window.
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// A9 D37, moved by A11 D10 to ⌘⌥, / Ctrl+Shift+Alt+,: the file itself.
class OpenConfigIntent extends Intent {
  const OpenConfigIntent();
}

/// A9 D33 ⌘⇧P / Ctrl+Shift+P.
class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}

/// A9 D32: the shortcut editor (no default chord).
class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

/// A11 D24: the first-run tour again (no default chord).
class ShowTourIntent extends Intent {
  const ShowTourIntent();
}

/// A11 D23: "What's new" for the running version (no default chord).
class ShowWhatsNewIntent extends Intent {
  const ShowWhatsNewIntent();
}

/// A12 D20: "Check for updates" (no default chord): opens Settings on the
/// row that shows the answer.
class CheckForUpdatesIntent extends Intent {
  const CheckForUpdatesIntent();
}

/// A9 D36: the problems panel (no default chord).
class ShowConfigProblemsIntent extends Intent {
  const ShowConfigProblemsIntent();
}

/// A9 D35 `run_command:<name>`.
class RunUserCommandIntent extends Intent {
  const RunUserCommandIntent(this.name);
  final String name;
}

/// A9 D31 `text:` / `csi:` / `esc:` — already decoded.
class SendTextIntent extends Intent {
  const SendTextIntent(this.text);
  final String text;
}

/// A9 D22 `ignore`: the key is swallowed.
class IgnoreKeyIntent extends Intent {
  const IgnoreKeyIntent();
}

/// A8 D41 `ssh_connect` (⌘⇧K / Ctrl+Shift+K): "Connect to a server", SSH
/// tab.
class OpenSshConnectIntent extends Intent {
  const OpenSshConnectIntent();
}

/// A8 D41 `tmux_attach` (no default chord): the same dialog, tmux tab.
class OpenTmuxAttachIntent extends Intent {
  const OpenTmuxAttachIntent();
}

/// A11 D13 `toggle_copy_mode` (⌘⇧M / Ctrl+Shift+M).
class ToggleCopyModeIntent extends Intent {
  const ToggleCopyModeIntent();
}

/// A11 D19 `increase_workspace_font_size[:N]`, `decrease_…`,
/// `reset_workspace_font_size`: [step] points more (negative: fewer) for the
/// workspace of the selected tab, or back to the global size with [reset].
class WorkspaceFontIntent extends Intent {
  const WorkspaceFontIntent(this.step, {this.reset = false});
  final double step;
  final bool reset;
}

/// A11 D14 `reopen_closed` (⌘⇧T / Ctrl+Shift+Alt+T).
class ReopenClosedIntent extends Intent {
  const ReopenClosedIntent();
}

/// A11 D18 `toggle_pin_tab` (no default key): pins or unpins the selected tab.
class TogglePinTabIntent extends Intent {
  const TogglePinTabIntent();
}

/// A11 D20 `swap_split:<dir>` (no default key).
class SwapPaneIntent extends Intent {
  const SwapPaneIntent(this.direction);
  final PaneDirection direction;
}

/// A11 D20 `break_pane` (no default key): the focused pane becomes a tab.
class BreakPaneIntent extends Intent {
  const BreakPaneIntent();
}

/// A11 D20 `join_pane:<n>` (no default key) and the menu / palette entries
/// "Move pane to tab": the focused pane joins tab [tabId], or the [position]-th
/// tab of the sidebar (1-based).
class JoinPaneIntent extends Intent {
  const JoinPaneIntent({this.tabId, this.position});
  final int? tabId;
  final int? position;
}

/// A11 D20 (palette "Move tab to {workspace}"): the selected tab goes to
/// workspace [workspaceId].
class MoveTabToWorkspaceIntent extends Intent {
  const MoveTabToWorkspaceIntent(this.workspaceId);
  final String workspaceId;
}

/// A11 D21 `search_all` (⌘⇧F / Ctrl+Shift+Alt+F).
class SearchAllIntent extends Intent {
  const SearchAllIntent();
}

/// A11 D15 `focus_history:back|forward` (⌘⌃[ / ⌘⌃], Ctrl+Alt+[ / ]).
class FocusHistoryIntent extends Intent {
  const FocusHistoryIntent({required this.back});
  final bool back;
}
