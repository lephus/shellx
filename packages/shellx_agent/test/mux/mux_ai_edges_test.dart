import 'dart:async';
import 'dart:typed_data';

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

/// Every kind a desktop sends to a phone, and every kind a phone sends.
final _toPhone = <AiMessage>[
  AiListResult(available: true, body: Uint8List.fromList([1, 2])),
  AiSnapshot(sid: 'e.-1', seq: 1, body: Uint8List.fromList([1, 2])),
  AiUpdate(sid: 'e.-1', seq: 2, body: Uint8List.fromList([1, 2])),
  const AiClosed(sid: 'e.-1', reason: 'gone'),
  const AiResult(rid: 1, ok: true),
];
final _toDesktop = <AiMessage>[
  const AiList(),
  const AiAttach(sid: 'e.-1'),
  const AiDetach(sid: 'e.-1'),
  const AiAck(sid: 'e.-1', seq: 1),
  const AiEarlier(sid: 'e.-1', before: 3),
  const AiPrompt(sid: 'e.-1', rid: 1, text: 'x'),
  const AiAnswer(sid: 'e.-1', rid: 2, permission: 1, option: 'allow'),
  const AiCancel(sid: 'e.-1', rid: 3),
  const AiForceStop(sid: 'e.-1', rid: 4),
  const AiUnqueue(sid: 'e.-1', rid: 5, queued: 1),
  const AiOpen(rid: 6, agent: 'claude', folder: 'ws:a'),
];

MuxMessage _carry(String type, String mobileId, AiMessage m) =>
    MuxMessage(type, fields: {'m': mobileId, 'b': encodeCbor(m.toMap())});

AiMessage? _decoded(MuxMessage m) {
  final map = decodeCbor(m.fields['b']! as Uint8List)! as Map<Object?, Object?>;
  return AppMessage.fromMap(map) as AiMessage?;
}

/// A snapshot whose one-message batch is exactly [bytes] long.
AiSnapshot _snapshotOf(int bytes) {
  var body = bytes;
  while (true) {
    final m = AiSnapshot(sid: 'e.-1', seq: 1, body: Uint8List(body));
    final size = encodeBatch([m]).length;
    if (size == bytes) return m;
    body -= size - bytes;
  }
}

/// The longest session id whose `ai.attach` still fits one sealed batch.
String _longestAttachableSid() {
  var length = kMaxSealedBatchBytes;
  while (encodeBatch([AiAttach(sid: 'x' * length)]).length >
      kMaxSealedBatchBytes) {
    length--;
  }
  return 'x' * length;
}

int _batchSize(AiMessage m) => encodeBatch([m]).length;

/// A hub that records what it is told.
final class _Hub implements AiEndpoint {
  final calls = <String>[];
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) =>
      calls.add('handle $mobileId ${message.type}');

  @override
  void phoneGone(String mobileId) => calls.add('gone $mobileId');

  @override
  void allPhonesGone() => calls.add('all gone');

  void say(String mobileId, AiMessage message) =>
      _out.add(OutboundMessage(mobileId, message));
}

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

