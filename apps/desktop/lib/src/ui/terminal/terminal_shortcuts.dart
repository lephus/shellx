import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../config/keybind_actions.dart';
import '../../config/keybindings.dart';
import 'terminal_intents.dart';

export 'terminal_intents.dart';

KeyBindings _table(KeyBindings? bindings, TargetPlatform platform) =>
    bindings ?? KeyBindings.defaults(platform);

/// Spec criterion 2 and UI §3.6: the workspace's `Shortcuts` (focus in
/// the sidebar, the strip, "Open new tab"). Built from the effective
/// bindings (A9 D24; null = the defaults, today's table exactly). Regions
/// cycle with F6 / Shift+F6, fixed here (A9 D25): outside the terminal
/// they always cycle regions; Ctrl+F6 / Ctrl+Shift+F6 are bindings.
Map<ShortcutActivator, Intent> desktopShortcuts(
  TargetPlatform platform, {
  KeyBindings? bindings,
}) => {
  ..._table(bindings, platform).map(KeyScope.window),
  const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
  const SingleActivator(LogicalKeyboardKey.f6, shift: true):
      const PreviousRegionIntent(),
};

/// What every `TerminalView` gets (xterm would otherwise consume Ctrl+Tab,
/// Ctrl+Shift+T… as terminal input): the window bindings. Plain F6 /
/// Shift+F6 are left out on purpose (controller ruling): they reach the
/// shell, where htop sorts and mc moves; Ctrl+F6 / Ctrl+Shift+F6 leave
/// the terminal instead.
Map<ShortcutActivator, Intent> terminalViewShortcuts(
  TargetPlatform platform, {
  KeyBindings? bindings,
}) => _table(bindings, platform).map(KeyScope.window);
