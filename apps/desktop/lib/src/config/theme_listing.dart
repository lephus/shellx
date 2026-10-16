import 'package:flutter/foundation.dart';

import 'config_files.dart';
import 'config_paths.dart';

/// Themes listed at most (a directory with more is cut).
const int kThemeListMax = 600;

/// One theme the user can pick: the name that goes after `theme =` and the
/// folder it was found in (empty for the built-in palette).
@immutable
final class ThemeEntry {
  const ThemeEntry(this.name, this.source);
  final String name;
  final String source;

  /// The built-in palette, first in every list.
  static const ThemeEntry builtIn = ThemeEntry('ShellX', '');

  @override
  bool operator ==(Object other) =>
      other is ThemeEntry && other.name == name && other.source == source;

  @override
  int get hashCode => Object.hash(name, source);

  @override
  String toString() => 'ThemeEntry($name)';
}

bool _usable(String name) =>
    name.isNotEmpty &&
    !name.startsWith('.') &&
    !name.contains('/') &&
    !name.contains(r'\') &&
    !name.contains('\x00') &&
    name.toLowerCase() != 'shellx';

/// The themes of every directory of [ConfigPaths.themeDirs] (A9 D13), the
/// built-in `ShellX` first, the others by name without regard to case. A
/// name with a separator or NUL is dropped (a theme never leaves its
/// directory), as are dotfiles; the first directory wins on an exact
/// duplicate; a directory that is missing or can't be read is skipped.
Future<List<ThemeEntry>> listThemes(ConfigPaths paths, ConfigFs fs) async {
  final seen = <String>{};
  final found = <ThemeEntry>[];
  for (final dir in paths.themeDirs) {
    List<String> names;
    try {
      names = await fs.list(dir);
    } on Object {
      continue;
    }
    for (final name in names) {
      if (!_usable(name) || !seen.add(name)) continue;
      found.add(ThemeEntry(name, dir));
      if (found.length >= kThemeListMax) break;
    }
    if (found.length >= kThemeListMax) break;
  }
  found.sort((a, b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return [ThemeEntry.builtIn, ...found];
}
