import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
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
/// per-launch token. The pane and tab ids are added per session.
Map<String, String> cliSessionEnvironment(
  Map<String, String> base, {
  required String cliDir,
  required String socket,
  required String token,
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
  env['SHELLX_SOCKET'] = socket;
  env['SHELLX_CLI_TOKEN'] = token;
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
  const ProcessOutcome({required this.exitCode, this.stderr = ''});
  final int exitCode;
  final String stderr;
}

typedef ProcessRunner =
    Future<ProcessOutcome> Function(String exe, List<String> args);

Future<ProcessOutcome> systemProcessRunner(
  String exe,
  List<String> args,
) async {
  final r = await Process.run(exe, args);
  return ProcessOutcome(exitCode: r.exitCode, stderr: '${r.stderr}');
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
      'mkdir -p ${_sh(_linkDir)} && '
      'ln -sf ${_sh(paths.binary)} ${_sh(paths.systemLink)}',
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
    return _asAdmin('rm -f ${_sh(paths.systemLink)}');
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

  List<String> _parts() =>
      (reg.read('Path') ?? '').split(';').where((s) => s.isNotEmpty).toList();

  bool _ours(String entry) =>
      entry.replaceAll(RegExp(r'\\+$'), '').toLowerCase() ==
      paths.dir.toLowerCase();

  @override
  Future<bool> get installed async => _parts().any(_ours);

  @override
  Future<PathInstallResult> install() async {
    final parts = _parts();
    if (!parts.any(_ours)) {
      reg.write('Path', [...parts, paths.dir].join(';'));
      broadcast();
    }
    return PathInstallResult.installed;
  }

  @override
  Future<PathInstallResult> uninstall() async {
    final parts = _parts();
    if (parts.any(_ours)) {
      reg.write('Path', parts.where((s) => !_ours(s)).join(';'));
      broadcast();
    }
    return PathInstallResult.installed;
  }
}
