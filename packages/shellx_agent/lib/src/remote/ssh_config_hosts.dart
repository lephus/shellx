import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ssh_target.dart';

/// A8 D6.
const int kMaxConfigHosts = 256;
const int _maxConfigBytes = 1024 * 1024;
const int _maxIncludeDepth = 4;

final class SshConfigFile {
  const SshConfigFile({required this.hosts, required this.includes});

  /// `Host` names without `*`, `?`, `!` that [SshTarget.parse] accepts.
  final List<String> hosts;

  /// `Include` values as written.
  final List<String> includes;
}

final _keyword = RegExp(r'^([A-Za-z]+)(?:\s*=\s*|\s+)(.*)$');
final _pattern = RegExp(r'[*?!]');

SshConfigFile parseSshConfig(String text) {
  final hosts = <String>[];
  final includes = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = _keyword.firstMatch(line);
    if (match == null) continue;
    final values = _words(match[2]!);
    switch (match[1]!.toLowerCase()) {
      case 'host':
        for (final value in values) {
          if (value.startsWith('#')) break;
          if (_pattern.hasMatch(value)) continue;
          if (SshTarget.parse(value) != null) hosts.add(value);
        }
      case 'include':
        includes.addAll(values);
    }
  }
  return SshConfigFile(hosts: hosts, includes: includes);
}

/// Whitespace-separated words; `"…"` keeps spaces (ssh_config(5)).
List<String> _words(String text) {
  final words = <String>[];
  final current = StringBuffer();
  var quoted = false;
  var started = false;
  for (final ch in text.split('')) {
    if (ch == '"') {
      quoted = !quoted;
      started = true;
      continue;
    }
    if (!quoted && (ch == ' ' || ch == '\t')) {
      if (started) {
        words.add(current.toString());
        current.clear();
        started = false;
      }
      continue;
    }
    current.write(ch);
    started = true;
  }
  if (started) words.add(current.toString());
  return words;
}

/// Every usable `Host` name of `~/.ssh/config` and what it includes, in
/// order, once each, at most [kMaxConfigHosts]. Unreadable, missing or
/// oversized files are skipped silently (never logged: paths are private).
Future<List<String>> readSshConfigHosts({
  required String home,
  bool windows = false,
  Future<String?> Function(String path)? read,
  Future<List<String>> Function(String directory)? list,
}) async {
  final sep = windows ? r'\' : '/';
  final sshDir = '$home$sep.ssh';
  final readFile = read ?? _readSmallFile;
  final listDir = list ?? _listNames;
  final hosts = <String>{};
  final seen = <String>{};

  Future<void> visit(String path, int depth) async {
    if (depth > _maxIncludeDepth || hosts.length >= kMaxConfigHosts) return;
    if (!seen.add(path)) return;
    final text = await readFile(path);
    if (text == null) return;
    final file = parseSshConfig(text);
    for (final host in file.hosts) {
      if (hosts.length >= kMaxConfigHosts) return;
      hosts.add(host);
    }
    for (final pattern in file.includes) {
      final paths = await _expand(
        pattern,
        home: home,
        sshDir: sshDir,
        sep: sep,
        list: listDir,
      );
      for (final included in paths) {
        await visit(included, depth + 1);
      }
    }
  }

  await visit('$sshDir${sep}config', 0);
  return hosts.toList();
}

Future<List<String>> _expand(
  String pattern, {
  required String home,
  required String sshDir,
  required String sep,
  required Future<List<String>> Function(String directory) list,
}) async {
  var path = pattern;
  if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
    path = '$home${path.substring(1)}';
  }
  final absolute =
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  if (!absolute) path = '$sshDir$sep$path';
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  if (cut < 0) return const [];
  final directory = path.substring(0, cut);
  final name = path.substring(cut + 1);
  if (!name.contains(RegExp(r'[*?]'))) return [path];
  final glob = RegExp(
    '^${name.split('').map((c) => switch (c) {
      '*' => '.*',
      '?' => '.',
      _ => RegExp.escape(c),
    }).join()}\$',
  );
  final names = (await list(directory)).where(glob.hasMatch).toList()..sort();
  return [for (final n in names) '$directory${path[cut]}$n'];
}

Future<String?> _readSmallFile(String path) async {
  try {
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, _maxConfigBytes + 1)) {
      bytes.add(chunk);
    }
    if (bytes.length > _maxConfigBytes) return null;
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  } on Object {
    return null;
  }
}

Future<List<String>> _listNames(String directory) async {
  try {
    return [
      await for (final entry in Directory(directory).list())
        if (entry is File) entry.uri.pathSegments.last,
    ];
  } on Object {
    return const [];
  }
}
