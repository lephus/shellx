import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../terminal/pane_layout.dart';

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

// Not const: LogicalKeyboardKey overrides ==, so it cannot key a const map.
final _arrows = {
  LogicalKeyboardKey.arrowLeft: PaneDirection.left,
  LogicalKeyboardKey.arrowRight: PaneDirection.right,
  LogicalKeyboardKey.arrowUp: PaneDirection.up,
  LogicalKeyboardKey.arrowDown: PaneDirection.down,
};

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

class FontBiggerIntent extends Intent {
  const FontBiggerIntent();
}

class FontSmallerIntent extends Intent {
  const FontSmallerIntent();
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

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Spec criterion 2 and UI §3.6: the workspace's `Shortcuts` (focus in
/// the sidebar, the strip, "Open new tab"). Windows tab-number and font
/// chords follow Windows Terminal, which leaves Ctrl+digit to the shell.
/// Regions cycle with F6 / Shift+F6 and, so one chord works everywhere,
/// Ctrl+F6 / Ctrl+Shift+F6.
Map<ShortcutActivator, Intent> desktopShortcuts(TargetPlatform platform) => {
  ..._windowShortcuts(platform),
  const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
  const SingleActivator(LogicalKeyboardKey.f6, shift: true):
      const PreviousRegionIntent(),
};

/// What every `TerminalView` gets (xterm would otherwise consume Ctrl+Tab,
/// Ctrl+Shift+T… as terminal input). Plain F6 / Shift+F6 are left out on
/// purpose (controller ruling): they reach the shell, where htop sorts and
/// mc moves; Ctrl+F6 / Ctrl+Shift+F6 leave the terminal instead.
Map<ShortcutActivator, Intent> terminalViewShortcuts(TargetPlatform platform) =>
    _windowShortcuts(platform);

Map<ShortcutActivator, Intent> _windowShortcuts(TargetPlatform platform) {
  final mac = platform == TargetPlatform.macOS;
  SingleActivator primary(
    LogicalKeyboardKey key, {
    bool includeRepeats = true,
  }) => mac
      ? SingleActivator(key, meta: true, includeRepeats: includeRepeats)
      : SingleActivator(
          key,
          control: true,
          shift: true,
          includeRepeats: includeRepeats,
        );
  // ⌘⇧ / Ctrl+Shift, without key repeat (Windows: the same chord as
  // [primary]; macOS adds ⇧ so ⌘I / ⌘U stay free).
  SingleActivator shifted(LogicalKeyboardKey key) => SingleActivator(
    key,
    meta: mac,
    control: !mac,
    shift: true,
    includeRepeats: false,
  );
  SingleActivator font(LogicalKeyboardKey key, {bool shift = false}) => mac
      ? SingleActivator(key, meta: true, shift: shift)
      : SingleActivator(key, control: true, shift: shift);
  return {
    // Holding ⌘T / ⌘W must not open (or close) a tab per key repeat.
    primary(LogicalKeyboardKey.keyT, includeRepeats: false):
        const NewTabIntent(),
    primary(LogicalKeyboardKey.keyW, includeRepeats: false):
        const CloseTabIntent(),
    (mac
            ? const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
                shift: true,
                includeRepeats: false,
              )
            : const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
                shift: true,
                includeRepeats: false,
              )):
        const NewWorkspaceIntent(),
    // A4 N5: held down, the panel must not flicker open/closed, nor next
    // unread run through every tab.
    shifted(LogicalKeyboardKey.keyI): const ToggleNotificationsPanelIntent(),
    shifted(LogicalKeyboardKey.keyU): const JumpToNextUnreadIntent(),
    primary(LogicalKeyboardKey.keyC): const CopySelectionIntent(),
    primary(LogicalKeyboardKey.keyV): const PasteClipboardIntent(),
    // ⌘A / Ctrl+Shift+A (Windows Terminal's), like the terminal's menu.
    primary(LogicalKeyboardKey.keyA): const SelectAllIntent(),
    for (var i = 0; i < _digits.length; i++)
      (mac
              ? SingleActivator(_digits[i], meta: true)
              : SingleActivator(_digits[i], control: true, alt: true)):
          SelectTabIntent(i + 1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true):
        const NextTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
        const PreviousTabIntent(),
    // A3 P3 / D20. Windows chords with Alt are guarded against AltGr in
    // the actions (Task 7), like Ctrl+Alt+digit.
    SingleActivator(
      LogicalKeyboardKey.keyD,
      meta: mac,
      control: !mac,
      shift: !mac,
      includeRepeats: false,
    ): const SplitPaneIntent(
      SplitAxis.row,
    ),
    SingleActivator(
      LogicalKeyboardKey.keyD,
      meta: mac,
      control: !mac,
      shift: true,
      alt: !mac,
      includeRepeats: false,
    ): const SplitPaneIntent(
      SplitAxis.column,
    ),
    for (final MapEntry(key: key, value: direction) in _arrows.entries) ...{
      SingleActivator(key, meta: mac, control: !mac, alt: true):
          FocusPaneIntent(direction),
      SingleActivator(key, meta: mac, control: true, shift: !mac, alt: !mac):
          ResizePaneIntent(direction),
    },
    for (final enter in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ])
      SingleActivator(
        enter,
        meta: mac,
        control: !mac,
        shift: true,
        includeRepeats: false,
      ): const TogglePaneZoomIntent(),
    SingleActivator(
      LogicalKeyboardKey.equal,
      meta: mac,
      control: true,
      shift: !mac,
      alt: !mac,
      includeRepeats: false,
    ): const EqualizePanesIntent(),
    font(LogicalKeyboardKey.equal): const FontBiggerIntent(),
    // ⌘+ is ⌘⇧= on a US layout; `add` is the "+" key of layouts that have
    // one (German…), and the keypad.
    font(LogicalKeyboardKey.equal, shift: true): const FontBiggerIntent(),
    font(LogicalKeyboardKey.add): const FontBiggerIntent(),
    font(LogicalKeyboardKey.numpadAdd): const FontBiggerIntent(),
    font(LogicalKeyboardKey.minus): const FontSmallerIntent(),
    font(LogicalKeyboardKey.numpadSubtract): const FontSmallerIntent(),
    font(LogicalKeyboardKey.digit0): const FontResetIntent(),
    font(LogicalKeyboardKey.numpad0): const FontResetIntent(),
    const SingleActivator(LogicalKeyboardKey.f6, control: true):
        const NextRegionIntent(),
    const SingleActivator(LogicalKeyboardKey.f6, control: true, shift: true):
        const PreviousRegionIntent(),
  };
}
