import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/ui_mux_responder.dart';

final class _Ui implements UiApi {
  final events_ = StreamController<Map<String, Object?>>.broadcast();
  final seen = <String>[];
  CliFailure? fail;

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) async {
    seen.add(request.type);
    if (fail != null) throw fail!;
    return {'tabs': <Object?>[]};
  }

  @override
  Stream<Map<String, Object?>> events() => events_.stream;
  @override
  Future<void> notifyApp({String? title, required String body}) async {}
  @override
  bool notifyPane(int pane, {String? title, required String body}) => false;
}

void main() {
  late MuxConnection daemon;
  late MuxClient client;
  late UiMuxResponder responder;
  late List<MuxMessage> fromUi;

  setUp(() {
    final (a, b) = MemoryMuxTransport.pair();
    daemon = a;
    fromUi = [];
    daemon.messages.listen(fromUi.add);
    responder = UiMuxResponder(attachWait: const Duration(milliseconds: 200));
    client = MuxClient(b, onRequest: responder.onRequest);
  });

  tearDown(() => client.close());

  test('a daemon request is answered with the window\'s result', () async {
    final ui = _Ui();
    responder.bind(ui, client);
    daemon.send(const MuxMessage('ui.ls', q: 7));
    await pumpEventQueue();
    expect(ui.seen, ['ui.ls']);
    expect(fromUi.single.type, MuxType.result);
    expect(fromUi.single.q, 7);
  });

  test('a request before the window is up waits for it (attach)', () async {
    final ui = _Ui();
    daemon.send(const MuxMessage('ui.ls', q: 1));
    await pumpEventQueue();
    expect(fromUi, isEmpty);
    responder.bind(ui, client);
    await pumpEventQueue();
    expect(fromUi.single.type, MuxType.result);
  });

  test('a window that never attaches: busy, not a hang', () async {
    daemon.send(const MuxMessage('ui.ls', q: 1));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(fromUi.single.type, MuxType.error);
    expect(fromUi.single.get<String>('code'), 'busy');
  });

  test('a refusal travels as its error code', () async {
    final ui = _Ui()..fail = const CliFailure('not_found', 'no such tab');
    responder.bind(ui, client);
    daemon.send(const MuxMessage('ui.focus', q: 2));
    await pumpEventQueue();
    expect(fromUi.single.type, MuxType.error);
    expect(fromUi.single.get<String>('code'), 'not_found');
  });

  test('the window\'s events go to the daemon as ui.event', () async {
    final ui = _Ui();
    responder.bind(ui, client);
    ui.events_.add({'event': 'tab.opened', 'id': 3});
    await pumpEventQueue();
    expect(fromUi.single.type, MuxType.uiEvent);
    expect(fromUi.single.fields['event'], 'tab.opened');
  });

  test('after a restart the events go to the new connection only', () async {
    final ui = _Ui();
    responder.bind(ui, client);
    final (a2, b2) = MemoryMuxTransport.pair();
    final second = <MuxMessage>[];
    a2.messages.listen(second.add);
    final client2 = MuxClient(b2, onRequest: responder.onRequest);
    responder.bind(ui, client2);
    ui.events_.add({'event': 'tab.closed'});
    await pumpEventQueue();
    expect(fromUi, isEmpty);
    expect(second.single.type, MuxType.uiEvent);
    await client2.close();
  });
}
