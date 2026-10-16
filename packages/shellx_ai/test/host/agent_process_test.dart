import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:shellx_ai/host.dart';
import 'package:test/test.dart';

import '../support/processes.dart';
import '../support/scripts.dart';

void main() {
  late Directory tmp;
  final started = <AgentProcess>[];
  setUp(() => tmp = Directory.systemTemp.createTempSync('agent_process'));
  tearDown(() async {
    for (final p in started) {
      await killIfRunning(p);
    }
    started.clear();
    tmp.deleteSync(recursive: true);
  });

  AgentProcess track(AgentProcess p) {
    started.add(p);
    return p;
  }

  AgentCommand fake(FakeScenario s) => AgentCommand(
    executable: Platform.resolvedExecutable,
    args: fakeAgentArgs(writeScenario(s, tmp)),
    environment: Platform.environment,
  );

  test(
    'speaks ACP over the process pipes; stop() closes stdin and it exits',
    () async {
      final killed = <int>[];
      final p = track(
        await AgentProcess.start(
          fake(
            FakeScenario(
              turns: [
                [FakeSteps.stderr('note: warming up'), FakeSteps.text('ok')],
              ],
            ),
          ),
          cwd: tmp.path,
          isWindows: false, // the tree killer is what is asked about
          killTree: (proc) async => killed.add(proc.pid),
        ),
      );
      final client = AcpClient(
        JsonRpcConnection(input: p.stdout, output: p.stdin),
      );
      await client.initialize(clientVersion: '2.0.0');
      final sid = (await client.newSession(cwd: tmp.path)).sessionId;
      expect(
        await client.prompt(sid, const [TextBlock('hi')]),
        StopReason.endTurn,
      );
      expect(p.stderrTail, contains('note: warming up'));
      await p.stop();
      expect(await p.exitCode.timeout(const Duration(seconds: 10)), 0);
      expect(killed, isEmpty, reason: 'it left within the grace period');
    },
  );

  test('stop() kills the tree when stdin closing is ignored', () async {
    final killed = <int>[];
    final p = track(
      await AgentProcess.start(
        AgentCommand(
          executable: Platform.resolvedExecutable,
          args: dartScript(tmp, 'ignore', ignoreStdin),
          environment: Platform.environment,
        ),
        cwd: tmp.path,
        grace: const Duration(milliseconds: 300),
        isWindows: false, // the tree killer is what is asked about
        killTree: (proc) async {
          killed.add(proc.pid);
          proc.kill(ProcessSignal.sigkill);
        },
      ),
    );
    await p.stop();
    await p.exitCode.timeout(const Duration(seconds: 10));
    expect(killed, [p.pid]);
    await p.stop(); // once is enough; a second call does not kill again
    expect(killed, hasLength(1));
  });

  test('the child gets exactly the given environment', () async {
    final p = track(
      await AgentProcess.start(
        AgentCommand(
          executable: Platform.resolvedExecutable,
          args: dartScript(tmp, 'env', printEnv),
          environment: {...minimalEnv(), 'ONLY_THIS': '1'},
        ),
        cwd: tmp.path,
      ),
    );
    final out = await p.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    await p.exitCode.timeout(const Duration(seconds: 10));
    expect(out, 'ONLY_THIS');
  });

  test('a missing executable fails to start', () async {
    await expectLater(
      AgentProcess.start(
        const AgentCommand(executable: '/nonexistent/agent'),
        cwd: tmp.path,
      ),
      throwsA(isA<ProcessException>()),
    );
  });
}
