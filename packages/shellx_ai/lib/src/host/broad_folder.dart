import 'package:path/path.dart' as p;

/// Whether [folder] is too broad to be a project: a filesystem or drive root,
/// the home folder, or a folder above it (V2-1 final review I-1). Undo
/// snapshots and the `@` index would crawl all of it, and on macOS the
/// crawl raises privacy prompts for Desktop, Documents and Downloads.
///
/// [home] is the user's home folder (`HOME`, or `USERPROFILE` on Windows);
/// null or relative means only roots count. Paths compare after
/// normalisation, without case on Windows.
bool isBroadFolder(String folder, {String? home, required bool isWindows}) {
  final ctx = isWindows ? p.windows : p.posix;
  String norm(String path) {
    final n = ctx.normalize(path);
    return isWindows ? n.toLowerCase() : n;
  }

  if (folder.isEmpty || !ctx.isAbsolute(folder)) return false;
  final f = norm(folder);
  final root = ctx.rootPrefix(f);
  // `/`, `C:\`, `\\server\share\`: the root itself (with or without its
  // trailing separator).
  if (f == root || '$f${ctx.separator}' == root) return true;
  if (home == null || home.isEmpty || !ctx.isAbsolute(home)) return false;
  final h = norm(home);
  return f == h || ctx.isWithin(f, h);
}
