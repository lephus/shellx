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

/// A9 D32: a shortcut could not be saved (error): the file is as it was.
final class ConfigWriteFailedNotice extends TabNotice {
  const ConfigWriteFailedNotice(this.path);
  final String path;
}

/// A11 D5: the file changed under Settings (a hand edit); it was reloaded
/// and nothing was written (neutral).
final class SettingsFileChangedNotice extends TabNotice {
  const SettingsFileChangedNotice();
}

/// A11 D5: the managed block is damaged; Settings writes nothing (error).
final class SettingsFileDamagedNotice extends TabNotice {
  const SettingsFileDamagedNotice();
}

/// A11 D5: the file could not be written (locked, read-only, too large …).
final class SettingsFileUnwritableNotice extends TabNotice {
  const SettingsFileUnwritableNotice();
}

/// A9 D36: errors → error toast; warnings only → neutral.
final class ConfigProblemsNotice extends TabNotice {
  const ConfigProblemsNotice(this.count, {required this.hasErrors});
  final int count;
  final bool hasErrors;
}

/// A9 D9: a reload the user asked for found nothing wrong (neutral).
final class ConfigReloadedNotice extends TabNotice {
  const ConfigReloadedNotice();
}

/// A9 D4: the first time Ghostty's fonts/colours are used (neutral).
final class ConfigGhosttyNotice extends TabNotice {
  const ConfigGhosttyNotice();
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
      // A8: a folder on a server means nothing on this computer.
      WorkingDirectoryKind.inherit =>
        _state.selected?.focused.remote?.launch.host != null
            ? null
            : _state.selected?.focused.cwd,
    };
  }
}
