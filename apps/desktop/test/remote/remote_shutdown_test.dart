import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/remote/remote_shutdown.dart';

void main() {
  test('shutdown tells the masters to exit and never throws (D40)', () async {
    final runs = <List<String>>[];
    Future<CommandResult> run(
      String exe,
      List<String> args, {
      Duration timeout = const Duration(seconds: 5),
    }) async {
      runs.add([exe, ...args]);
      return const CommandResult(0, '', '');
    }

    final control = SshControl(
      sshPath: '/usr/bin/ssh',
      run: run,
      controlDirectory: '/tmp/x',
    );
    control.noteMaster(SshTarget.parse('devbox')!);
    runs.clear();
    var disposed = 0;
    await shutdownRemote(
      RemoteTools(sshPath: '/usr/bin/ssh', control: control),
      disposeWatcher: () => disposed++,
    );
    expect(disposed, 1);
    expect(runs.single, containsAllInOrder(['-O', 'exit']));
    await shutdownRemote(const RemoteTools(), disposeWatcher: () => disposed++);
    expect(disposed, 2);
  });
}
