import 'dart:io';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
// Only the testing library: it must bring FakeScenario and FakeSteps along.
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

AcpClient connect(AgentChannel channel) =>
    AcpClient(JsonRpcConnection(input: channel.stdout, output: channel.stdin));

Future<StopReason> converse(AcpClient client, [String text = 'hi']) async {
  await client.initialize(clientVersion: '2.0.0');
  final sid = (await client.newSession(cwd: '/work')).sessionId;
  return client.prompt(sid, [TextBlock(text)]);
}

void main() {
  group('FakeAgentChannel', () {
    test(
      'speaks ACP over its pipes; stderr lines are the stderrTail',
      () async {
        final channel = FakeAgentChannel(
          FakeScenario(
            turns: [
              [FakeSteps.stderr('note: warming up'), FakeSteps.text('ok')],
            ],
          ),
        );
        final client = connect(channel);
        expect(await converse(client), StopReason.endTurn);
        expect(channel.stderrTail, contains('note: warming up\n'));
        expect(channel.agent.received, contains('session/prompt:hi'));
        expect(channel.exited, isFalse);
        await channel.stop();
      },
    );

    test('closing stdin makes it exit 0; stop() is counted', () async {
      final channel = FakeAgentChannel(FakeScenario());
      final client = connect(channel);
      await client.initialize(clientVersion: '2.0.0');

      await channel.stop();
      expect(await channel.exitCode.timeout(const Duration(seconds: 5)), 0);
      expect(
        await client.connection.done.timeout(const Duration(seconds: 5)),
        ConnectionCloseReason.ended,
        reason: 'stdout ended',
      );
      expect(channel.stopCalls, 1);
      expect(channel.killCalls, 0);
      expect(channel.exited, isTrue);

      await channel.stop(); // harmless the second time
      expect(channel.stopCalls, 2);
      expect(await channel.exitCode, 0);
    });

    test('kill() exits -9 at once, closes stdout and is counted', () async {
      final channel = FakeAgentChannel(FakeScenario());
      final client = connect(channel);
      await client.initialize(clientVersion: '2.0.0');

      await channel.kill();
      expect(channel.exited, isTrue);
      expect(await channel.exitCode, -9);
      expect(
        await client.connection.done.timeout(const Duration(seconds: 5)),
        ConnectionCloseReason.ended,
        reason: 'stdout ended',
      );
      expect(channel.killCalls, 1);
      expect(channel.stopCalls, 0);

      await channel.stop(); // already gone: keeps -9
      expect(await channel.exitCode, -9);
    });

    test('an exit step is a crash: that code, and the turn fails', () async {
      final channel = FakeAgentChannel(
        FakeScenario(
          turns: [
            [FakeSteps.stderr('fatal: out of memory'), FakeSteps.exit(3)],
          ],
        ),
      );
      final client = connect(channel);
      await client.initialize(clientVersion: '2.0.0');
      final sid = (await client.newSession(cwd: '/work')).sessionId;
      final turn = expectLater(
        client.prompt(sid, const [TextBlock('go')]),
        throwsA(isA<ConnectionClosed>()),
      );
      expect(await channel.exitCode.timeout(const Duration(seconds: 5)), 3);
      await turn;
      expect(channel.stderrTail, contains('fatal: out of memory'));
      expect(channel.stopCalls + channel.killCalls, 0);
    });

    test('the client hanging up lets it exit 0', () async {
      final channel = FakeAgentChannel(FakeScenario());
      final client = connect(channel);
      await client.initialize(clientVersion: '2.0.0');
      await client.close();
      expect(await channel.exitCode.timeout(const Duration(seconds: 5)), 0);
    });
  });

  group('FakeLauncher', () {
    const command = AgentCommand(executable: 'agent');
    FakeScenario scenario(String id) => FakeScenario(sessionId: id);
    List<String> ids(FakeLauncher l) => [
      for (final c in l.channels) c.agent.scenario.sessionId,
    ];

    test(
      'launch 0 uses first, launch n uses later[n - 1], the last repeats',
      () async {
        final launcher = FakeLauncher(scenario('a'), [
          scenario('b'),
          scenario('c'),
        ]);
        for (var i = 0; i < 4; i++) {
          await launcher.call(command, cwd: '/work');
        }
        expect(ids(launcher), ['a', 'b', 'c', 'c']);
      },
    );

    test('without later scenarios every launch uses the first', () async {
      final launcher = FakeLauncher(scenario('a'));
      for (var i = 0; i < 3; i++) {
        await launcher.call(command, cwd: '/work');
      }
      expect(ids(launcher), ['a', 'a', 'a']);
      expect(launcher.channels.toSet(), hasLength(3), reason: 'fresh channels');
    });

    test('plugs in as an AgentLauncher and remembers each command', () async {
      final launcher = FakeLauncher(scenario('a'));
      final AgentLauncher launch = launcher.call;
      const other = AgentCommand(executable: 'other', args: ['--acp']);
      final first = await launch(command, cwd: '/work');
      final second = await launch(other, cwd: '/work');
      expect(launcher.commands, [command, other]);
      expect(launcher.channels, [same(first), same(second)]);
    });

    test('the cwd it is given is where the fake agent works', () async {
      final tmp = Directory.systemTemp.createTempSync('fake_launcher');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final launcher = FakeLauncher(
        FakeScenario(
          turns: [
            [FakeSteps.write('out.txt', 'made by agent')],
          ],
        ),
      );
      final channel = await launcher.call(command, cwd: tmp.path);
      expect(await converse(connect(channel)), StopReason.endTurn);
      expect(File('${tmp.path}/out.txt').readAsStringSync(), 'made by agent');
      await channel.stop();
    });

    test('a restarted agent can behave differently', () async {
      final launcher = FakeLauncher(
        FakeScenario(
          turns: [
            [FakeSteps.exit(1)],
          ],
        ),
        [
          FakeScenario(
            turns: [
              [FakeSteps.text('back')],
            ],
          ),
        ],
      );
      final crashed = await launcher.call(command, cwd: '/work');
      final client = connect(crashed);
      await client.initialize(clientVersion: '2.0.0');
      final sid = (await client.newSession(cwd: '/work')).sessionId;
      final turn = expectLater(
        client.prompt(sid, const [TextBlock('go')]),
        throwsA(isA<ConnectionClosed>()),
      );
      expect(await crashed.exitCode, 1);
      await turn;

      final again = await launcher.call(command, cwd: '/work');
      expect(await converse(connect(again)), StopReason.endTurn);
      await again.stop();
    });
  });
}
