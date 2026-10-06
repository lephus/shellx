import 'package:flutter/foundation.dart';

/// macOS shows ⌘ shortcuts; Windows Ctrl+Shift (spec criterion 2). Labels
/// are built from the platform, never translated (UI §5).
bool get isMacDesktop => defaultTargetPlatform == TargetPlatform.macOS;

String newTabShortcutLabel() => isMacDesktop ? '⌘T' : 'Ctrl+Shift+T';
String closeTabShortcutLabel() => isMacDesktop ? '⌘W' : 'Ctrl+Shift+W';
