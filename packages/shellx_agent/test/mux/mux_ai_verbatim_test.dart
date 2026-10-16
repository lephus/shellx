import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

/// What [map] decodes to (an [AiRaw] for a kind this version does not know,
/// carrying [map] as it came).
AiMessage _read(Map<String, Object?> map) =>
    decodeBatch(encodeCbor([map])).single as AiMessage;

/// The window's `ai.out` carrying [map] for [phone].
MuxMessage _out(Map<String, Object?> map) =>
    MuxMessage(MuxType.aiOut, fields: {'m': phone, 'b': encodeCbor(map)});

/// What [m] puts on the phone's wire.
Object? _onWire(AiMessage m) => (decodeCbor(encodeBatch([m]))! as List).single;

/// One of each V2-2b request, with rids 1 to 10.
List<AiMessage> _requests() => [
  const AiConfigGet(sid: 'e.-1', rid: 1),
  AiConfigSet(sid: 'e.-1', rid: 2, body: Uint8List.fromList([0x7B, 0x7D])),
  AiBlob(rid: 3, blob: 1, part: 0, parts: 1, data: Uint8List(4)),
  const AiFiles(sid: 'e.-1', rid: 4, query: 'a'),
  const AiItemPart(sid: 'e.-1', rid: 5, index: 0, part: 0),
  const AiHistory(sid: 'e.-1', rid: 6),
  const AiFolder(sid: 'e.-1', rid: 7, folder: 'ws:a'),
  const AiChanges(sid: 'e.-1', rid: 8),
  const AiDiff(sid: 'e.-1', rid: 9, path: 'a.ts'),
  const AiRevert(sid: 'e.-1', rid: 10),
];

/// V2-2b B2 (R2, R4), Review Focus 2: the background service passes `ai.*`
/// on as it came, a kind it does not know the way it came; without a window
/// every request still gets its one answer at once.
void main() {
  late MuxAiForwarder forwarder;
  late List<OutboundMessage> out;
  late List<MuxMessage> toUi;
  late Object window;

  setUp(() {
    forwarder = MuxAiForwarder();
    out = [];
    forwarder.outbound.listen(out.add);
    toUi = [];
    window = Object();
  });

  test('a window\'s message of a kind this service does not know reaches the '
      'phone as it was sent', () {
    forwarder.serve(window, toUi.add);
    final later = <String, Object?>{
      't': 'ai.later',
      'rid': 4,
      'x': [
        1,
        {'y': true},
      ],
    };
    forwarder.fromUi(window, _out(later));
    expect(out.single.mobileId, phone);
    expect(out.single.message, isA<AiRaw>());
    expect(_onWire(out.single.message as AiMessage), later);
  });

  test('a known kind keeps the keys this service does not know, both '
      'ways', () {
    forwarder.serve(window, toUi.add);
    final result = <String, Object?>{
      't': 'ai.result',
      'rid': 1,
      'ok': false,
      'code': 'confirm',
      'later': 'x',
    };
    forwarder.fromUi(window, _out(result));
    expect(_onWire(out.single.message as AiMessage), result);

    final prompt = <String, Object?>{
      't': 'ai.prompt',
      'sid': 'e.-1',
      'rid': 2,
      'text': 'hi',
      'tone': 'calm',
    };
    forwarder.handle(phone, _read(prompt));
    final carried = toUi.single;
    expect(carried.type, MuxType.aiIn);
    expect(decodeCbor(carried.fields['b']! as Uint8List), prompt);
  });

  test('a phone\'s kind this service does not know goes to the window as it '
      'came', () {
    forwarder.serve(window, toUi.add);
    final later = <String, Object?>{'t': 'ai.later', 'sid': 'e.-1', 'rid': 3};
    forwarder.handle(phone, _read(later));
    expect(decodeCbor(toUi.single.fields['b']! as Uint8List), later);
    expect(out, isEmpty);
  });

  test('without a window, every V2-2b request and a newer phone\'s request '
      'with a rid are answered unavailable at once; one without a rid gets '
      'nothing', () {
    for (final m in _requests()) {
      forwarder.handle(phone, m);
    }
    forwarder.handle(phone, _read({'t': 'ai.later', 'rid': 11}));
    forwarder.handle(phone, _read({'t': 'ai.later', 'sid': 'e.-1'}));
    expect(
      [for (final o in out) (o.message as AiResult).rid],
      [for (var rid = 1; rid <= 11; rid++) rid],
    );
    expect(out.map((o) => (o.message as AiResult).code).toSet(), {
      'unavailable',
    });
  });

  test('the slot of a process whose window has no hub yet answers them '
      'unavailable too', () {
    final slot = AiEndpointSlot();
    final sent = <OutboundMessage>[];
    slot.outbound.listen(sent.add);
    for (final m in _requests()) {
      slot.handle(phone, m);
    }
    slot.handle(phone, _read({'t': 'ai.later', 'rid': 11}));
    expect(sent, hasLength(11));
    expect(sent.map((o) => (o.message as AiResult).code).toSet(), {
      'unavailable',
    });
  });

  test('a window\'s message of a kind this service does not know, over one '
      'sealed batch, is dropped, never sent', () {
    forwarder.serve(window, toUi.add);
    expect(
      () => forwarder.fromUi(
        window,
        _out({'t': 'ai.later', 'data': Uint8List(kMaxSealedBatchBytes)}),
      ),
      returnsNormally,
    );
    expect(out, isEmpty);
  });

  test('a desktop → phone kind from a phone still goes nowhere, and a phone '
      '→ desktop kind from the window too', () {
    forwarder.serve(window, toUi.add);
    forwarder.handle(phone, const AiResult(rid: 1, ok: true));
    forwarder.fromUi(
      window,
      _out(const AiConfigGet(sid: 'e.-1', rid: 2).toMap()),
    );
    expect(toUi, isEmpty);
    expect(out, isEmpty);
  });
}
