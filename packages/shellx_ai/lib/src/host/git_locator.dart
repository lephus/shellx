import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart' show Redacted;

import '../model/changes.dart';
import 'login_shell_env.dart';
import 'probe.dart';

/// Git as the checkpoints use it.
final class GitTool with Redacted {
  const GitTool(this.executable, this.major, this.minor);

  final String executable;
  final int major;
  final int minor;
}

/// Finds git on the login PATH (spec D12). On macOS `/usr/bin/git` is a
/// stub that opens the Command Line Tools installer when they are missing,
/// so `xcode-select -p` must succeed first. Git older than 2.26 has no
/// `restore --pathspec-from-file`.
final class GitLocator {
  GitLocator({
    ProbeRunner? probe,
    bool? isMacOS,
    bool? isWindows,
    this.files = const RealFileProbe(),
  }) : _probe = probe ?? runProbe,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isWindows = isWindows ?? Platform.isWindows;

  final FileProbe files;
  final ProbeRunner _probe;
  final bool _isMacOS;
  final bool _isWindows;

  Future<(GitTool?, UndoOff?)> locate(LoginEnv env) async {
    final git = findExecutable(
      'git',
      env.vars,
      isWindows: _isWindows,
      files: files,
    );
    if (git == null) return (null, UndoOff.noGit);
    if (_isMacOS && git == '/usr/bin/git') {
      final r = await _probe('/usr/bin/xcode-select', const [
        '-p',
      ], environment: env.vars);
      if (r == null || r.exitCode != 0) {
        return (null, UndoOff.noCommandLineTools);
      }
    }
    final v = await _probe(git, const ['--version'], environment: env.vars);
    final m = RegExp(r'git version (\d+)\.(\d+)').firstMatch(v?.stdout ?? '');
    if (v == null || v.exitCode != 0 || m == null) return (null, UndoOff.noGit);
    final major = int.parse(m.group(1)!);
    final minor = int.parse(m.group(2)!);
    if (major < 2 || (major == 2 && minor < 26)) {
      return (null, UndoOff.gitTooOld);
    }
    return (GitTool(git, major, minor), null);
  }
}
