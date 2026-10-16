import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:test/test.dart';

import '../support/runtime_rig.dart';

List<PromptSource> _sources(RuntimeRig r) => [
  for (final u in r.state.timeline.items.whereType<UserItem>()) u.source,
];

/// V2-2b B24: `AiRuntime.send` carries who wrote the prompt into its turn,
/// also when the prompt waited in the queue.
void main() {
  test(
    'a phone\'s prompt starts a turn the timeline says is the phone\'s',
    () async {
      final r = RuntimeRig(
        first: FakeScenario(
          turns: [
            [FakeSteps.text('ok')],
          ],
        ),
      );
      addTearDown(r.dispose);
      await r.runtime.start();
      expect(
        await r.runtime.send(const [
          TextBlock('a'),
        ], source: PromptSource.phone),
        isTrue,
      );
      await r.until(() => r.turnEnds.length == 1);
      expect(await r.runtime.send(const [TextBlock('b')]), isTrue);
      await r.until(() => r.turnEnds.length == 2);
      expect(_sources(r), [PromptSource.phone, PromptSource.computer]);
    },
  );

  test('queued prompts go out in order, each as its own writer\'s', () async {
    final r = RuntimeRig(
      first: FakeScenario(
        turns: [
          [FakeSteps.sleep(30), FakeSteps.text('ok')],
        ],
      ),
    );
    addTearDown(r.dispose);
    await r.runtime.start();
    expect(await r.runtime.send(const [TextBlock('a')]), isTrue);
    expect(
      await r.runtime.send(const [TextBlock('b')], source: PromptSource.phone),
      isTrue,
    );
    expect(await r.runtime.send(const [TextBlock('c')]), isTrue);
    expect(r.state.queue.map((q) => q.source), [
      PromptSource.phone,
      PromptSource.computer,
    ]);
    await r.until(() => r.turnEnds.length == 3);
    expect(_sources(r), [
      PromptSource.computer,
      PromptSource.phone,
      PromptSource.computer,
    ]);
  });

  test('a prompt sent while the agent is stopped waits with its source and '
      'goes out with it once the agent runs', () async {
    final r = RuntimeRig(
      first: FakeScenario(
        turns: [
          [FakeSteps.text('ok')],
        ],
      ),
    );
    addTearDown(r.dispose);
    expect(
      await r.runtime.send(const [TextBlock('a')], source: PromptSource.phone),
      isTrue,
    );
    await r.until(() => r.turnEnds.length == 1);
    expect(_sources(r), [PromptSource.phone]);
  });
}
