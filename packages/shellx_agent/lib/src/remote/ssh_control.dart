import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'command_runner.dart';
import 'remote_bootstrap.dart' show remoteExecCommand;
import 'ssh_command.dart';
import 'ssh_target.dart';

abstract interface class LocalPorts {
  /// Nothing listens on 127.0.0.1:[port].
  Future<bool> isFree(int port);

  /// A port the OS gives out right now.
  Future<int> ephemeral();
}

abstract interface class ForwardProcess {
  Future<int> get exitCode;
  void kill();
}

typedef ForwardStarter =
    Future<ForwardProcess> Function(String executable, List<String> arguments);

final class ForwardFailedException implements Exception {
  const ForwardFailedException();
  @override
  String toString() => 'ForwardFailedException';
}

final class _SocketPorts implements LocalPorts {
  const _SocketPorts();

  @override
  Future<bool> isFree(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  Future<int> ephemeral() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}

final class _ProcessForward implements ForwardProcess {
  _ProcessForward(this._process) {
    unawaited(_process.stdin.close().catchError((Object _) {}));
    _process.stdout.drain<void>().ignore();
    _process.stderr.drain<void>().ignore();
  }
  final Process _process;
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  void kill() => _process.kill();
}

Future<ForwardProcess> _startForward(
  String executable,
  List<String> arguments,
) async => _ProcessForward(
  await Process.start(
    executable,
    arguments,
    // A8 security: no ShellX socket credentials for ssh.
    environment: helperEnvironment(Platform.environment),
    includeParentEnvironment: false,
  ),
);

final class _Forward {
  _Forward(this.target, this.remote, this.local, this.process);
  final SshTarget target;
  final int remote;
  final int local;
  final ForwardProcess? process;
  bool dead = false;
  String get spec => '127.0.0.1:$local:localhost:$remote';
}

/// The helpers around the panes' own `ssh` (A8 D8, D9, D13, D18, D19, D40).
/// Every call runs `BatchMode=yes` or only talks to the control socket:
/// nothing here can ever wait for a password nobody sees (D38g). Nothing
/// here logs.
final class SshControl {
  SshControl({
    required this.sshPath,
    this.controlDirectory,
    CommandRunner? run,
    ForwardStarter? startForward,
    LocalPorts? ports,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _run = run ?? runCommand,
       _start = startForward ?? _startForward,
       _ports = ports ?? const _SocketPorts(),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final String sshPath;

  /// D8: `/tmp/shellx-ssh-<uid>` checked by [prepareControlDirectory];
  /// null = no multiplexing (Windows, unsafe directory).
  final String? controlDirectory;
  final CommandRunner _run;
  final ForwardStarter _start;
  final LocalPorts _ports;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  final _keepalive = <String, ({DateTime at, bool needed})>{};
  final _forwards = <String, _Forward>{};
  final _masters = <String, SshTarget>{};

  String? get controlPath =>
      controlDirectory == null ? null : '$controlDirectory/%C';

  /// D13: `ssh -G` (local, no network) says `serveraliveinterval 0`, or
  /// cannot answer.
  Future<bool> keepaliveNeeded(SshTarget target) async {
    final now = _now();
    final cached = _keepalive[target.key];
    if (cached != null &&
        now.difference(cached.at) < const Duration(seconds: 60)) {
      return cached.needed;
    }
    final r = await _run(sshPath, [
      '-G',
      ...target.destinationArgs,
    ], timeout: const Duration(seconds: 2));
    var needed = true;
    if (r.exitCode == 0 && !r.timedOut) {
      for (final line in const LineSplitter().convert(r.stdout)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 &&
            parts[0].toLowerCase() == 'serveraliveinterval') {
          needed = (int.tryParse(parts[1]) ?? 0) == 0;
        }
      }
    }
    _keepalive[target.key] = (at: now, needed: needed);
    return needed;
  }

  Future<bool> masterAlive(SshTarget target) async {
    final path = controlPath;
    if (path == null) return false;
    final r = await _run(sshPath, [
      '-o',
      'ControlPath=$path',
      '-O',
      'check',
      ...target.destinationArgs,
    ], timeout: const Duration(seconds: 2));
    return r.exitCode == 0 && !r.timedOut;
  }

  /// D9: at most 3 s (checks 100 ms apart) while [stillWaiting].
  Future<void> awaitMaster(
    SshTarget target, {
    required bool Function() stillWaiting,
  }) async {
    if (controlPath == null) return;
    final deadline = _now().add(const Duration(seconds: 3));
    while (stillWaiting() && _now().isBefore(deadline)) {
      if (await masterAlive(target)) return;
      await _sleep(const Duration(milliseconds: 100));
    }
  }

  /// D18, D25: [script] under `/bin/sh` on the server, never prompting,
  /// over the master when one exists.
  Future<CommandResult> runRemote(
    SshTarget target,
    String script, {
    Duration timeout = const Duration(seconds: 4),
  }) => _run(sshPath, [
    '-T',
    '-o',
    'BatchMode=yes',
    '-o',
    'ConnectTimeout=${max(1, timeout.inSeconds)}',
    ...controlOptions(controlPath, master: 'no'),
    '-o',
    'ClearAllForwardings=yes',
    ...target.destinationArgs,
    remoteExecCommand(script),
  ], timeout: timeout);

  /// A pane's ssh may have become a master for [target] (D40).
  void noteMaster(SshTarget target) {
    if (controlPath != null) _masters[target.key] = target;
  }

  Iterable<SshTarget> get mastersUsed => _masters.values;

  int? forwardedPort(SshTarget target, int remotePort) {
    final f = _forwards['${target.key}\u0000$remotePort'];
    return f == null || f.dead ? null : f.local;
  }

  /// D19: `127.0.0.1:L → localhost:remotePort` on the server; L = the same
  /// port when it is free here. Throws [ForwardFailedException].
  Future<int> forward(SshTarget target, int remotePort) async {
    if (remotePort < 1 || remotePort > 65535) {
      throw const ForwardFailedException();
    }
    final key = '${target.key}\u0000$remotePort';
    final existing = _forwards[key];
    if (existing != null && !existing.dead) {
      // A forward over a master dies with it: check before reusing.
      if (existing.process != null || await masterAlive(target)) {
        return existing.local;
      }
      _forwards.remove(key);
    }
    // Ended forwards (their process exited) hold no slot.
    final live = _forwards.values.where((f) => f.target == target && !f.dead);
    if (live.length >= 32) throw const ForwardFailedException();
    final local = await _ports.isFree(remotePort)
        ? remotePort
        : await _ports.ephemeral();
    if (local < 1 || local > 65535) throw const ForwardFailedException();
    final spec = '127.0.0.1:$local:localhost:$remotePort';
    final path = controlPath;
    if (path != null && await masterAlive(target)) {
      final r = await _run(sshPath, [
        '-o',
        'ControlPath=$path',
        '-O',
        'forward',
        '-L',
        spec,
        ...target.destinationArgs,
      ], timeout: const Duration(seconds: 3));
      if (r.exitCode != 0 || r.timedOut) throw const ForwardFailedException();
      _forwards[key] = _Forward(target, remotePort, local, null);
      return local;
    }
    final process = await _start(sshPath, [
      '-N',
      '-T',
      '-o',
      'BatchMode=yes',
      '-o',
      'ExitOnForwardFailure=yes',
      '-o',
      'ControlMaster=no',
      '-o',
      'ControlPath=none',
      '-L',
      spec,
      ...target.destinationArgs,
    ]);
    final forward = _Forward(target, remotePort, local, process);
    var exited = false;
    unawaited(
      process.exitCode.then((_) {
        exited = true;
        forward.dead = true;
      }),
    );
    for (var i = 0; i < 50 && !exited; i++) {
      await _sleep(const Duration(milliseconds: 100));
      if (exited) break;
      if (!await _ports.isFree(local)) {
        _forwards[key] = forward;
        return local;
      }
    }
    process.kill();
    throw const ForwardFailedException();
  }

  /// The last pane of [target] closed (D19).
  Future<void> cancelForwards(SshTarget target) async {
    final mine = _forwards.entries
        .where((e) => e.value.target == target)
        .toList();
    for (final entry in mine) {
      _forwards.remove(entry.key);
      final process = entry.value.process;
      if (process != null) {
        process.kill();
        continue;
      }
      final path = controlPath;
      if (path == null) continue;
      await _run(sshPath, [
        '-o',
        'ControlPath=$path',
        '-O',
        'cancel',
        '-L',
        entry.value.spec,
        ...target.destinationArgs,
      ], timeout: const Duration(seconds: 2));
    }
  }

  /// D40: "Quit completely" — every forward process killed, every master
  /// ShellX may have started told to exit, in parallel, ≤ 2 s each.
  Future<void> exitMasters(Iterable<SshTarget> targets) async {
    for (final f in _forwards.values) {
      f.process?.kill();
    }
    _forwards.clear();
    final path = controlPath;
    if (path == null) return;
    final unique = {for (final t in targets) t.key: t}.values.toList();
    await Future.wait([
      for (final t in unique)
        _run(sshPath, [
          '-o',
          'ControlPath=$path',
          '-O',
          'exit',
          ...t.destinationArgs,
        ], timeout: const Duration(seconds: 2)),
    ]);
  }
}

/// D8 (macOS): `<base>/shellx-ssh-<uid>`, owned by us, 0700, a real
/// directory — else null (no multiplexing). `ControlPath` plus ssh's
/// 17-character temporary suffix must stay under `sun_path` (104 bytes);
/// `%C` is counted as 64 characters (SHA-256 proof).
Future<String?> prepareControlDirectory({
  String base = '/tmp',
  int maxSocketPath = 104,
  CommandRunner? run,
  void Function(String message)? log,
}) async {
  final runner = run ?? runCommand;
  final id = await runner('/usr/bin/id', ['-u']);
  final uid = id.stdout.trim();
  if (id.exitCode != 0 || !RegExp(r'^[0-9]+$').hasMatch(uid)) {
    log?.call('ssh: control dir user unknown');
    return null;
  }
  final dir = '$base/shellx-ssh-$uid';
  if (dir.length + 1 + 64 + 17 >= maxSocketPath) {
    log?.call('ssh: control dir path too long'); // never the path (D37)
    return null;
  }
  try {
    await Directory(dir).create();
  } on FileSystemException {
    // Exists already, or cannot be made: the checks below decide.
  }
  final stat = await runner('/usr/bin/stat', ['-f', '%u %Lp %HT', dir]);
  // Owner and type before chmod, so chmod never follows a link.
  final first = stat.stdout.trim();
  if (stat.exitCode != 0 ||
      !first.startsWith('$uid ') ||
      !first.endsWith(' Directory')) {
    log?.call('ssh: control dir unsafe'); // never the path (D37)
    return null;
  }
  await runner('/bin/chmod', ['700', dir]);
  final again = await runner('/usr/bin/stat', ['-f', '%u %Lp %HT', dir]);
  if (again.exitCode != 0 || again.stdout.trim() != '$uid 700 Directory') {
    log?.call('ssh: control dir unsafe');
    return null;
  }
  return dir;
}
