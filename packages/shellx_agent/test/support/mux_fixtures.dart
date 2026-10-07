import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// The shared secret of every mux test.
final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));

/// A [MuxListener] a test feeds with the daemon side of a memory pair.
final class TestListener implements MuxListener {
  final _c = StreamController<MuxConnection>.broadcast();
  @override
  Stream<MuxConnection> get connections => _c.stream;
  @override
  String get address => 'test';
  @override
  Future<void> close() async {}
  void push(MuxConnection c) => _c.add(c);
}

/// [RemoteTools] whose `ssh -G` says "no keepalive" and whose `-O check`
/// says "no master": enough to start an SSH or tmux launch on a fake PTY.
RemoteTools fakeRemoteTools() {
  Future<CommandResult> run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (args.first == '-G') {
      return const CommandResult(0, 'serveraliveinterval 0\n', '');
    }
    return const CommandResult(255, '', '');
  }

  var clock = DateTime(2026, 10, 7);
  return RemoteTools(
    sshPath: '/usr/bin/ssh',
    tmuxPath: '/usr/local/bin/tmux',
    control: SshControl(
      sshPath: '/usr/bin/ssh',
      controlDirectory: '/tmp/shellx-ssh-501',
      run: run,
      now: () => clock,
      sleep: (d) async => clock = clock.add(d),
    ),
  );
}
