import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show immutable, listEquals, visibleForTesting;
import 'package:path/path.dart' as p;

import '../terminal_sharing/sharing_paths.dart';
import '../terminal_sharing/term_binary.dart';

/// A7 D7, D8: where the `shellx` command lives. `<support>/cli` sits beside
/// terminal sharing's `bin` (apart, so a `bin/shellx-term` never reads as
/// "sharing is on"); the binary is the app's own `shellx-term`, renamed.
final class CliPaths {
  const CliPaths._({
    required this.dir,
    required this.binary,
    required this.bundledBinary,
    required this.systemLink,
    required this.windows,
  });

  /// From terminal sharing's paths: one formula for the bundled binary.
  factory CliPaths.of(SharingPaths sharing) {
    final ctx = sharing.context;
    final dir = ctx.join(ctx.dirname(sharing.binDir), 'cli');
    return CliPaths._(
      dir: dir,
      binary: ctx.join(dir, sharing.windows ? 'shellx.exe' : 'shellx'),
      bundledBinary: sharing.bundledBinary,
      systemLink: sharing.windows ? '' : '/usr/local/bin/shellx',
      windows: sharing.windows,
    );
  }

  factory CliPaths.macos({required String home, required String executable}) =>
      CliPaths.of(SharingPaths.macos(home: home, executable: executable));

  factory CliPaths.windows({
    required String localAppData,
    required String executable,
  }) => CliPaths.of(
    // The user profile is not part of any command-line path.
    SharingPaths.windows(
      localAppData: localAppData,
      userProfile: '',
      executable: executable,
    ),
  );

  /// Null without the environment terminal sharing needs (`HOME`;
  /// `LOCALAPPDATA` and `USERPROFILE`).
  static CliPaths? forPlatform({
    required bool windows,
    required Map<String, String> environment,
    required String executable,
  }) {
    final sharing = SharingPaths.forPlatform(
      windows: windows,
      environment: environment,
      executable: executable,
    );
    return sharing == null ? null : CliPaths.of(sharing);
  }

  @visibleForTesting
  factory CliPaths.forTest({
    required String dir,
    required String binary,
    required String bundled,
    String systemLink = '/usr/local/bin/shellx',
    bool windows = false,
  }) => CliPaths._(
    dir: dir,
    binary: binary,
    bundledBinary: bundled,
    systemLink: systemLink,
    windows: windows,
  );

  /// `<support>/cli`, first on every ShellX shell's `PATH`.
  final String dir;

  /// `<dir>/shellx` (`shellx.exe`).
  final String binary;

  /// The app's `shellx-term`.
  final String bundledBinary;

  /// macOS `/usr/local/bin/shellx` (other terminals); Windows ''.
  final String systemLink;
  final bool windows;
}

