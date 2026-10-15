import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_core/shellx_core.dart';

import '../support/ai_fakes.dart';
import '../support/ai_phone_rig.dart';
import '../support/ai_tabs.dart';

/// A PNG's first bytes and a little more (all the type check reads).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, //
]);

/// V2-2b B12 on the real window: images from the phone reach the agent.
void main() {
  test('images from the phone reach the agent as image blocks after the text, '
      "as the phone's message", () async {
    final rig = PhoneHubRig(const FakeScenario());
    final tab = openTestAiTab(rig.c, cwd: testAiCwd, select: false);
    final sid = rig.sidOf(tab);
    rig.say(AiAttach(sid: sid));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    rig.say(
      AiBlob(rid: 1, blob: 1, part: 0, parts: 1, mime: 'image/png', data: _png),
    );
    rig.say(AiPrompt(sid: sid, rid: 2, text: 'xem ảnh này', blobs: const [1]));
    expect((await rig.answer(1)).ok, isTrue);
    expect((await rig.answer(2)).ok, isTrue);
    await rig.until(() => rig.fakes.agent().params['session/prompt'] != null);
    final prompt =
        rig.fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'text', 'text': 'xem ảnh này'},
      {'type': 'image', 'data': base64Encode(_png), 'mimeType': 'image/png'},
    ]);
    final user = rig.stateOf(tab).timeline.items.whereType<UserItem>().single;
    expect(user.source, PromptSource.phone);
    expect(user.blocks.whereType<ImageBlock>(), hasLength(1));
  });

  test('an agent that takes no images gets none: no_images', () async {
    final rig = PhoneHubRig(const FakeScenario(image: false));
    final tab = openTestAiTab(rig.c, cwd: testAiCwd, select: false);
    final sid = rig.sidOf(tab);
    rig.say(AiAttach(sid: sid));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    rig.say(
      AiBlob(rid: 1, blob: 1, part: 0, parts: 1, mime: 'image/png', data: _png),
    );
    rig.say(AiPrompt(sid: sid, rid: 2, text: 'xem', blobs: const [1]));
    expect((await rig.answer(2)).code, 'no_images');
    expect(rig.fakes.agent().params['session/prompt'], isNull);
  });

  test("the agent says it takes no images while the phone's images are "
      'encoded: none is sent, and the phone is told no_images', () async {
    final rig = PhoneHubRig(const FakeScenario());
    final tab = openTestAiTab(rig.c, cwd: testAiCwd, select: false);
    final sid = rig.sidOf(tab);
    rig.say(AiAttach(sid: sid));
    await rig.until(() => rig.stateOf(tab).phase == AgentPhase.ready);
    rig.say(
      AiBlob(rid: 1, blob: 1, part: 0, parts: 1, mime: 'image/png', data: _png),
    );
    // The hub lets the prompt go (the agent takes images, as far as it said);
    // the window encodes the images — it always yields to the event loop
    // first — and `initialize` is answered again meanwhile (here: the state
    // says so, before anything else runs).
    rig.say(AiPrompt(sid: sid, rid: 2, text: 'xem', blobs: const [1]));
    rig
        .stateOf(tab)
        .setAgent(
          const InitializeResult(
            protocolVersion: 1,
            capabilities: AgentCapabilities(
              prompt: PromptCapabilities(image: false),
            ),
          ),
        );
    expect((await rig.answer(2)).code, 'no_images');
    expect(rig.fakes.agent().params['session/prompt'], isNull);
    expect(rig.stateOf(tab).timeline.items.whereType<UserItem>(), isEmpty);
  });
}
