import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The exit code and output of a short helper command.
final class ProbeResult {
  const ProbeResult(this.exitCode, this.stdout);

  final int exitCode;
  final String stdout;
}

/// Runs a short helper (`node --version`, `git --version`, `xcode-select
/// -p`, `ps`); null when it cannot start or runs over its time.
typedef ProbeRunner =
    Future<ProbeResult?> Function(
      String executable,
      List<String> args, {
      Map<String, String>? environment,
    });

Future<ProbeResult?> runProbe(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      args,
      environment: environment,
      includeParentEnvironment: environment == null,
    );
  } on Object {
    return null;
  }
  unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
  unawaited(process.stderr.drain<void>());
  final out = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProbeResult(
      code,
      await out.timeout(const Duration(seconds: 1), onTimeout: () => ''),
    );
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
}

/// What the host asks the file system; faked in tests for both platforms.
abstract interface class FileProbe {
  bool isFile(String path);
  bool isExecutable(String path);
  String? read(String path);
}

final class RealFileProbe implements FileProbe {
  const RealFileProbe();

  @override
  bool isFile(String path) =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.file;

  @override
  bool isExecutable(String path) {
    if (Platform.isWindows) return isFile(path);
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
  }

  @override
  String? read(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }
}

/// [name]'s value in [vars], ignoring case (Windows writes `Path`).
String? envValue(Map<String, String> vars, String name) {
  final exact = vars[name];
  if (exact != null) return exact;
  final upper = name.toUpperCase();
  for (final e in vars.entries) {
    if (e.key.toUpperCase() == upper) return e.value;
  }
  return null;
}

/// [command] as given when it holds a separator, else the first match on
/// the `PATH` of [vars]. On Windows the extensions are `.exe` and `.com`;
/// `.cmd`/`.bat` only with [shims] (ShellX never runs them: cmd.exe would
/// have to parse the arguments). A Windows name that already ends in one of
/// the extensions in use is taken as given; any other gets them appended, so
/// an explicit `agent.cmd` is a shim too and `python3.11` finds `.exe`.
String? findExecutable(
  String command,
  Map<String, String> vars, {
  required bool isWindows,
  FileProbe files = const RealFileProbe(),
  bool shims = false,
}) {
  final ctx = p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
  final winExts = shims ? const ['.cmd', '.bat'] : const ['.exe', '.com'];
  final exts =
      !isWindows || winExts.contains(ctx.extension(command).toLowerCase())
      ? const ['']
      : winExts;
  bool ok(String path) =>
      isWindows ? files.isFile(path) : files.isExecutable(path);
  if (command.contains('/') || (isWindows && command.contains(r'\'))) {
    for (final e in exts) {
      if (ok('$command$e')) return '$command$e';
    }
    return null;
  }
  final path = envValue(vars, 'PATH') ?? '';
  for (final dir in path.split(isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    for (final e in exts) {
      final candidate = ctx.join(dir, '$command$e');
      if (ok(candidate)) return candidate;
    }
  }
  return null;
}