/// A7 amendment: the per-launch secret only ShellX shells get
/// (`SHELLX_CLI_TOKEN`): 32 random bytes, 64 hex digits. Never logged.
String generateCliToken() {
  final r = Random.secure();
  return [
    for (var i = 0; i < 32; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// D8, D29, amendment: what every ShellX shell gets on top of the app's
/// environment — `<support>/cli` first on `PATH` (Windows: the existing
/// key, whatever its case, else `Path`), the host address and the
/// per-launch token. The pane and tab ids are added per session. Final
/// ruling M1: without a running host ([socket] and [token] null) neither
/// goes in, and inherited ones are dropped.
Map<String, String> cliSessionEnvironment(
  Map<String, String> base, {
  required String cliDir,
  required String? socket,
  required String? token,
  required bool windows,
}) {
  final env = Map<String, String>.of(base);
  final key = windows
      ? env.keys.firstWhere(
          (k) => k.toUpperCase() == 'PATH',
          orElse: () => 'Path',
        )
      : 'PATH';
  final old = env[key] ?? '';
  env[key] = old.isEmpty ? cliDir : '$cliDir${windows ? ';' : ':'}$old';
  if (socket == null || token == null) {
    env
      ..remove('SHELLX_SOCKET')
      ..remove('SHELLX_CLI_TOKEN');
  } else {
    env['SHELLX_SOCKET'] = socket;
    env['SHELLX_CLI_TOKEN'] = token;
  }
  return env;
}

/// D7: keeps `<support>/cli/shellx` the same bytes as the app's binary.
final class CliBinaryInstaller {
  CliBinaryInstaller(this.paths, {Chmod chmod = systemChmod}) : _chmod = chmod;

  final CliPaths paths;
  final Chmod _chmod;

  /// Copies the app's binary when the copy is missing or different. True
  /// when it copied; false when current, or when the app has none (a
  /// development build).
  Future<bool> ensureCurrent() async {
    final from = File(paths.bundledBinary);
    final to = File(paths.binary);
    if (!await from.exists()) return false;
    if (await to.exists() &&
        await to.length() == await from.length() &&
        listEquals(await to.readAsBytes(), await from.readAsBytes())) {
      return false;
    }
    await copyBinary(
      from: from.path,
      to: to.path,
      windows: paths.windows,
      chmod: _chmod,
    );
    if (paths.windows) await _cleanupOld();
    return true;
  }

  Future<void> remove() async {
    final d = Directory(paths.dir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Windows: `shellx.old-<n>.exe` files no terminal runs any more.
  Future<void> _cleanupOld() async {
    final old = RegExp(r'^shellx\.old-\d+\.exe$');
    await for (final entity in Directory(paths.dir).list()) {
      if (entity is! File || !old.hasMatch(p.basename(entity.path))) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // Still running somewhere.
      }
    }
  }
}

enum PathInstallResult { installed, cancelled, failed }

/// D8: `shellx` for terminals ShellX did not open. [install] and
/// [uninstall] report `installed` when they reached the state asked for.
abstract interface class PathInstaller {
  /// Our entry is in place.
  Future<bool> get installed;
  Future<PathInstallResult> install();
  Future<PathInstallResult> uninstall();
}

final class ProcessOutcome {
  const ProcessOutcome({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A [boundedProcessRunner] process ran too long and was killed.
final class ProcessTimeout implements Exception {
  const ProcessTimeout();
}

typedef ProcessRunner =
    Future<ProcessOutcome> Function(String exe, List<String> args);

Future<ProcessOutcome> systemProcessRunner(
  String exe,
  List<String> args,
) async {
  final r = await Process.run(exe, args);
  return ProcessOutcome(
    exitCode: r.exitCode,
    stdout: '${r.stdout}',
    stderr: '${r.stderr}',
  );
}

/// Like [systemProcessRunner], but bounded: when the process has not both
/// exited and closed its stdout and stderr within [limit] (a child it left
/// behind may hold them open), it is killed, its output dropped and
/// [ProcessTimeout] thrown. A process killed by a signal is an ordinary
/// outcome (its negative exit code), never mistaken for the timeout.
ProcessRunner boundedProcessRunner(Duration limit) => (exe, args) async {
  final process = await Process.start(exe, args);
  final out = StringBuffer();
  final err = StringBuffer();
  final outDone = Completer<void>();
  final errDone = Completer<void>();
  final outSub = process.stdout
      .transform(systemEncoding.decoder)
      .listen(out.write, onDone: outDone.complete, onError: (Object _) {});
  final errSub = process.stderr
      .transform(systemEncoding.decoder)
      .listen(err.write, onDone: errDone.complete, onError: (Object _) {});
  final finished = Future.wait<Object?>([
    process.exitCode,
    outDone.future,
    errDone.future,
  ]).then<_Bounded>((r) => _Finished(r.first! as int));
  final timer = Completer<_Bounded>();
  final t = Timer(limit, () => timer.complete(const _TimedOut()));
  final result = await Future.any([finished, timer.future]);
  t.cancel();
  switch (result) {
    case _Finished(:final exitCode):
      return ProcessOutcome(
        exitCode: exitCode,
        stdout: out.toString(),
        stderr: err.toString(),
      );
    case _TimedOut():
      process.kill(ProcessSignal.sigkill);
      unawaited(outSub.cancel());
      unawaited(errSub.cancel());
      throw const ProcessTimeout();
  }
};

sealed class _Bounded {
  const _Bounded();
}

final class _Finished extends _Bounded {
  const _Finished(this.exitCode);
  final int exitCode;
}

final class _TimedOut extends _Bounded {
  const _TimedOut();
}

/// `/bin/test -w`: the user may create files in [dir].
Future<bool> posixWritable(String dir) async =>
    (await Process.run('/bin/test', ['-w', dir])).exitCode == 0;

/// POSIX single quotes.
String _sh(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The body of an AppleScript string literal.
String _appleScript(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// D8 macOS: a symlink `/usr/local/bin/shellx` → `<support>/cli/shellx`.
/// Directly when the folder is writable; otherwise through the system's
/// administrator password prompt (`osascript … with administrator
/// privileges`). The script is built from the fixed paths only, quoted for
/// the shell and for AppleScript. Never replaces a `shellx` that is not
/// our link. Run from the tray item only, never at startup.
final class MacPathInstaller implements PathInstaller {
  MacPathInstaller(
    this.paths, {
    this.run = systemProcessRunner,
    this.writable = posixWritable,
  });

  final CliPaths paths;
  final ProcessRunner run;
  final Future<bool> Function(String dir) writable;

  /// osascript: "User canceled. (-128)".
  static const _cancelled = '-128';

  String get _linkDir => p.posix.dirname(paths.systemLink);

  Future<FileSystemEntityType> get _type =>
      FileSystemEntity.type(paths.systemLink, followLinks: false);

  @override
  Future<bool> get installed async =>
      await _type == FileSystemEntityType.link &&
      await Link(paths.systemLink).target() == paths.binary;

  @override
  Future<PathInstallResult> install() async {
    if (await installed) return PathInstallResult.installed;
    // Someone else's `shellx` (a file or a link elsewhere): leave it.
    if (await _type != FileSystemEntityType.notFound) {
      return PathInstallResult.failed;
    }
    if (await writable(_linkDir)) {
      try {
        await Link(paths.systemLink).create(paths.binary);
        return PathInstallResult.installed;
      } on FileSystemException {
        return PathInstallResult.failed;
      }
    }
    return _asAdmin(
      // No -f: whatever appeared at the path meanwhile is never replaced
      // (ln fails, the item reports `failed`); -h never follows a link.
      'mkdir -p ${_sh(_linkDir)} && '
      'ln -sh ${_sh(paths.binary)} ${_sh(paths.systemLink)}',
    );
  }

  @override
  Future<PathInstallResult> uninstall() async {
    // Never touch someone else's file.
    if (!await installed) return PathInstallResult.installed;
    if (await writable(_linkDir)) {
      try {
        await Link(paths.systemLink).delete();
        return PathInstallResult.installed;
      } on FileSystemException {
        return PathInstallResult.failed;
      }
    }
    // Ownership is checked again as root, right before the removal.
    final link = _sh(paths.systemLink);
    return _asAdmin(
      '[ "\$(readlink $link)" = ${_sh(paths.binary)} ] && rm -f $link',
    );
  }

  Future<PathInstallResult> _asAdmin(String script) async {
    final r = await run('/usr/bin/osascript', [
      '-e',
      'do shell script "${_appleScript(script)}" '
          'with administrator privileges',
    ]);
    if (r.exitCode == 0) return PathInstallResult.installed;
    return r.stderr.contains(_cancelled)
        ? PathInstallResult.cancelled
        : PathInstallResult.failed;
  }
}

/// `HKCU\Environment` values (Windows); [write] stores `REG_EXPAND_SZ`.
abstract interface class RegistryAccess {
  String? read(String name);
  void write(String name, String value);
}

final class MemoryRegistry implements RegistryAccess {
  MemoryRegistry(this.values);
  final Map<String, String> values;

  @override
  String? read(String name) => values[name];

  @override
  void write(String name, String value) => values[name] = value;
}

/// D8 Windows: `<support>\cli` in the user's own `Path` (`HKCU\Environment`,
/// no administrator rights), exactly once, then `WM_SETTINGCHANGE` so new
/// terminals see it. Entries match case-insensitively, a trailing `\`
/// ignored.
final class WindowsPathInstaller implements PathInstaller {
  WindowsPathInstaller(
    this.paths, {
    required this.reg,
    required this.broadcast,
  });

  final CliPaths paths;
  final RegistryAccess reg;
  final void Function() broadcast;

  /// The raw segments, empty ones included, so a rewrite keeps every
  /// other byte.
  List<String> _segments() => (reg.read('Path') ?? '').split(';');

  bool _ours(String entry) =>
      entry.replaceAll(RegExp(r'\\+$'), '').toLowerCase() ==
      paths.dir.toLowerCase();

  @override
  Future<bool> get installed async => _segments().any(_ours);

  /// Appends `;<dir>` (just `<dir>` to an empty value); the existing value
  /// is kept as is, so [uninstall] gives it back byte for byte.
  @override
  Future<PathInstallResult> install() async {
    final old = reg.read('Path') ?? '';
    if (!old.split(';').any(_ours)) {
      final separator = old.isEmpty ? '' : ';';
      reg.write('Path', '$old$separator${paths.dir}');
      broadcast();
    }
    return PathInstallResult.installed;
  }

  /// Drops only our segments (each with one separator).
  @override
  Future<PathInstallResult> uninstall() async {
    final segments = _segments();
    if (segments.any(_ours)) {
      reg.write('Path', segments.where((s) => !_ours(s)).join(';'));
      broadcast();
    }
    return PathInstallResult.installed;
  }
}

/// A7 ruling M10: what to add when `/usr/local/bin` is not on the login
/// shell's `PATH` (rare on macOS).
@immutable
final class LoginPathHint {
  const LoginPathHint({required this.file, required this.line});

  /// `~/.zprofile`, `~/.bash_profile` or `~/.profile`.
  final String file;

  /// `export PATH="/usr/local/bin:$PATH"`.
  final String line;

  @override
  bool operator ==(Object other) =>
      other is LoginPathHint && other.file == file && other.line == line;

  @override
  int get hashCode => Object.hash(file, line);
}

/// A7 ruling M10: after a macOS install, asks the user's login shell
/// (`$SHELL -lc`, zsh / bash / sh only; anything else → `/bin/zsh`)
/// for its `PATH`. Unknown (the shell failed or ran over its time) → no
/// hint.
final class LoginPathCheck {
  LoginPathCheck({
    required String shell,
    required this.linkDir,
    ProcessRunner? run,
  }) : shell = _known.contains(p.posix.basename(shell)) && shell.startsWith('/')
           ? shell
           : '/bin/zsh',
       _run = run ?? boundedProcessRunner(const Duration(seconds: 2));

  static const _known = {'zsh', 'bash', 'sh'};

  /// ASCII record separator: printed around `PATH` so profile output
  /// (banners, `echo`s) is told apart from it.
  static const _mark = '\x1e';
  static const _script =
      r"printf '\036%s\036' "
      r'"$PATH"';

  final String shell;
  final String linkDir;
  final ProcessRunner _run;

  Future<LoginPathHint?> missing() async {
    final ProcessOutcome r;
    try {
      r = await _run(shell, ['-lc', _script]);
    } on Object {
      return null;
    }
    if (r.exitCode != 0) return null;
    // Only what sits between the markers: a profile may print anything.
    final start = r.stdout.indexOf(_mark);
    final end = start < 0 ? -1 : r.stdout.indexOf(_mark, start + 1);
    if (end < 0) return null;
    final path = r.stdout.substring(start + 1, end);
    if (path.split(':').contains(linkDir)) return null;
    return LoginPathHint(
      file: switch (p.posix.basename(shell)) {
        'zsh' => '~/.zprofile',
        'bash' => '~/.bash_profile',
        _ => '~/.profile',
      },
      line: 'export PATH="$linkDir:\$PATH"',
    );
  }
}
