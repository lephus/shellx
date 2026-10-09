import 'dart:io';

/// How long a search result (found or not) is kept.
const Duration kGhLocatorTtl = Duration(minutes: 5);

/// A12 D16: where the GitHub CLI is. Only `PATH` (absolute entries) and the
/// folders the installers use are searched; never the working directory,
/// never a `.cmd` or `.bat` (they need a shell).
final class GhLocator {
  GhLocator({
    required this.path,
    required this.home,
    required this.windows,
    this.programFiles,
    Future<bool> Function(String path)? isExecutable,
    DateTime Function()? now,
  }) : _isExecutable = isExecutable ?? _ioIsExecutable,
       _now = now ?? DateTime.now;

  /// The `PATH` variable as the app was started with.
  final String path;
  final String home;
  final bool windows;

  /// `%ProgramFiles%` (Windows).
  final String? programFiles;
  final Future<bool> Function(String path) _isExecutable;
  final DateTime Function() _now;

  String? _found;
  DateTime? _at;

  bool _absolute(String dir) =>
      windows ? RegExp(r'^[A-Za-z]:[\\/]').hasMatch(dir) : dir.startsWith('/');

  List<String> _folders() {
    final sep = windows ? r'\' : '/';
    final dirs = <String>[
      for (final d in path.split(windows ? ';' : ':'))
        if (d.isNotEmpty && _absolute(d)) d,
    ];
    if (windows) {
      final pf = programFiles;
      if (pf != null && pf.isNotEmpty) dirs.add('$pf${sep}GitHub CLI');
    } else {
      dirs.addAll(['/opt/homebrew/bin', '/usr/local/bin']);
      if (home.isNotEmpty) dirs.add('$home/.local/bin');
    }
    return dirs;
  }

  /// The full path of `gh`, or null. Cached for [kGhLocatorTtl].
  Future<String?> find() async {
    final at = _at;
    if (at != null && _now().difference(at) < kGhLocatorTtl) return _found;
    final sep = windows ? r'\' : '/';
    final name = windows ? 'gh.exe' : 'gh';
    String? found;
    for (final dir in _folders()) {
      final candidate = dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
      if (await _isExecutable(candidate)) {
        found = candidate;
        break;
      }
    }
    _found = found;
    _at = _now();
    return found;
  }
}

Future<bool> _ioIsExecutable(String path) async {
  try {
    final stat = await FileStat.stat(path); // follows links (Homebrew's)
    if (stat.type != FileSystemEntityType.file) return false;
    return Platform.isWindows || (stat.mode & 0x49) != 0;
  } on Object {
    return false;
  }
}
