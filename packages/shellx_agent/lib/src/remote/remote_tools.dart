import 'command_runner.dart';
import 'ssh_command.dart';
import 'ssh_control.dart';

/// What this computer has for A8 (D3, D8, D25), resolved once at startup.
final class RemoteTools {
  const RemoteTools({this.sshPath, this.tmuxPath, this.control});

  /// Null: no ssh — SSH panes fail with `ssh_unavailable`.
  final String? sshPath;

  /// Null: no local tmux (always on Windows).
  final String? tmuxPath;
  final SshControl? control;
}

Future<RemoteTools> resolveRemoteTools({
  required String operatingSystem,
  required Map<String, String> environment,
  CommandRunner? run,
  Future<bool> Function(String path)? fileExists,
  void Function(String message)? log,
  String controlBase = '/tmp',
}) async {
  final ssh = await sshPathFor(
    operatingSystem: operatingSystem,
    environment: environment,
    fileExists: fileExists,
  );
  final tmux = await tmuxPathFor(
    operatingSystem: operatingSystem,
    environment: environment,
    fileExists: fileExists,
  );
  if (ssh == null) return RemoteTools(tmuxPath: tmux);
  final dir = operatingSystem == 'macos'
      ? await prepareControlDirectory(base: controlBase, run: run, log: log)
      : null;
  return RemoteTools(
    sshPath: ssh,
    tmuxPath: tmux,
    control: SshControl(sshPath: ssh, controlDirectory: dir, run: run),
  );
}
