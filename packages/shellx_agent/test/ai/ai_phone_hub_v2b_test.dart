import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// One of each V2-2b request, with rids 1 to 10.
List<AiMessage> _requests() => [
  const AiConfigGet(sid: 'ep.-1', rid: 1),
  AiConfigSet(sid: 'ep.-1', rid: 2, body: Uint8List.fromList([0x7B, 0x7D])),
  AiBlob(rid: 3, blob: 1, part: 0, parts: 1, data: Uint8List(4)),
  const AiFiles(sid: 'ep.-1', rid: 4, query: 'a'),
  const AiItemPart(sid: 'ep.-1', rid: 5, index: 0, part: 0),
  const AiHistory(sid: 'ep.-1', rid: 6),
  const AiFolder(sid: 'ep.-1', rid: 7, folder: 'ws:a'),
  const AiChanges(sid: 'ep.-1', rid: 8),
  const AiDiff(sid: 'ep.-1', rid: 9, path: 'a.ts'),
  const AiRevert(sid: 'ep.-1', rid: 10),
];

/// What [map] decodes to: an `ai.*` kind this version does not know is an
/// [AiRaw] only when it comes from the wire.
AiMessage _read(Map<String, Object?> map) =>
    decodeBatch(encodeCbor([map])).single as AiMessage;

/// V2-2b B1, B2, B4 (R4): until its feature lands, a V2-2b request gets its
/// one answer, `refused`; so does a newer phone's request (an [AiRaw] with a
/// `rid`). None of them escapes the request budget.
void main() {
  test('every V2-2b request is answered refused, once, with its rid', () {
    final rig = HubRig()..source.add(-1);
    for (final m in _requests()) {
      rig.hub.handle(_phone, m);
    }
    expect(
      [
        for (final r in rig.to(_phone).whereType<AiResult>())
          (r.rid, r.ok, r.code),
      ],
      [for (var rid = 1; rid <= 10; rid++) (rid, false, 'refused')],
    );
  });

  test('a newer phone\'s request (an AiRaw) gets its one answer when it has '
      'a rid; without one, nothing', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, _read({'t': 'ai.later', 'sid': 'ep.-1', 'rid': 9}));
    rig.hub.handle(_phone, _read({'t': 'ai.later', 'sid': 'ep.-1'}));
    rig.hub.handle(_phone, _read({'t': 'ai.later', 'rid': 'nine'}));
    expect(rig.to(_phone), [
      const AiResult(rid: 9, ok: false, code: 'refused'),
    ]);
  });

  test('V2-2b requests spend the budget like the others: over it, busy with '
      'their rid', () {
    final rig = HubRig()..source.add(-1);
    // The rig's clock stands still: the 60 of the burst are all there is.
    for (var rid = 1; rid <= 60; rid++) {
      rig.hub.handle(_phone, AiConfigGet(sid: 'ep.-1', rid: rid));
    }
    rig.hub.handle(_phone, const AiHistory(sid: 'ep.-1', rid: 61));
    rig.hub.handle(_phone, _read({'t': 'ai.later', 'rid': 62}));
    expect(
      [
        for (final r in rig.to(_phone).whereType<AiResult>())
          if (r.rid > 60) (r.rid, r.code),
      ],
      [(61, 'busy'), (62, 'busy')],
    );
  });
}
