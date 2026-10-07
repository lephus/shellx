import 'dart:io';

import '../pty/pty.dart';
import 'remote_bootstrap.dart';
import 'session_launch.dart';

/// D3: `/usr/bin/ssh` on macOS (never PATH: GUI apps get a minimal one),
/// the Windows OpenSSH client, else the first `ssh` on PATH.
Future<String?> sshPathFor({
  required String operatingSystem,
  required Map<String, String> environment,
  Future<bool> Function(String path)? fileExists,
}) async {
  final exists = fileExists ?? _exists;
  switch (operatingSystem) {
    case 'macos':
      return await exists('/usr/bin/ssh') ? '/usr/bin/ssh' : null;
    case 'windows':
      final root =
          environment['SystemRoot'] ??
          environment['SYSTEMROOT'] ??
          r'C:\Windows';
      final system = '$root\\System32\\OpenSSH\\ssh.exe';
      if (await exists(system)) return system;
      return _onPath('ssh.exe', environment, exists, windows: true);
    default:
      return _onPath('ssh', environment, exists, windows: false);
  }
}

/// D25: Homebrew, MacPorts and system locations first (GUI PATH again).
Future<String?> tmuxPathFor({
  required String operatingSystem,
  required Map<String, String> environment,
  Future<bool> Function(String path)? fileExists,
}) async {
  if (operatingSystem == 'windows') return null;
  final exists = fileExists ?? _exists;
  for (final candidate in const [
    '/opt/homebrew/bin/tmux',
    '/usr/local/bin/tmux',
    '/opt/local/bin/tmux',
    '/usr/bin/tmux',
  ]) {
    if (await exists(candidate)) return candidate;
  }
  return _onPath('tmux', environment, exists, windows: false);
}

Future<bool> _exists(String path) => File(path).exists();

Future<String?> _onPath(
  String name,
  Map<String, String> environment,
  Future<bool> Function(String) exists, {
  required bool windows,
}) async {
  final path = environment['PATH'] ?? environment['Path'] ?? '';
  final sep = windows ? r'\' : '/';
  for (final entry in path.split(windows ? ';' : ':')) {
    final dir = entry.trim();
    if (dir.isEmpty) continue;
    final candidate = dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
    if (await exists(candidate)) return candidate;
  }
  return null;
}

final class SshCommandOptions {
  const SshCommandOptions({
    required this.sshPath,
    this.controlPath,
    this.keepalive = true,
  });

  final String sshPath;

  /// D8: `<dir>/%C` on macOS; null = no multiplexing (Windows, unsafe dir).
  final String? controlPath;

  /// D13: add `ServerAliveInterval=15` / `ServerAliveCountMax=3`.
  final bool keepalive;
}

/// D8: [master] is `auto` for panes (first one becomes the master) and
/// `no` for helpers (use a master when there is one, never become one).
List<String> controlOptions(String? controlPath, {required String master}) =>
    controlPath == null
    ? const []
    : [
        '-o',
        'ControlMaster=$master',
        '-o',
        'ControlPath=$controlPath',
        if (master == 'auto') ...['-o', 'ControlPersist=60'],
      ];

/// D12: `ssh -t [control] [keepalive] [-l -p] -- host [remote command]`.
ShellCommand buildSshCommand(SessionLaunch launch, SshCommandOptions options) {
  final target = launch.host;
  if (target == null) {
    throw ArgumentError('a tmux session on this computer has no ssh command');
  }
  final remote = switch (launch) {
    SshLaunch(:final hook, :final remoteCwd) =>
      hook
          ? remoteExecCommand(
              remoteBootstrapScript(RemoteBootstrap(cwd: remoteCwd)),
            )
          : null,
    TmuxLaunch(:final hook, :final session, :final create) =>
      hook
          ? remoteExecCommand(
              remoteBootstrapScript(
                RemoteBootstrap(
                  tmuxSession: session,
                  tmuxCreate: create,
                  writeHooks: false,
                ),
              ),
            )
          : _plainTmux(session, create),
  };
  return ShellCommand(
    executable: options.sshPath,
    arguments: [
      '-t',
      ...controlOptions(options.controlPath, master: 'auto'),
      if (options.keepalive) ...[
        '-o',
        'ServerAliveInterval=15',
        '-o',
        'ServerAliveCountMax=3',
      ],
      ...target.destinationArgs,
      ?remote,
    ],
    name: 'ssh',
  );
}

/// D11: without the hook the name reaches the server's shell as a bare
/// word — only `[A-Za-z0-9_-]`, and no `=` prefix (zsh would expand it).
String _plainTmux(String session, bool create) {
  if (!isPlainTmuxName(session)) {
    throw ArgumentError('this tmux name needs the ShellX hook');
  }
  return create
      ? 'tmux new-session -A -s $session'
      : 'tmux attach-session -t $session';
}

/// D25: a local tmux client, argv only (no shell, exact-name `=`).
ShellCommand buildLocalTmuxCommand(TmuxLaunch launch, String tmuxPath) =>
    ShellCommand(
      executable: tmuxPath,
      arguments: launch.create
          ? ['new-session', '-A', '-s', launch.session]
          : ['attach-session', '-t', '=${launch.session}'],
      name: 'tmux',
    );
