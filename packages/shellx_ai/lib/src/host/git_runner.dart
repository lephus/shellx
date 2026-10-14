import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import 'git_locator.dart';

/// A git command failed or ran over its time. Never carries git's stderr:
/// it may name the user's files (spec D20).
final class GitFailed implements Exception {
  const GitFailed(this.exitCode, {this.timedOut = false});

  final int exitCode;
  final bool timedOut;

  @override
  String toString() => timedOut ? 'GitFailed(timeout)' : 'GitFailed($exitCode)';
}

/// Runs git against the shadow repository only (spec D12, ruling R3).
/// `GIT_DIR` and `GIT_WORK_TREE` are always set; every inherited `GIT_*`
/// variable is dropped; [flags] keep the user's config from changing
/// bytes, starting daemons or signing. Pathspecs are literal.
final class GitRunner with Redacted {
  GitRunner({
    required this.git,
    required this.gitDir,
    required this.workTree,
    required Map<String, String> env,
    DateTime Function()? now,
  }) : _env = env,
       _now = now ?? DateTime.now;

  /// The user's global config cannot convert bytes, start fsmonitor,
  /// sign, gc, or run hooks: `core.hooksPath` points at the shadow repo's
  /// own `hooks` folder, which the store never fills (`git init` runs
  /// without templates). A global `reference-transaction` hook would
  /// otherwise veto `update-ref`.
  List<String> get flags => [
    for (final setting in [
      'core.autocrlf=false',
      'core.safecrlf=false',
      'core.fsmonitor=false',
      'core.quotePath=false',
      'commit.gpgSign=false',
      'gc.auto=0',
      'maintenance.auto=false',
      'core.logAllRefUpdates=false',
      'core.longpaths=true',
      'core.hooksPath=$gitDir${Platform.pathSeparator}hooks',
    ]) ...['-c', setting],
  ];

  final GitTool git;
  final String gitDir;
  final String workTree;
  final Map<String, String> _env;
  final DateTime Function() _now;

  Map<String, String> _environment() {
    final when = '${_now().toUtc().millisecondsSinceEpoch ~/ 1000} +0000';
    return {
      for (final e in _env.entries)
        if (!e.key.toUpperCase().startsWith('GIT_')) e.key: e.value,
      'GIT_DIR': gitDir,
      'GIT_WORK_TREE': workTree,
      'GIT_LITERAL_PATHSPECS': '1',
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_AUTHOR_NAME': 'ShellX',
      'GIT_AUTHOR_EMAIL': 'checkpoint@shellx.invalid',
      'GIT_COMMITTER_NAME': 'ShellX',
      'GIT_COMMITTER_EMAIL': 'checkpoint@shellx.invalid',
      'GIT_AUTHOR_DATE': when,
      'GIT_COMMITTER_DATE': when,
    };
  }

  /// Runs `git <flags> <args>`; returns stdout, throws [GitFailed].
  Future<List<int>> run(
    List<String> args, {
    List<int>? input,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final process = await Process.start(
      git.executable,
      [...flags, ...args],
      workingDirectory: workTree,
      environment: _environment(),
      includeParentEnvironment: false,
    );
    if (input != null) process.stdin.add(input);
    unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    unawaited(process.stderr.drain<void>());
    final out = BytesBuilder(copy: false);
    final outDone = process.stdout.listen(out.add).asFuture<void>();
    final int code;
    try {
      // The output is under the same limit: a child that keeps stdout open
      // after git has exited must not hang the project's queue.
      final done = Future.wait<Object?>([process.exitCode, outDone]);
      code = (await done.timeout(timeout)).first! as int;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      final lock = File('$gitDir${Platform.pathSeparator}index.lock');
      if (lock.existsSync()) {
        try {
          lock.deleteSync();
        } on FileSystemException {
          // Left for the next run to fail on; undo is off anyway.
        }
      }
      throw const GitFailed(-1, timedOut: true);
    }
    if (code != 0) throw GitFailed(code);
    return out.takeBytes();
  }

  Future<String> text(
    List<String> args, {
    List<int>? input,
    Duration timeout = const Duration(seconds: 60),
  }) async => utf8.decode(
    await run(args, input: input, timeout: timeout),
    allowMalformed: true,
  );
}
