import 'dart:io';

import 'package:path/path.dart' as p;

/// A path that exists, absolute and normalised.
final class ResolvedPath {
  const ResolvedPath(this.path, {required this.isDirectory});
  final String path;
  final bool isDirectory;

  /// Never shows the path (A10 §5).
  @override
  String toString() => 'ResolvedPath(…)';
}

/// What [LinkResolver] asks the file system.
typedef EntityTypeOf = Future<FileSystemEntityType> Function(String path);

/// A10 D7: turns a path found in the terminal into one that exists on this
/// computer. `~/` is [home], a relative one is [cwd]'s (null cwd: no
/// answer), `..` is normalised away, a symbolic link is followed. Answers
/// are remembered for [ttl] (hovering asks again and again).
final class LinkResolver {
  LinkResolver({
    required this.home,
    required this.windows,
    EntityTypeOf? typeOf,
    DateTime Function()? now,
    this.ttl = const Duration(seconds: 2),
    this.maxEntries = 64,
  }) : _typeOf =
           typeOf ?? ((path) => FileSystemEntity.type(path, followLinks: true)),
       _now = now ?? DateTime.now;

  final String? home;
  final bool windows;
  final EntityTypeOf _typeOf;
  final DateTime Function() _now;
  final Duration ttl;
  final int maxEntries;
  final _cache = <String, (DateTime, ResolvedPath?)>{};

  static final RegExp _control = RegExp(r'[\u0000-\u001f\u007f]');

  p.Context get _ctx => windows ? p.windows : p.posix;

  /// The absolute form of [target] before any file system check; null when
  /// it cannot be made one.
  String? absoluteOf(String target, {String? cwd}) {
    if (target.isEmpty || _control.hasMatch(target)) return null;
    String joined;
    if (target == '~' || target.startsWith('~/')) {
      final h = home;
      if (h == null || h.isEmpty) return null;
      joined = target == '~' ? h : _ctx.join(h, target.substring(2));
    } else if (_ctx.isAbsolute(target)) {
      joined = target;
    } else {
      if (cwd == null || cwd.isEmpty || !_ctx.isAbsolute(cwd)) return null;
      joined = _ctx.join(cwd, target);
    }
    final normal = _ctx.normalize(joined);
    // Never an option for `open` / `explorer`, whatever came in.
    return _ctx.isAbsolute(normal) ? normal : null;
  }

  /// The existing file or folder [target] means, or null.
  Future<ResolvedPath?> resolve(String target, {String? cwd}) async {
    final absolute = absoluteOf(target, cwd: cwd);
    if (absolute == null) return null;
    final at = _now();
    final hit = _cache[absolute];
    if (hit != null && at.difference(hit.$1) < ttl) return hit.$2;
    ResolvedPath? found;
    try {
      final type = await _typeOf(absolute);
      if (type != FileSystemEntityType.notFound) {
        found = ResolvedPath(
          absolute,
          isDirectory: type == FileSystemEntityType.directory,
        );
      }
    } on Object {
      found = null; // unreadable is "not there"
    }
    if (_cache.length >= maxEntries) _cache.remove(_cache.keys.first);
    _cache[absolute] = (at, found);
    return found;
  }
}
