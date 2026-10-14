import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_gitignore.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';

/// A project in memory: its files ([files], path relative to [root] →
/// text), its restore points (V2-1a `Checkpoints`) and the reader the pane
/// uses (`AiProjectFiles`). Nothing touches the disk or git.
final class FakeProject implements Checkpoints, AiProjectFiles {
  FakeProject(this.root, Map<String, String> files) : files = {...files};

  final String root;

  /// The project as it is now.
  final Map<String, String> files;

  /// Runs right after each restore point is taken, with its ref
  /// (`<session>/<turn>`): what the agent does during that turn.
  void Function(String ref)? onSnapshot;

  /// Every restore: (commit, paths).
  final restored = <(String, List<String>)>[];

  final _trees = <String, Map<String, String>>{};
  var _n = 0;

  @override
  UndoOff? off;

  String _keep() {
    final tree = 't${_n++}';
    _trees[tree] = {...files};
    return tree;
  }

  @override
  Future<Checkpoint?> snapshot(String ref) async {
    final tree = _keep();
    onSnapshot?.call(ref);
    return Checkpoint(commit: 'c$tree', tree: tree);
  }

  @override
  Future<String?> currentTree() async => _keep();

  Map<String, String> _tree(String treeish) =>
      _trees[treeish.startsWith('c') ? treeish.substring(1) : treeish]!;

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) async {
    final from = _tree(fromTree);
    final to = toTree == null ? files : _tree(toTree);
    int lines(String? s) =>
        s == null || s.isEmpty ? 0 : '\n'.allMatches(s).length;
    return [
      for (final path in {...from.keys, ...to.keys}.toList()..sort())
        if (from[path] != to[path])
          FileChange(
            path: path,
            kind: !from.containsKey(path)
                ? ChangeKind.added
                : !to.containsKey(path)
                ? ChangeKind.deleted
                : ChangeKind.modified,
            added: lines(to[path]),
            removed: lines(from[path]),
          ),
    ];
  }

  @override
  Future<Set<String>> changedSince(String tree) async {
    final then = _tree(tree);
    return {
      for (final path in {...then.keys, ...files.keys})
        if (then[path] != files[path]) path,
    };
  }

  @override
  Future<List<int>?> fileAt(String treeish, String path) async {
    final text = _tree(treeish)[path];
    return text == null ? null : utf8.encode(text);
  }

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {
    final then = _tree(treeish);
    final list = [...paths];
    for (final path in list) {
      final text = then[path];
      if (text == null) {
        files.remove(path);
      } else {
        files[path] = text;
      }
    }
    restored.add((treeish, list));
  }

  @override
  Future<AiFileContent> read(String path) async {
    final text = files[p.relative(path, from: root)];
    return text == null ? const AiFileMissing() : AiFileText(text);
  }

  /// The project's `.gitignore` files, as the disk version reads them.
  AiGitIgnore _rules() {
    final rules = AiGitIgnore();
    for (final MapEntry(:key, :value) in files.entries) {
      if (key == '.gitignore') rules.add('', value);
      if (key.endsWith('/.gitignore')) {
        rules.add(key.substring(0, key.length - '/.gitignore'.length), value);
      }
    }
    return rules;
  }

  bool _inIgnoredFolder(AiGitIgnore rules, String path) {
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      if (rules.ignores(parts.take(i).join('/'), dir: true)) return true;
    }
    return false;
  }

  @override
  Future<List<AiDirEntry>> list(String root, String dir) async {
    final rules = _rules();
    final prefix = dir.isEmpty ? '' : '$dir/';
    final dirs = <String>{};
    final names = <String>{};
    for (final path in files.keys) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      slash < 0 ? names.add(rest) : dirs.add(rest.substring(0, slash));
    }
    AiDirEntry entry(String name, {required bool dir}) {
      final rel = '$prefix$name';
      return AiDirEntry(
        rel,
        dir: dir,
        ignored: _inIgnoredFolder(rules, rel) || rules.ignores(rel, dir: dir),
      );
    }

    return [
      for (final d in dirs.toList()..sort()) entry(d, dir: true),
      for (final n in names.toList()..sort()) entry(n, dir: false),
    ];
  }

  @override
  Future<List<String>> index(String root) async {
    final rules = _rules();
    return [
      for (final path in files.keys.toList()..sort())
        if (!_inIgnoredFolder(rules, path) && !rules.ignores(path, dir: false))
          path,
    ];
  }
}
