import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_acp/testing.dart';
import 'package:test/test.dart';

late Directory tmp;

Future<(Process, AcpClient, StringBuffer)> spawn(FakeScenario scenario) async {
  final file = writeScenario(scenario, tmp);
  final p = await Process.start(
    Platform.resolvedExecutable,
    fakeAgentArgs(file),
    workingDirectory: tmp.path,
  );
  final err = StringBuffer();
  p.stderr.transform(utf8.decoder).listen(err.write);
  return (
    p,
    AcpClient(JsonRpcConnection(input: p.stdout, output: p.stdin)),
    err,
  );
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('fake_agent'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('speaks ACP over real pipes and logs what it got to stderr', () async {
    final (p, client, err) = await spawn(
      FakeScenario(
        turns: [
          [
            FakeSteps.text('hello'),
            FakeSteps.write('out.txt', 'made by agent'),
          ],
        ],
      ),
    );
    final got = <SessionUpdate>[];
    client.onUpdate = (_, u) => got.add(u);
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    expect(
      await client.prompt(sid, const [TextBlock('hi')]),
      StopReason.endTurn,
    );
    expect((got.single as AgentMessageChunk).content, isA<TextBlock>());
    expect(File('${tmp.path}/out.txt').readAsStringSync(), 'made by agent');
    await client.close(); // closes stdin
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(err.toString(), contains('RECV session/prompt:hi'));
  });

  test('a garbage line is skipped; a 10 MiB line arrives whole', () async {
    final (p, client, _) = await spawn(
      FakeScenario(
        turns: [
          [
            FakeSteps.raw('Welcome to my shell profile!'),
            FakeSteps.bigText(10 << 20),
          ],
        ],
      ),
    );
    final sizes = <int>[];
    client.onUpdate = (_, u) {
      if (u is AgentMessageChunk) {
        sizes.add((u.content as TextBlock).text.length);
      }
    };
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    await client.prompt(sid, const [TextBlock('go')]);
    expect(sizes, [10 << 20]);
    await client.close();
    await p.exitCode.timeout(const Duration(seconds: 10));
  });

  test('exit mid-turn: exit code 3 and the prompt fails', () async {
    final (p, client, _) = await spawn(
      FakeScenario(
        turns: [
          [FakeSteps.stderr('fatal: out of tokens'), FakeSteps.exit(3)],
        ],
      ),
    );
    await client.initialize(clientVersion: '2.0.0');
    final sid = (await client.newSession(cwd: tmp.path)).sessionId;
    await expectLater(
      client.prompt(sid, const [TextBlock('go')]),
      throwsA(isA<ConnectionClosed>()),
    );
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), 3);
  });
}
