import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';
const _sid = 'ep.-1';

void _tool(AiSessionState s, String id, String output) => s.applyUpdate(
  SessionUpdate.fromJson({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': 'Run',
    'kind': 'execute',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': output},
      },
    ],
  }),
  aiT0,
);

/// Every slice of item [index], asked one after the other as the phone
/// does; the results in order.
Future<List<AiResult>> _load(HubRig rig, int index) async {
  final results = <AiResult>[];
  var parts = 1;
  for (var part = 0; part < parts; part++) {
    // A second between requests: the phone's budget (30 a second) refills.
    rig.now = rig.now.add(const Duration(seconds: 1));
    rig.hub.handle(
      _phone,
      AiItemPart(sid: _sid, rid: 100 + part, index: index, part: part),
    );
    await pumpEventQueue();
    final result = rig.last<AiResult>(_phone);
    results.add(result);
    if (!result.ok) break;
    parts = decodeBody(result.body)!['parts']! as int;
  }
  return results;
}

String _joined(List<AiResult> results) =>
    [for (final r in results) decodeBody(r.body)!['text']! as String].join();

/// V2-2b B16, R14: a big item in full, one slice per request.
void main() {
  test('a long output comes in slices that make the whole view; the listing '
      'names the feature', () async {
    final rig = HubRig();
    final s = rig.source.add(-1);
    final output = [for (var i = 0; i < 20000; i++) 'dòng $i'].join('\n');
    _tool(s, 'c1', output);
    final results = await _load(rig, 0);
    expect(results.length, greaterThan(1));
    expect(results.every((r) => r.ok), isTrue);
    final bodies = [for (final r in results) decodeBody(r.body)!];
    expect(bodies.map((b) => b['part']), [
      for (var i = 0; i < results.length; i++) i,
    ]);
    expect(bodies.map((b) => b['r']).toSet(), {s.timeline.items.single.rev});
    final view = AiFullView.fromJson(
      jsonDecode(_joined(results)) as Map<String, Object?>,
    )!;
    expect(view.output, output);
    rig.hub.handle(_phone, const AiList());
    final listing = AiListing.fromJson(
      decodeBody(rig.last<AiListResult>(_phone).body)!,
      available: true,
    );
    expect(listing.features, contains(AiFeature.item));
  });

  test('Review Focus 3: the worst escaping still makes bodies within one '
      'message', () async {
    final rig = HubRig();
    _tool(
      rig.source.add(-1),
      'c1',
      [for (var i = 0; i < 150; i++) '"\\\u0001' * 600].join('\n'),
    );
    final results = await _load(rig, 0);
    expect(results.every((r) => r.ok), isTrue);
    for (final r in results) {
      expect(r.body!.length, lessThanOrEqualTo(kAiMaxBodyBytes));
      expect(encodeBatch([r]).length, lessThan(kMaxSealedBatchBytes));
    }
  });

  test(
    'a command still running: a new rev is made again, and says so',
    () async {
      final rig = HubRig();
      final s = rig.source.add(-1);
      _tool(s, 'c1', [for (var i = 0; i < 6000; i++) 'x' * 20].join('\n'));
      rig.hub.handle(
        _phone,
        const AiItemPart(sid: _sid, rid: 1, index: 0, part: 0),
      );
      await pumpEventQueue();
      final first = decodeBody(rig.last<AiResult>(_phone).body)!;
      s.applyUpdate(
        SessionUpdate.fromJson({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'c1',
          'content': [
            {
              'type': 'content',
              'content': {
                'type': 'text',
                'text': [for (var i = 0; i < 6000; i++) 'y' * 20].join('\n'),
              },
            },
          ],
        }),
        aiT0,
      );
      rig.hub.handle(
        _phone,
        const AiItemPart(sid: _sid, rid: 2, index: 0, part: 1),
      );
      await pumpEventQueue();
      final second = decodeBody(rig.last<AiResult>(_phone).body)!;
      expect(second['r'], isNot(first['r']));
    },
  );

  test('over 2 MiB is read on the computer; an index, a part or an item with '
      'nothing more is refused; another run\'s session is not_found', () async {
    final rig = HubRig();
    final s = rig.source.add(-1);
    // Lines of 1 000 (a line is cut at 2 000): over 2 MiB in all.
    _tool(s, 'c1', [for (var i = 0; i < 2200; i++) 'z' * 1000].join('\n'));
    s
      ..beginTurn(const [TextBlock('go')], aiT0)
      ..endTurn(outcome: TurnOutcome.finished, at: aiT0);
    rig.hub
      ..handle(_phone, const AiItemPart(sid: _sid, rid: 1, index: 0, part: 0))
      ..handle(_phone, const AiItemPart(sid: _sid, rid: 2, index: 9, part: 0))
      ..handle(_phone, const AiItemPart(sid: _sid, rid: 3, index: 1, part: 5))
      ..handle(_phone, const AiItemPart(sid: _sid, rid: 4, index: 2, part: 0))
      ..handle(
        _phone,
        const AiItemPart(sid: 'x.-1', rid: 5, index: 0, part: 0),
      );
    await pumpEventQueue();
    final codes = {
      for (final r in rig.to(_phone).whereType<AiResult>()) r.rid: r.code,
    };
    expect(codes, {
      1: 'too_big',
      2: 'refused',
      3: 'refused',
      4: 'refused',
      5: 'not_found',
    });
  });
}
