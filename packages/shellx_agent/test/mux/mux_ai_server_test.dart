import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

const _self = MuxPeerInfo(
  protocol: kMuxProtocol,
  app: '2.0.0',
  instance: 'inst1',
  pid: 42,
);

Future<(MuxConnection, List<MuxMessage>)> _ui(TestListener l) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  l.push(daemonSide);
  final peer = await clientHandshake(
    client,
    secret: secret,
    app: '2.0.0',
    role: 'ui',
  );
  final inbox = [...peer.early];
  client.messages.listen(inbox.add);
  return (client, inbox);
}

/// V2-2 D1: the background service and the window over the real mux link.
void main() {
  late SessionRig rig;
  late TestListener listener;
  late MuxServer server;

  setUp(() {
    rig = SessionRig();
    listener = TestListener();
  });

  tearDown(() async => server.close());

  test('a window that serves gets the phones\' ai.* and answers them; when '
      'it goes, phones hear the window closed', () async {
    final forwarder = MuxAiForwarder();
    final out = <OutboundMessage>[];
    forwarder.outbound.listen(out.add);
    server =
        MuxServer(
            sessions: rig.manager,
            secret: secret,
            self: _self,
            onQuit: () async {},
          )
          ..ai = forwarder
          ..serve(listener);
    final (ui, inbox) = await _ui(listener);
    ui.send(const MuxMessage(MuxType.aiServe));
    await pumpEventQueue();
    expect(forwarder.serving, isTrue);
    forwarder.handle(phone, const AiList());
    forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
    await pumpEventQueue();
    expect(inbox.where((m) => m.type == MuxType.aiIn), hasLength(2));
    ui.send(
      MuxMessage(
        MuxType.aiOut,
        fields: {
          'm': phone,
          'b': encodeCbor(const AiResult(rid: 1, ok: true).toMap()),
        },
      ),
    );
    await pumpEventQueue();
    expect(out.single.message, const AiResult(rid: 1, ok: true));
    await ui.close();
    await pumpEventQueue();
    expect(forwarder.serving, isFalse);
    expect(out.skip(1).map((o) => o.message.type), [
      'ai.list.result',
      'ai.closed',
    ]);
  });

  test('an older service (no forwarder) ignores the window\'s ai.* '
      'messages and keeps answering', () async {
    server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: _self,
      onQuit: () async {},
    )..serve(listener);
    final (ui, inbox) = await _ui(listener);
    ui.send(const MuxMessage(MuxType.aiServe));
    ui.send(
      MuxMessage(
        MuxType.aiOut,
        fields: {
          'm': phone,
          'b': encodeCbor({'t': 'ai.list'}),
        },
      ),
    );
    final reply = ui.messages.firstWhere((m) => m.q == 1);
    ui.send(const MuxMessage(MuxType.sessionsList, q: 1));
    expect((await reply).type, MuxType.result);
    expect(inbox.where((m) => m.type == MuxType.error), isEmpty);
  });
}
