import 'package:flutter/foundation.dart';

/// macOS shows ⌘ shortcuts; Windows Ctrl+Shift (spec criterion 2). Labels
/// are built from the platform, never translated (UI §5).
bool get isMacDesktop => defaultTargetPlatform == TargetPlatform.macOS;

String newTabShortcutLabel() => isMacDesktop ? '⌘T' : 'Ctrl+Shift+T';
String closeTabShortcutLabel() => isMacDesktop ? '⌘W' : 'Ctrl+Shift+W';
String copyShortcutLabel() => isMacDesktop ? '⌘C' : 'Ctrl+Shift+C';
String pasteShortcutLabel() => isMacDesktop ? '⌘V' : 'Ctrl+Shift+V';
String selectAllShortcutLabel() => isMacDesktop ? '⌘A' : 'Ctrl+Shift+A';

String renameShortcutLabel() => 'F2';
String moveUpShortcutLabel() => isMacDesktop ? '⌥↑' : 'Alt+↑';
String moveDownShortcutLabel() => isMacDesktop ? '⌥↓' : 'Alt+↓';
String newWorkspaceShortcutLabel() => isMacDesktop ? '⌘⇧N' : 'Ctrl+Shift+N';
String notificationsShortcutLabel() => isMacDesktop ? '⌘⇧I' : 'Ctrl+Shift+I';
String nextUnreadShortcutLabel() => isMacDesktop ? '⌘⇧U' : 'Ctrl+Shift+U';

String splitRightShortcutLabel() => isMacDesktop ? '⌘D' : 'Ctrl+Shift+D';
String splitDownShortcutLabel() => isMacDesktop ? '⌘⇧D' : 'Ctrl+Shift+Alt+D';
String zoomPaneShortcutLabel() => isMacDesktop ? '⌘⇧↩' : 'Ctrl+Shift+Enter';
String equalizePanesShortcutLabel() =>
    isMacDesktop ? '⌘⌃=' : 'Ctrl+Shift+Alt+=';
String closePaneShortcutLabel() => closeTabShortcutLabel();
