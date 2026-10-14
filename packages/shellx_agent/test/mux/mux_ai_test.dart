import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// V2-2 D1: the background service forwards `ai.*` to the window.
void main() {
  group('background service (mux)', () {
    test('no window: unavailable; a window serves: forwarded both ways; '
        'it quits: lists unavailable, mirrors closed; a new one re-lists', () {
      final pushes = <AiPush>[];
      final forwarder = MuxAiForwarder(onPush: pushes.add);
      final out = <OutboundMessage>[];
      forwarder.outbound.listen(out.add);
      forwarder.handle(phone, const AiList());
      expect((out.single.message as AiListResult).available, isFalse);

      final toUi = <MuxMessage>[];
      final window = Object();
      forwarder.serve(window, toUi.add);
      expect(toUi.single.type, MuxType.aiIn); // the phone that listed
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      expect(toUi.last.fields['m'], phone);

      MuxMessage outMsg(AppMessage m) => MuxMessage(
        MuxType.aiOut,
        fields: {'m': phone, 'b': encodeCbor(m.toMap())},
      );
      forwarder.fromUi(window, outMsg(const AiResult(rid: 1, ok: true)));
      forwarder.fromUi(
        window,
        outMsg(const AiPrompt(sid: 'e.-1', rid: 2, text: 'x')),
      );
      forwarder.fromUi(window, outMsg(const SessionReset(id: 1)));
      forwarder.fromUi(Object(), outMsg(const AiResult(rid: 3, ok: true)));
      expect(out.map((o) => o.message.type), ['ai.list.result', 'ai.result']);

      forwarder.fromUi(
        window,
        MuxMessage(
          MuxType.aiPush,
          fields: const AiPush(
            kind: AiPushKind.needsInput,
            agentName: 'Claude',
            sid: 'e.-1',
          ).toFields(),
        ),
      );
      expect(pushes.single.sid, 'e.-1');

      forwarder.unserve(window);
      expect(out.skip(2).map((o) => o.message.type), [
        'ai.list.result',
        'ai.closed',
      ]);
      expect((out[3].message as AiClosed).reason, 'desktop_closed');

      final again = <MuxMessage>[];
      forwarder.serve(Object(), again.add);
      expect(again.single.type, MuxType.aiIn);
      forwarder.phoneGone(phone);
      expect(again.last.type, MuxType.aiGone);
    });

    test('the window side: ai.in reaches the hub, its answers go back as '
        'ai.out, and it serves at once', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final client = MuxClient(a);
      final fromWindow = <MuxMessage>[];
      b.messages.listen(fromWindow.add);
      final rig = HubRig()..source.add(-1);
      final binding = MuxAiBinding(client, rig.hub);
      await Future<void>.delayed(Duration.zero);
      expect(fromWindow.single.type, MuxType.aiServe);
      b.send(
        MuxMessage(
          MuxType.aiIn,
          fields: {'m': phone, 'b': encodeCbor(const AiList().toMap())},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final reply = fromWindow.last;
      expect((reply.type, reply.fields['m']), (MuxType.aiOut, phone));
      final message = AppMessage.fromMap(
        decodeCbor(reply.fields['b']! as dynamic) as Map<Object?, Object?>,
      );
      expect((message as AiListResult).available, isTrue);
      await binding.dispose();
      await client.close();
    });
  });
}
