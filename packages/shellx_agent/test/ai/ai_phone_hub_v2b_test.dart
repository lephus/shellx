import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// One of each V2-2b request (rids 1 to 10), with the feature whose task
/// makes the hub take it.
List<(int, AiMessage, String)> _requests() => [
  (1, const AiConfigGet(sid: 'ep.-1', rid: 1), AiFeature.config),
  (
    2,
    AiConfigSet(sid: 'ep.-1', rid: 2, body: Uint8List.fromList([0x7B, 0x7D])),
    AiFeature.config,
  ),
  (
    3,
    AiBlob(rid: 3, blob: 1, part: 0, parts: 1, data: Uint8List(4)),
    AiFeature.blob,
  ),
  (4, const AiFiles(sid: 'ep.-1', rid: 4, query: 'a'), AiFeature.files),
  (
    5,
    const AiItemPart(sid: 'ep.-1', rid: 5, index: 0, part: 0),
    AiFeature.item,
  ),
  (6, const AiHistory(sid: 'ep.-1', rid: 6), AiFeature.history),
  (7, const AiFolder(sid: 'ep.-1', rid: 7, folder: 'ws:a'), AiFeature.folder),
  (8, const AiChanges(sid: 'ep.-1', rid: 8), AiFeature.changes),
  (9, const AiDiff(sid: 'ep.-1', rid: 9, path: 'a.ts'), AiFeature.changes),
  (10, const AiRevert(sid: 'ep.-1', rid: 10), AiFeature.revert),
];

/// What [map] decodes to: an `ai.*` kind this version does not know is an
/// [AiRaw] only when it comes from the wire.
AiMessage _read(Map<String, Object?> map) =>
    decodeBatch(encodeCbor([map])).single as AiMessage;

/// V2-2b B1, B2, B4 (R4): every V2-2b request has its handler, its feature
/// named in [AiPhoneHub.offered]; a newer phone's request (an [AiRaw] with a
/// `rid`) gets its one answer, `refused`. None of them escapes the request
/// budget.
void main() {
  test('the feature of every V2-2b request kind is named in every listing '
      '(B1)', () {
    for (final (_, message, feature) in _requests()) {
      expect(
        AiPhoneHub.offered,
        contains(feature),
        reason: '${message.runtimeType}',
      );
    }
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
