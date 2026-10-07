import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  Future<CommandResult> run(
    String exe,
    List<String> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async => switch (args) {
    ['-u'] => const CommandResult(0, '501\n', ''),
    ['-f', _, _] => const CommandResult(0, '501 700 Directory\n', ''),
    _ => const CommandResult(0, '', ''),
  };

  test('macOS: system ssh, Homebrew tmux, multiplexing (D3, D8)', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'macos',
      environment: const {'PATH': '/usr/bin'},
      run: run,
      fileExists: (p) async =>
          p == '/usr/bin/ssh' || p == '/opt/homebrew/bin/tmux',
      controlBase: '/tmp/s',
    );
    expect(tools.sshPath, '/usr/bin/ssh');
    expect(tools.tmuxPath, '/opt/homebrew/bin/tmux');
    expect(tools.control!.controlPath, '/tmp/s/shellx-ssh-501/%C');
  });

  test('Windows: no multiplexing, no local tmux', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'windows',
      environment: const {'SystemRoot': r'C:\Windows'},
      run: run,
      fileExists: (p) async => p.endsWith(r'OpenSSH\ssh.exe'),
    );
    expect(tools.control!.controlPath, isNull);
    expect(tools.tmuxPath, isNull);
  });

  test('no ssh: no control', () async {
    final tools = await resolveRemoteTools(
      operatingSystem: 'macos',
      environment: const {},
      run: run,
      fileExists: (_) async => false,
    );
    expect(tools.sshPath, isNull);
    expect(tools.control, isNull);
  });
}
