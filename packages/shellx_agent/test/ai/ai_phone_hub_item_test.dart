import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';
const _phone2 = 'b0000000-0000-4000-8000-000000000003';
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

var _rid = 0;

/// The full view of item [index] that [phone] gets, from the one slice a
/// short item takes.
Future<AiFullView> _view(HubRig rig, int index, {String phone = _phone}) async {
  rig.hub.handle(
    phone,
    AiItemPart(sid: _sid, rid: ++_rid, index: index, part: 0),
  );
  await pumpEventQueue();
  final result = rig.last<AiResult>(phone);
  expect(result.ok, isTrue, reason: 'code ${result.code}');
  final body = decodeBody(result.body)!;
  expect(body['parts'], 1, reason: 'a short item is one slice');
  return AiFullView.fromJson(
    jsonDecode(body['text']! as String) as Map<String, Object?>,
  )!;
}

/// The output of tool card [index] as [phone] gets it in full.
Future<String?> _output(HubRig rig, int index, {String phone = _phone}) async =>
    (await _view(rig, index, phone: phone)).output;

/// Changes what tool card [index] would show without changing its rev (nor
/// the card): a full view kept for a phone is the only place the old text can
/// still come from.
void _silently(AiSessionState s, int index, String output) {
  (s.timeline.items[index] as ToolItem).fields = ToolCallFields.fromJson({
    'title': 'Run',
    'kind': 'execute',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': output},
      },
    ],
  });
}

ElicitationRequest _form(String message) => ElicitationRequest.fromJson({
  'mode': 'form',
  'message': message,
  'requestedSchema': {
    'type': 'object',
    'properties': {
      'pick': {
        'type': 'string',
        'enum': ['a', 'b'],
      },
    },
  },
});

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

  group('what is kept for a phone (V2-2b F21, F22)', () {
    test('F21: a runtime replaced under the same sid is not served from the '
        'old one\'s view, though its item 0 has the same rev', () async {
      final rig = HubRig();
      final old = rig.source.add(-1);
      _tool(old, 'c1', 'old output');
      expect(await _output(rig, 0), 'old output');
      // A new runtime in the same tab: its item 0 is another card, with the
      // rev a first card has too.
      final fresh = rig.source.replace(-1);
      _tool(fresh, 'c1', 'new output');
      expect(
        fresh.timeline.items.single.rev,
        old.timeline.items.single.rev,
        reason: 'only the card itself tells the two apart',
      );
      rig.now = rig.now.add(const Duration(seconds: 30));
      expect(await _output(rig, 0), 'new output');
    });

    test('F21: a question is read as it is asked now, not as the runtime that '
        'was replaced asked it', () async {
      final rig = HubRig();
      final old = rig.source.add(-1);
      old.addAsk(_form('Which file?'));
      expect((await _view(rig, 0)).request!.message, 'Which file?');
      final fresh = rig.source.replace(-1);
      fresh.addAsk(_form('Delete everything?'));
      expect(
        fresh.timeline.items.single.rev,
        old.timeline.items.single.rev,
        reason: 'only the question itself tells the two apart',
      );
      rig.now = rig.now.add(const Duration(seconds: 30));
      expect((await _view(rig, 0)).request!.message, 'Delete everything?');
    });

    test('F22: an item is kept 60 s after the last slice asked, then made '
        'again; it goes with its phone', () async {
      final rig = HubRig();
      final s = rig.source.add(-1);
      _tool(s, 'c1', 'old');
      expect(await _output(rig, 0), 'old');
      _silently(s, 0, 'new');
      rig.now = rig.now.add(const Duration(seconds: 59));
      expect(await _output(rig, 0), 'old', reason: 'inside 60 s: kept');
      // Asked again: the 60 s count from there.
      rig.now = rig.now.add(const Duration(seconds: 59));
      expect(await _output(rig, 0), 'old', reason: '59 s after the last ask');
      rig.now = rig.now.add(const Duration(seconds: 61));
      expect(
        await _output(rig, 0),
        'new',
        reason: 'idle over 60 s: made again',
      );
      // Kept again, until the phone is gone: a new channel makes it again.
      _silently(s, 0, 'newer');
      expect(await _output(rig, 0), 'new', reason: 'kept for the next slices');
      rig.hub.phoneGone(_phone);
      expect(await _output(rig, 0), 'newer', reason: 'gone with its phone');
    });

    test('F22: a phone keeps 4 items at most, the one asked longest ago goes, '
        'and another phone has its own', () async {
      final rig = HubRig();
      final s = rig.source.add(-1);
      for (var i = 0; i < 5; i++) {
        _tool(s, 'c$i', 'old $i');
      }
      // Five asked in turn: the cap of 4 drops the first, item 0.
      for (var i = 0; i < 5; i++) {
        rig.now = rig.now.add(const Duration(seconds: 1));
        expect(await _output(rig, i), 'old $i');
      }
      // Every item changes in silence: only what is kept has the old text.
      for (var i = 0; i < 5; i++) {
        _silently(s, i, 'new $i');
      }
      rig.now = rig.now.add(const Duration(seconds: 1));
      // Kept: 1, 2, 3, 4. Asking 2 again makes it the latest: 1, 3, 4, 2.
      expect(await _output(rig, 2), 'old 2');
      // Item 0 is made again, a fifth: the one asked longest ago, 1, goes
      // (3, 4, 2, 0). Asking 1 makes it again and drops 3 (4, 2, 0, 1).
      expect(await _output(rig, 0), 'new 0');
      expect(await _output(rig, 1), 'new 1');
      // 2 and 4 are still kept; 3 is gone.
      expect(await _output(rig, 2), 'old 2');
      expect(await _output(rig, 4), 'old 4');
      expect(await _output(rig, 3), 'new 3');
      // Another phone never asked: it has its own, made now.
      expect(await _output(rig, 4, phone: _phone2), 'new 4');
    });
  });
}
