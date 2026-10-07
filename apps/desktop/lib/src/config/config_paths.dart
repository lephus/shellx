import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

final RegExp _drive = RegExp(r'^[A-Za-z]:[\\/]');
final RegExp _unc = RegExp(r'^\\\\([^\\/]+)\\([^\\/]+)(?:[\\/]|$)');

/// The one absolute-path rule of the config code (A9 D3, D6, D21, D39):
/// `XDG_CONFIG_HOME`, `APPDATA`, the home directory, `config-file` targets
/// after `~` expansion and `working-directory` all pass through it. The
/// Rust CLI (Task 13) mirrors the table in `config_paths_test`.
///
/// POSIX: starts with `/`. Windows: a drive root `X:\` / `X:/` or a UNC
/// share `\\server\share`; root-relative (`\x`, `/x`), drive-relative
/// (`C:x`) and the device namespaces (`\\.\`, `\\?\`) are refused.
bool isAbsoluteConfigPath(String path, {required bool windows}) {
  if (!windows) return path.startsWith('/');
  if (_drive.hasMatch(path)) return true;
  final unc = _unc.firstMatch(path);
  if (unc == null) return false;
  final server = unc.group(1)!;
  return server != '.' && server != '?';
}

/// Where the configuration lives (A9 spec D3, D4, D13). Pinned by
/// `config_paths_test`; the Rust CLI mirrors it (Task 13).
@immutable
final class ConfigPaths {
  const ConfigPaths({
    required this.shellx,
    required this.ghostty,
    required this.themeDirs,
    required this.home,
    required this.windows,
  });

  final String shellx;

  /// Read in this order; a later file overrides an earlier one (D4).
  final List<String> ghostty;
  final List<String> themeDirs;
  final String home;
  final bool windows;

  String get shellxDir => (windows ? p.windows : p.posix).dirname(shellx);
}

/// D3/D4. [home] must pass [isAbsoluteConfigPath] (ArgumentError
/// otherwise); an `XDG_CONFIG_HOME` or `APPDATA` that does not is ignored.
ConfigPaths configPathsFor({
  required bool windows,
  required Map<String, String> env,
  required String home,
}) {
  if (!isAbsoluteConfigPath(home, windows: windows)) {
    throw ArgumentError.value(home, 'home', 'is not an absolute path');
  }
  final ctx = windows ? p.windows : p.posix;
  String? absolute(String name) {
    final value = env[name];
    return value != null && isAbsoluteConfigPath(value, windows: windows)
        ? value
        : null;
  }

  final xdgBase = absolute('XDG_CONFIG_HOME');
  final shellxDir = xdgBase != null
      ? ctx.join(xdgBase, 'shellx')
      : windows
      ? ctx.join(
          absolute('APPDATA') ?? ctx.join(home, 'AppData', 'Roaming'),
          'ShellX',
        )
      : ctx.join(home, '.config', 'shellx');
  final ghosttyXdg = ctx.join(xdgBase ?? ctx.join(home, '.config'), 'ghostty');
  final macGhostty = ctx.join(
    home,
    'Library',
    'Application Support',
    'com.mitchellh.ghostty',
  );
  // Normalised: `D:/cfg` and `D:\cfg\` print as `D:\cfg\…`.
  String at(String dir, String name) => ctx.normalize(ctx.join(dir, name));
  return ConfigPaths(
    shellx: at(shellxDir, 'config'),
    ghostty: [
      at(ghosttyXdg, 'config.ghostty'),
      at(ghosttyXdg, 'config'),
      if (!windows) ...[
        at(macGhostty, 'config.ghostty'),
        at(macGhostty, 'config'),
      ],
    ],
    themeDirs: [
      at(shellxDir, 'themes'),
      at(ghosttyXdg, 'themes'),
      if (!windows) ...[
        at(macGhostty, 'themes'),
        '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
      ],
    ],
    home: home,
    windows: windows,
  );
}
