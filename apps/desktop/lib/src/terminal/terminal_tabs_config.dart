part of 'terminal_tabs.dart';

/// A9 D35: a command with no live terminal to run in (neutral).
final class NoTerminalForCommandNotice extends TabNotice {
  const NoTerminalForCommandNotice();
}

/// A9 D37: the configuration file could not be opened (error).
final class ConfigOpenFailedNotice extends TabNotice {
  const ConfigOpenFailedNotice(this.path);
  final String path;
}

// A9 D21: where a new tab's shell starts. Kept apart from the tab list.
extension TerminalTabsConfig on TerminalTabs {
  /// Null = home. A path or `inherit`'s directory is checked by the agent
  /// like every cwd (A3 D17: unusable falls back to home).
  String? newTabCwd() {
    final wd = _ref.read(shellxConfigProvider).config.workingDirectory;
    return switch (wd.kind) {
      WorkingDirectoryKind.home => null,
      WorkingDirectoryKind.path => wd.path,
      WorkingDirectoryKind.inherit => _state.selected?.focused.cwd,
    };
  }
}
