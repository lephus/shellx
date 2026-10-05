import 'dart:convert';
import 'dart:io';

/// Runs a program and returns its result with stdout/stderr decoded as
/// UTF-8; injected in tests.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> runProcessUtf8(
  String executable,
  List<String> arguments,
) => Process.run(
  executable,
  arguments,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// Whether a PowerShell will run its profile (spec §10.3).
enum ScriptPolicy {
  /// Profiles run.
  allowed,

  /// `Restricted` or `AllSigned`: fixable with `Set-ExecutionPolicy
  /// -Scope CurrentUser RemoteSigned` when the user asks.
  blocked,

  /// Blocked by Group Policy (`MachinePolicy`/`UserPolicy`): ShellX cannot
  /// change it, so this PowerShell is not shared.
  blockedByGroupPolicy,
}

/// One installed PowerShell (7 or Windows PowerShell 5.1).
final class PowerShellInstall {
  const PowerShellInstall({
    required this.name,
    required this.executable,
    required this.profilePath,
    required this.policy,
  });

  /// "PowerShell 7" or "Windows PowerShell".
  final String name;
  final String executable;

  /// `$PROFILE.CurrentUserAllHosts`, asked from this PowerShell itself
  /// (Documents may live in OneDrive).
  final String profilePath;
  final ScriptPolicy policy;
}

/// Asks each installed PowerShell for its profile path and script policy.
final class PowerShellProbe {
  PowerShellProbe({
    required Map<String, String> environment,
    ProcessRunner run = runProcessUtf8,
  }) : _environment = environment,
       _run = run;

  final Map<String, String> _environment;
  final ProcessRunner _run;

  static const String _query =
      r'[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); '
      r'$PROFILE.CurrentUserAllHosts; '
      r'[string](Get-ExecutionPolicy); '
      r'Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }';

  /// PowerShell 7 from `PATH`, Windows PowerShell from `%SystemRoot%`.
  List<(String, String)> get candidates {
    final root =
        _environment['SystemRoot'] ??
        _environment['SYSTEMROOT'] ??
        r'C:\Windows';
    return [
      ('PowerShell 7', 'pwsh.exe'),
      (
        'Windows PowerShell',
        '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      ),
    ];
  }

  /// Every PowerShell that answered. One that is not installed, fails, or
  /// prints something unexpected is left out.
  Future<List<PowerShellInstall>> find() async {
    final found = <PowerShellInstall>[];
    for (final (name, executable) in candidates) {
      final ProcessResult result;
      try {
        result = await _run(executable, [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          _query,
        ]);
      } on ProcessException {
        continue; // Not installed.
      }
      if (result.exitCode != 0) continue;
      final install = parse(name, executable, result.stdout as String);
      if (install != null) found.add(install);
    }
    return found;
  }

  /// Runs `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` in
  /// [install]. Only ever called after the user pressed the button.
  Future<bool> allowLocalScripts(PowerShellInstall install) async {
    try {
      final result = await _run(install.executable, [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force',
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Visible for tests: the query's output → an install, or null.
  static PowerShellInstall? parse(
    String name,
    String executable,
    String output,
  ) {
    final lines = const LineSplitter()
        .convert(output)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final profile = lines[0];
    if (!RegExp(r'^[A-Za-z]:\\|^\\\\').hasMatch(profile)) return null;
    final effective = lines[1].toLowerCase();
    final scopes = <String, String>{};
    for (final line in lines.skip(2)) {
      final eq = line.indexOf('=');
      if (eq > 0) {
        scopes[line.substring(0, eq).toLowerCase()] = line
            .substring(eq + 1)
            .toLowerCase();
      }
    }
    bool set(String scope) {
      final value = scopes[scope];
      return value != null && value != 'undefined';
    }

    final ScriptPolicy policy;
    if (effective != 'restricted' && effective != 'allsigned') {
      policy = ScriptPolicy.allowed;
    } else if (set('machinepolicy') || set('userpolicy')) {
      policy = ScriptPolicy.blockedByGroupPolicy;
    } else {
      policy = ScriptPolicy.blocked;
    }
    return PowerShellInstall(
      name: name,
      executable: executable,
      profilePath: profile,
      policy: policy,
    );
  }
}