/// V2-2 D1: the edges `mux_ai_test.dart` and `mux_ai_server_test.dart` leave
/// open — direction, one sealed batch, a phone that leaves twice, a window
/// that comes and goes, a push that fails, old and new peers.
void main() {
  group('MuxAiForwarder', () {
    late MuxAiForwarder forwarder;
    late List<OutboundMessage> out;
    late List<MuxMessage> toUi;
    late List<AiPush> pushes;
    late Object window;

    setUp(() {
      pushes = [];
      forwarder = MuxAiForwarder(onPush: pushes.add);
      out = [];
      forwarder.outbound.listen(out.add);
      toUi = [];
      window = Object();
    });

    test('a phone cannot send what only a desktop sends: it goes nowhere, '
        'with a window or without', () {
      for (final m in _toPhone) {
        forwarder.handle(phone, m);
      }
      forwarder.serve(window, toUi.add);
      for (final m in _toPhone) {
        forwarder.handle(phone, m);
      }
      expect(toUi, isEmpty);
      expect(out, isEmpty);
    });

    test('everything a phone does send reaches the window whole, with the '
        'phone\'s id', () {
      forwarder.serve(window, toUi.add);
      for (final m in _toDesktop) {
        forwarder.handle(phone, m);
      }
      expect(toUi.map((m) => m.type), everyElement(MuxType.aiIn));
      expect(toUi.map((m) => m.fields['m']), everyElement(phone));
      expect(toUi.map(_decoded), _toDesktop);
    });

    test('from the window only what a desktop sends goes on to a phone', () {
      forwarder.serve(window, toUi.add);
      for (final m in [..._toPhone, ..._toDesktop]) {
        forwarder.fromUi(window, _carry(MuxType.aiOut, phone, m));
      }
      expect(out.map((o) => o.message), _toPhone);
      expect(out.map((o) => o.mobileId), everyElement(phone));
    });

    test('a message that fills one sealed batch goes on, one byte more is '
        'dropped, and the next one still passes', () {
      forwarder.serve(window, toUi.add);
      final fits = _snapshotOf(kMaxSealedBatchBytes);
      final tooBig = _snapshotOf(kMaxSealedBatchBytes + 1);
      final largestBody = AiSnapshot(
        sid: 'e.-1',
        seq: 3,
        body: Uint8List(kAiMaxBodyBytes),
      );
      for (final m in [tooBig, fits, largestBody]) {
        forwarder.fromUi(window, _carry(MuxType.aiOut, phone, m));
      }
      expect(out.map((o) => o.message), [fits, largestBody]);
    });

    test('an attach answered "closed" at once is no open mirror: a window '
        'that comes and goes says nothing more of it', () {
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      expect(
        out.single.message,
        const AiClosed(sid: 'e.-1', reason: 'unavailable'),
      );
      forwarder.serve(window, toUi.add);
      forwarder.unserve(window);
      expect(out, hasLength(1));
    });

    test('a mirror the window closed is not closed again when it quits', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      forwarder.handle(phone, const AiAttach(sid: 'e.-2'));
      forwarder.handle(tablet, const AiAttach(sid: 'e.-3'));
      forwarder.fromUi(
        window,
        _carry(
          MuxType.aiOut,
          phone,
          const AiClosed(sid: 'e.-1', reason: 'gone'),
        ),
      );
      forwarder.handle(tablet, const AiDetach(sid: 'e.-3'));
      out.clear();
      forwarder.unserve(window);
      expect(out.map((o) => (o.mobileId, o.message)), [
        (phone, const AiClosed(sid: 'e.-2', reason: 'desktop_closed')),
      ]);
    });

    test('mirrors closed when a window quit are not closed again when the '
        'next window quits', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiList());
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      forwarder.unserve(window);
      expect(out.map((o) => o.message.type), ['ai.list.result', 'ai.closed']);
      out.clear();
      final next = Object();
      forwarder.serve(next, toUi.add);
      forwarder.unserve(next);
      // The phone still lists, so it hears "unavailable" again; the mirror
      // is closed already.
      expect(out.map((o) => o.message.type), ['ai.list.result']);
    });

    test('nothing it sends can pass one sealed batch, not even the echo of '
        'a long session id', () {
      final sid = _longestAttachableSid();
      expect(_batchSize(AiAttach(sid: sid)), kMaxSealedBatchBytes);
      // The preconditions: both echoes would not fit.
      expect(
        _batchSize(AiClosed(sid: sid, reason: 'unavailable')),
        greaterThan(kMaxSealedBatchBytes),
      );
      expect(
        _batchSize(AiClosed(sid: sid, reason: 'desktop_closed')),
        greaterThan(kMaxSealedBatchBytes),
      );

      forwarder.handle(phone, AiAttach(sid: sid)); // no window
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, AiAttach(sid: sid));
      forwarder.unserve(window);
      expect(toUi, hasLength(1)); // the attach itself fits, so it is passed
      for (final o in out) {
        expect(
          _batchSize(o.message as AiMessage),
          lessThanOrEqualTo(kMaxSealedBatchBytes),
        );
      }
    });

    test('a phone that leaves twice, or one never heard of, leaves nothing '
        'behind', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiList());
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      forwarder.phoneGone(phone);
      forwarder.phoneGone(phone);
      forwarder.phoneGone(tablet);
      expect(
        toUi.where((m) => m.type == MuxType.aiGone).map((m) => m.fields['m']),
        [phone, phone, tablet],
      );
      forwarder.unserve(window);
      expect(out, isEmpty); // nobody is left to tell
      final again = <MuxMessage>[];
      forwarder.serve(Object(), again.add);
      expect(again, isEmpty); // nobody to list again
    });

    test('a phone that left while no window served is not listed for the '
        'next one', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiList());
      forwarder.handle(tablet, const AiList());
      forwarder.unserve(window);
      forwarder.phoneGone(phone); // while no window serves
      forwarder.phoneGone(phone);
      final again = <MuxMessage>[];
      forwarder.serve(Object(), again.add);
      expect(again.map((m) => m.fields['m']), [tablet]);
      expect(_decoded(again.single), const AiList());
    });

    test('a phone that comes back is told once, as the one phone it is', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiList());
      forwarder.phoneGone(phone);
      forwarder.handle(phone, const AiList());
      forwarder.unserve(window);
      expect(out.map((o) => (o.mobileId, o.message.type)), [
        (phone, 'ai.list.result'),
      ]);
    });

    test('allPhonesGone forgets every phone and tells the window, once, '
        'without an id', () {
      forwarder.serve(window, toUi.add);
      forwarder.handle(phone, const AiList());
      forwarder.handle(tablet, const AiAttach(sid: 'e.-1'));
      toUi.clear();
      forwarder.allPhonesGone();
      forwarder.allPhonesGone();
      expect(toUi.map((m) => m.type), [MuxType.aiGone, MuxType.aiGone]);
      expect(toUi.map((m) => m.fields.containsKey('m')), everyElement(false));
      forwarder.unserve(window);
      expect(out, isEmpty);
      final again = <MuxMessage>[];
      forwarder.serve(Object(), again.add);
      expect(again, isEmpty);
    });

    test('only the window that serves counts: another one\'s unserve or '
        'ai.out changes nothing', () {
      final reply = _carry(
        MuxType.aiOut,
        phone,
        const AiResult(rid: 1, ok: true),
      );
      forwarder.serve(window, toUi.add);
      forwarder.unserve(Object());
      expect(forwarder.serving, isTrue);
      expect(out, isEmpty);

      final next = Object();
      final toNext = <MuxMessage>[];
      forwarder.serve(next, toNext.add);
      forwarder.unserve(window); // the old one, late
      expect(forwarder.serving, isTrue);
      forwarder.fromUi(window, reply);
      expect(out, isEmpty);
      forwarder.fromUi(next, reply);
      expect(out, hasLength(1));
      forwarder.unserve(next);
      forwarder.fromUi(next, reply); // after it left
      expect(forwarder.serving, isFalse);
      expect(out, hasLength(1));
    });

    test('an ai.out it cannot read is dropped, and does not throw', () {
      forwarder.serve(window, toUi.add);
      final result = encodeCbor(const AiResult(rid: 1, ok: true).toMap());
      final unreadable = <Map<String, Object?>>[
        {},
        {'m': phone},
        {'m': phone, 'b': 'text'},
        {
          'm': phone,
          'b': Uint8List.fromList([0xff, 0xff]),
        },
        {
          'm': phone,
          'b': encodeCbor([1, 2]),
        },
        {
          'm': phone,
          'b': encodeCbor({'t': 'ai.future', 'x': 1}),
        },
        {
          'm': phone,
          'b': encodeCbor({'t': 'ai.result'}),
        },
        {'m': 7, 'b': result},
        {'b': result},
      ];
      for (final fields in unreadable) {
        expect(
          () => forwarder.fromUi(
            window,
            MuxMessage(MuxType.aiOut, fields: fields),
          ),
          returnsNormally,
        );
      }
      expect(out, isEmpty);
    });

    test('ai.push: only from the window that serves, only whole; a push '
        'callback that throws does not escape', () {
      const push = AiPush(
        kind: AiPushKind.done,
        agentName: 'Claude',
        sid: 'e.-1',
        turn: 2,
        elapsed: Duration(seconds: 95),
      );
      final fields = push.toFields();
      forwarder.fromUi(window, MuxMessage(MuxType.aiPush, fields: fields));
      forwarder.serve(window, toUi.add);
      forwarder.fromUi(Object(), MuxMessage(MuxType.aiPush, fields: fields));
      forwarder.fromUi(
        window,
        MuxMessage(MuxType.aiPush, fields: {...fields, 'kind': 'loud'}),
      );
      forwarder.fromUi(
        window,
        MuxMessage(MuxType.aiPush, fields: {...fields, 'name': 7}),
      );
      expect(pushes, isEmpty);
      forwarder.fromUi(window, MuxMessage(MuxType.aiPush, fields: fields));
      expect(
        (pushes.single.kind, pushes.single.sid, pushes.single.turn),
        (AiPushKind.done, 'e.-1', 2),
      );
      expect(pushes.single.elapsed, const Duration(seconds: 95));

      final failing = MuxAiForwarder(
        onPush: (_) => throw StateError('no account'),
      )..serve(window, toUi.add);
      expect(
        () =>
            failing.fromUi(window, MuxMessage(MuxType.aiPush, fields: fields)),
        returnsNormally,
      );
    });
  });

  group('MuxAiBinding', () {
    late MuxConnection daemon;
    late MuxClient client;
    late _Hub hub;
    late MuxAiBinding binding;
    late List<MuxMessage> fromWindow;

    setUp(() {
      final (a, b) = MemoryMuxTransport.pair();
      client = MuxClient(a);
      daemon = b;
      fromWindow = [];
      daemon.messages.listen(fromWindow.add);
      hub = _Hub();
      binding = MuxAiBinding(client, hub);
    });

    tearDown(() async {
      await binding.dispose();
      await client.close();
    });

    test('ai.in reaches the hub with the phone\'s id; ai.gone tells it that '
        'one phone, or every phone, left', () async {
      daemon
        ..send(_carry(MuxType.aiIn, phone, const AiList()))
        ..send(_carry(MuxType.aiIn, tablet, const AiAttach(sid: 'ep.1')))
        ..send(MuxMessage(MuxType.aiGone, fields: {'m': phone}))
        ..send(const MuxMessage(MuxType.aiGone));
      await pumpEventQueue();
      expect(hub.calls, [
        'handle $phone ai.list',
        'handle $tablet ai.attach',
        'gone $phone',
        'all gone',
      ]);
    });

    test('an ai.in it cannot read never reaches the hub', () async {
      final list = encodeCbor(const AiList().toMap());
      final unreadable = <Map<String, Object?>>[
        {},
        {'m': phone},
        {'b': list},
        {'m': phone, 'b': 'text'},
        {
          'm': phone,
          'b': Uint8List.fromList([0xff, 0xff]),
        },
        {'m': phone, 'b': encodeCbor('ai.list')},
        {
          'm': phone,
          'b': encodeCbor({'t': 'ai.future'}),
        },
        {'m': phone, 'b': encodeCbor(const SessionReset(id: 1).toMap())},
        {'m': 7, 'b': list},
      ];
      for (final fields in unreadable) {
        daemon.send(MuxMessage(MuxType.aiIn, fields: fields));
      }
      await pumpEventQueue();
      expect(hub.calls, isEmpty);
    });

    test('what the hub says goes to the service as ai.out, however big a '
        'body the hub may send', () async {
      final largest = AiSnapshot(
        sid: 'ep.1',
        seq: 4,
        body: Uint8List(kAiMaxBodyBytes),
      );
      hub
        ..say(tablet, const AiResult(rid: 5, ok: false, code: 'busy'))
        ..say(phone, largest);
      await pumpEventQueue();
      final sent = fromWindow.where((m) => m.type == MuxType.aiOut).toList();
      expect(sent.map((m) => m.fields['m']), [tablet, phone]);
      expect(sent.map(_decoded), [
        const AiResult(rid: 5, ok: false, code: 'busy'),
        largest,
      ]);
    });

    test('dispose: every phone is gone, and neither side reaches the other '
        'any more', () async {
      await binding.dispose();
      expect(hub.calls, ['all gone']);
      daemon.send(_carry(MuxType.aiIn, phone, const AiList()));
      hub.say(phone, const AiResult(rid: 1, ok: true));
      await pumpEventQueue();
      expect(hub.calls, ['all gone']);
      expect(fromWindow.map((m) => m.type), [MuxType.aiServe]);
    });

    test('muxAiPushSink: ai.push carries the push, whole, to the '
        'service\'s own push', () async {
      final pushes = <AiPush>[];
      final forwarder = MuxAiForwarder(onPush: pushes.add);
      final owner = Object();
      forwarder.serve(owner, (_) {});
      daemon.messages.listen((m) => forwarder.fromUi(owner, m));
      muxAiPushSink(client)(
        const AiPush(
          kind: AiPushKind.needsInput,
          agentName: 'Claude',
          sid: 'ep.1',
          detail: 'Sửa src/main.ts',
          turn: 3,
          elapsed: Duration(seconds: 95),
        ),
      );
      await pumpEventQueue();
      final push = pushes.single;
      expect(
        (push.kind, push.agentName, push.sid, push.detail, push.turn),
        (AiPushKind.needsInput, 'Claude', 'ep.1', 'Sửa src/main.ts', 3),
      );
      expect(push.elapsed, const Duration(seconds: 95));
    });
  });

  group('the service and the window over the real link', () {
    late SessionRig rig;
    late TestListener listener;
    late MuxServer server;
    late MuxAiForwarder forwarder;
    late List<OutboundMessage> out;
    late List<AiPush> pushes;

    setUp(() {
      rig = SessionRig();
      listener = TestListener();
      pushes = [];
      forwarder = MuxAiForwarder(onPush: pushes.add);
      out = [];
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
    });

    tearDown(() async => server.close());

    Future<void> request(MuxConnection ui, int q) async {
      final reply = ui.messages.firstWhere((m) => m.q == q);
      ui.send(MuxMessage(MuxType.sessionsList, q: q));
      expect((await reply).type, MuxType.result);
    }

    test('a window that never said ai.serve gets nothing and answers '
        'nothing: phones hear "unavailable"', () async {
      final (ui, inbox) = await _ui(listener);
      forwarder.handle(phone, const AiList());
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      forwarder.phoneGone(phone);
      forwarder.allPhonesGone();
      ui.send(_carry(MuxType.aiOut, phone, const AiResult(rid: 1, ok: true)));
      await request(ui, 1);
      expect(inbox.where((m) => m.type.startsWith('ai.')), isEmpty);
      expect(out.map((o) => o.message.type), ['ai.list.result', 'ai.closed']);
      expect(forwarder.serving, isFalse);
    });

    test('a new window gets the phones that listed, listed again', () async {
      final (first, _) = await _ui(listener);
      first.send(const MuxMessage(MuxType.aiServe));
      await pumpEventQueue();
      forwarder.handle(phone, const AiList());
      forwarder.handle(tablet, const AiList());
      forwarder.handle(tablet, const AiAttach(sid: 'e.-1'));
      await first.close();
      await pumpEventQueue();
      expect(forwarder.serving, isFalse);
      expect(
        out.map((o) => (o.mobileId, o.message.type)),
        containsAll([
          (phone, 'ai.list.result'),
          (tablet, 'ai.list.result'),
          (tablet, 'ai.closed'),
        ]),
      );

      final (second, inbox) = await _ui(listener);
      second.send(const MuxMessage(MuxType.aiServe));
      await pumpEventQueue();
      expect(forwarder.serving, isTrue);
      final listed = inbox.where((m) => m.type == MuxType.aiIn);
      expect(
        listed.map((m) => m.fields['m']),
        unorderedEquals([phone, tablet]),
      );
      expect(listed.map(_decoded), everyElement(const AiList()));
    });

    const push = AiPush(
      kind: AiPushKind.needsInput,
      agentName: 'Claude',
      sid: 'e.-1',
      detail: 'Sửa src/main.ts',
    );

    test('the window\'s ai.push is the service\'s own push', () async {
      final (ui, _) = await _ui(listener);
      ui.send(const MuxMessage(MuxType.aiServe));
      ui.send(MuxMessage(MuxType.aiPush, fields: push.toFields()));
      await pumpEventQueue();
      expect(pushes.single.detail, 'Sửa src/main.ts');
    });

    test('a push that cannot be sent is lost, the link goes on', () async {
      server.ai = MuxAiForwarder(onPush: (_) => throw StateError('no account'));
      final (ui, inbox) = await _ui(listener);
      ui.send(const MuxMessage(MuxType.aiServe));
      ui.send(MuxMessage(MuxType.aiPush, fields: push.toFields()));
      await request(ui, 1);
      expect(inbox.where((m) => m.type == MuxType.error), isEmpty);
    });

    test('closing the service closes the phones\' mirrors', () async {
      final (ui, _) = await _ui(listener);
      ui.send(const MuxMessage(MuxType.aiServe));
      await pumpEventQueue();
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      await server.close();
      await pumpEventQueue();
      expect(out.single.message, isA<AiClosed>());
      expect((out.single.message as AiClosed).reason, 'desktop_closed');
    });

    test('an older window (it never serves) is told nothing, whatever the '
        'phones do', () async {
      final (ui, inbox) = await _ui(listener);
      forwarder.handle(phone, const AiList());
      forwarder.handle(phone, const AiAttach(sid: 'e.-1'));
      forwarder.handle(phone, const AiPrompt(sid: 'e.-1', rid: 1, text: 'x'));
      forwarder.phoneGone(phone);
      await request(ui, 1);
      expect(inbox.where((m) => m.type.startsWith('ai.')), isEmpty);
      expect(out.map((o) => o.message.type), [
        'ai.list.result',
        'ai.closed',
        'ai.result',
      ]);
      expect((out.last.message as AiResult).code, 'unavailable');
    });
  });

  test('an older service (no forwarder) ignores every ai.* message of the '
      'window, push and the service\'s own kinds included', () async {
    final rig = SessionRig();
    final listener = TestListener();
    final server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: _self,
      onQuit: () async {},
    )..serve(listener);
    addTearDown(server.close);
    final (ui, inbox) = await _ui(listener);
    ui
      ..send(const MuxMessage(MuxType.aiServe))
      ..send(_carry(MuxType.aiOut, phone, const AiList()))
      ..send(_carry(MuxType.aiIn, phone, const AiList()))
      ..send(const MuxMessage(MuxType.aiGone))
      ..send(
        MuxMessage(
          MuxType.aiPush,
          fields: const AiPush(
            kind: AiPushKind.done,
            agentName: 'Claude',
            sid: 'e.-1',
          ).toFields(),
        ),
      );
    final reply = ui.messages.firstWhere((m) => m.q == 1);
    ui.send(const MuxMessage(MuxType.sessionsList, q: 1));
    expect((await reply).type, MuxType.result);
    await pumpEventQueue();
    expect(inbox.where((m) => m.type == MuxType.error), isEmpty);
    expect(inbox.where((m) => m.type.startsWith('ai.')), isEmpty);
  });
}
