import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ai_host'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('launch keeps running.json in step with the agent process', () async {
    final host = AiHost(supportDir: tmp.path, clientVersion: '2.0.0');
    final command = AgentCommand(
      executable: Platform.resolvedExecutable,
      args: fakeAgentArgs(writeScenario(const FakeScenario(), tmp)),
      environment: Platform.environment,
    );
    final channel = await host.launch(command, cwd: tmp.path) as AgentProcess;
    expect(host.running.read().single.pid, channel.pid);
    final client = AcpClient(
      JsonRpcConnection(input: channel.stdout, output: channel.stdin),
    );
    await client.initialize(clientVersion: '2.0.0');
    await channel.stop();
    await channel.exitCode;
    for (var i = 0; i < 100 && host.running.read().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(host.running.read(), isEmpty);
    expect(File(p.join(tmp.path, 'ai', 'running.json')).existsSync(), isTrue);
  });

  test('startup sweeps leftovers', () async {
    final killed = <int>[];
    final t = DateTime.now();
    final running = RunningAgents(
      File(p.join(tmp.path, 'ai', 'running.json')),
      info: (pid) async => (command: '/usr/bin/node', startedAt: t),
      killPid: (pid) async => killed.add(pid),
    );
    await running.add(
      RunningRecord(pid: 4242, command: '/usr/local/bin/node', startedAt: t),
    );
    // A login shell that answers at once, so the background prune stays hermetic.
    final env = LoginShellEnv(
      processEnv: {'PATH': '/usr/bin'},
      run: (s, a, e, t) async => (0, <int>[]),
    );
    final host = AiHost(
      supportDir: tmp.path,
      clientVersion: '2.0.0',
      running: running,
      env: env,
    );
    expect(await host.startup(), 1);
    expect(killed, [4242]);
  });
}
