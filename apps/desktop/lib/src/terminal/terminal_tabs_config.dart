part of 'terminal_tabs.dart';

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
