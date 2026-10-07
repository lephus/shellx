import 'package:flutter/foundation.dart';

import '../../config/keybind_actions.dart';
import '../../config/keybindings.dart';

/// macOS shows ⌘ shortcuts; Windows Ctrl+Shift (spec criterion 2). Labels
/// are built from the platform, never translated (UI §5).
bool get isMacDesktop => defaultTargetPlatform == TargetPlatform.macOS;

KeyBindings get _bindings =>
    labelBindings ?? KeyBindings.defaults(defaultTargetPlatform);

/// A9 D29: the first trigger in effect; null when the action is unbound
/// (callers then show no hint). A widget that stays on screen watches
/// `shellxConfigProvider.select((s) => s.bindings)` so it rebuilds, and so
/// re-reads this, after a reload.
String? actionShortcutLabel(KeyAction action) => _bindings.labelOf(action);

String? newTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_tab'));
String? closeTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('close_surface'));
String? copyShortcutLabel() =>
    actionShortcutLabel(const KeyAction('copy_to_clipboard'));
String? pasteShortcutLabel() =>
    actionShortcutLabel(const KeyAction('paste_from_clipboard'));
String? selectAllShortcutLabel() =>
    actionShortcutLabel(const KeyAction('select_all'));
String? newWorkspaceShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_workspace'));
String? sshConnectShortcutLabel() =>
    actionShortcutLabel(const KeyAction('ssh_connect'));
String? tmuxAttachShortcutLabel() =>
    actionShortcutLabel(const KeyAction('tmux_attach'));
String? notificationsShortcutLabel() =>
    actionShortcutLabel(const KeyAction('toggle_notifications'));
String? nextUnreadShortcutLabel() =>
    actionShortcutLabel(const KeyAction('jump_to_unread'));
String? splitRightShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_split', 'right'));
String? splitDownShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_split', 'down'));
String? zoomPaneShortcutLabel() =>
    actionShortcutLabel(const KeyAction('toggle_split_zoom'));
String? equalizePanesShortcutLabel() =>
    actionShortcutLabel(const KeyAction('equalize_splits'));
String? closePaneShortcutLabel() => closeTabShortcutLabel();

/// A tooltip or caption with its hint: [message] gets the label, or an
/// empty string when the action is unbound, and the gap that was left for
/// the hint goes (D29: never a hint for an unbound action).
String withShortcut(String Function(String shortcut) message, String? label) =>
    message(label ?? '').trimRight();

// Sidebar-local keys (A2), not configurable.
String renameShortcutLabel() => 'F2';
String moveUpShortcutLabel() => isMacDesktop ? '⌥↑' : 'Alt+↑';
String moveDownShortcutLabel() => isMacDesktop ? '⌥↓' : 'Alt+↓';
