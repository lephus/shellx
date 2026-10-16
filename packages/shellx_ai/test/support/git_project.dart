import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';

/// A temp project and a shadow repo path, cleaned up by the caller.
final class GitProject {
  GitProject() : tmp = Directory.systemTemp.createTempSync('ckpt') {
    Directory(project).createSync();
  }

  final Directory tmp;

  String get project => p.join(tmp.path, 'project');
  String get gitDir => p.join(tmp.path, 'support', 'ai', 'checkpoints', 'abc');

  void put(String rel, Object content) {
    final f = File(p.join(project, rel))..parent.createSync(recursive: true);
    content is String
        ? f.writeAsStringSync(content)
        : f.writeAsBytesSync(content as List<int>);
  }

  List<int> bytes(String rel) => File(p.join(project, rel)).readAsBytesSync();
  bool exists(String rel) =>
      FileSystemEntity.typeSync(p.join(project, rel)) !=
      FileSystemEntityType.notFound;

  /// git in the project itself, as the user would run it.
  ProcessResult userGit(List<String> args, {String? dir}) =>
      Process.runSync('git', [
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@t.invalid',
        '-c',
        'commit.gpgSign=false',
        ...args,
      ], workingDirectory: dir ?? project);

  static Future<GitTool> git() async {
    final (tool, off) = await GitLocator().locate(
      LoginEnv(Platform.environment, source: LoginEnvSource.process),
    );
    if (tool == null) throw StateError('git is needed for these tests ($off)');
    return tool;
  }

  void dispose() => tmp.deleteSync(recursive: true);
}
