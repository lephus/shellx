import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

/// The one answer [rig] sent to request [rid].
AiResult _result(HubRig rig, int rid) =>
    rig.to(_phone).whereType<AiResult>().singleWhere((r) => r.rid == rid);

/// V2-2b B19: what a phone sees of a session's changes, one file's diff,
/// and a revert — all worked out by the window when asked.
void main() {
  test('every listing names changes and revert (B1)', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, const AiList());
    final r = rig.last<AiListResult>(_phone);
    final listing = AiListing.fromJson(decodeBody(r.body)!, available: true);
    expect(
      listing.features,
      containsAll([AiFeature.changes, AiFeature.revert]),
    );
  });

  test('ai.changes: the window\'s view, for the turn asked', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!
      ..changesView = const AiChangesView(
        scope: 'turn',
        turn: 3,
        files: [AiChangedFile(path: 'src/a.ts', kind: 'm', plus: 4, minus: 1)],
        after: ['src/a.ts'],
        first: 1,
        last: 3,
        done: 3,
      );
    rig.hub.handle(_phone, const AiChanges(sid: 'ep.-1', rid: 1, turn: 3));
    rig.hub.handle(_phone, const AiChanges(sid: 'ep.-1', rid: 2));
    await pumpEventQueue();
    final r = _result(rig, 1);
    expect(r.ok, isTrue);
    final view = AiChangesView.fromJson(decodeBody(r.body)!);
    expect(view.files.single.path, 'src/a.ts');
    expect(view.after, ['src/a.ts']);
    expect(control.changesAsked, [3, null]);
  });

  test(
    'ten thousand changed files still fit one message (Review Focus 3)',
    () async {
      final rig = HubRig()..source.add(-1);
      rig.source.controls[-1]!.changesView = AiChangesView(
        scope: 'session',
        files: [
          for (var i = 0; i < 10000; i++)
            AiChangedFile(path: 'src/${'x' * 500}/$i.ts', kind: 'a', plus: 1),
        ],
      );
      rig.hub.handle(_phone, const AiChanges(sid: 'ep.-1', rid: 1));
      await pumpEventQueue();
      final r = _result(rig, 1);
      expect(r.ok, isTrue);
      expect(r.body!.length, lessThanOrEqualTo(kAiMaxBodyBytes));
      expect(encodeBatch([r]).length, lessThan(kMaxSealedBatchBytes));
      final view = AiChangesView.fromJson(decodeBody(r.body)!);
      expect(view.files.length + view.more, 10000);
    },
  );

  test('ai.diff: a path no window could have offered is refused, and the '
      'window is not asked (R18)', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!..diffBody = const {'new': 'x'};
    final bad = [
      '',
      '../secrets',
      'a/../../b',
      './a',
      'a//b',
      '/etc/passwd',
      'C:/Windows/x',
      r'a\b',
      'a\x00b',
      'a' * (kAiMaxPathBytes + 1),
    ];
    for (final (i, path) in bad.indexed) {
      rig.hub.handle(_phone, AiDiff(sid: 'ep.-1', rid: i, path: path));
    }
    await pumpEventQueue();
    for (var i = 0; i < bad.length; i++) {
      expect(_result(rig, i).code, 'refused', reason: bad[i]);
    }
    expect(control.diffs, isEmpty);
  });

  test(
    'ai.diff: the window\'s body as it gave it; its refusal as its code',
    () async {
      final rig = HubRig()..source.add(-1);
      final control = rig.source.controls[-1]!
        ..diffBody = const {'path': 'logo.png', 'binary': true};
      rig.hub.handle(
        _phone,
        const AiDiff(sid: 'ep.-1', rid: 1, turn: 2, path: 'img/logo.png'),
      );
      await pumpEventQueue();
      expect(decodeBody(_result(rig, 1).body), {
        'path': 'logo.png',
        'binary': true,
      });
      expect(control.diffs, [(2, 'img/logo.png')]);
      control.diffBody = null;
      rig.hub.handle(_phone, const AiDiff(sid: 'ep.-1', rid: 2, path: 'a.ts'));
      await pumpEventQueue();
      expect(_result(rig, 2).code, 'refused');
    },
  );

  test('ai.revert: the count; busy_turn and undo_off; confirm with its '
      'question; keep reaches the window (Review Focus 4)', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!..reverted = 2;
    rig.hub.handle(_phone, const AiRevert(sid: 'ep.-1', rid: 1, turn: 3));
    await pumpEventQueue();
    expect(decodeBody(_result(rig, 1).body), {'reverted': 2});

    control.revertRefusal = const AiRefused('busy_turn');
    rig.hub.handle(_phone, const AiRevert(sid: 'ep.-1', rid: 2, turn: 3));
    control.revertRefusal = const AiRefused('undo_off');
    rig.hub.handle(_phone, const AiRevert(sid: 'ep.-1', rid: 3));
    await pumpEventQueue();
    expect(_result(rig, 2).code, 'busy_turn');
    expect(_result(rig, 3).code, 'undo_off');

    control.revertRefusal = AiRefused(
      'confirm',
      body: encodeRevertConfirm(
        touched: ['src/b.ts'],
        someClean: true,
        total: 2,
      ),
    );
    rig.hub.handle(_phone, const AiRevert(sid: 'ep.-1', rid: 4, turn: 3));
    await pumpEventQueue();
    final ask = _result(rig, 4);
    expect((ask.ok, ask.code), (false, 'confirm'));
    final question = AiRevertConfirm.fromJson(decodeBody(ask.body)!);
    expect(question.touched, ['src/b.ts']);
    expect(question.someClean, isTrue);

    control.revertRefusal = null;
    rig.hub.handle(
      _phone,
      const AiRevert(sid: 'ep.-1', rid: 5, turn: 3, keep: 'clean'),
    );
    rig.hub.handle(
      _phone,
      const AiRevert(sid: 'ep.-1', rid: 6, turn: 3, keep: 'maybe'),
    );
    await pumpEventQueue();
    expect(_result(rig, 5).ok, isTrue);
    expect(_result(rig, 6).code, 'refused');
    expect(control.reverts, [
      (3, null),
      (3, null),
      (null, null),
      (3, null),
      (3, 'clean'),
    ]);
  });

  test(
    'a session that is not there is not_found, and nothing is asked',
    () async {
      final rig = HubRig()..source.add(-1);
      final control = rig.source.controls[-1]!;
      rig.hub
        ..handle(_phone, const AiChanges(sid: 'ep.-9', rid: 1))
        ..handle(_phone, const AiDiff(sid: 'old.-1', rid: 2, path: 'a.ts'))
        ..handle(_phone, const AiRevert(sid: 'ep.-9', rid: 3));
      await pumpEventQueue();
      expect(
        [for (var i = 1; i <= 3; i++) _result(rig, i).code],
        ['not_found', 'not_found', 'not_found'],
      );
      expect(control.changesAsked, isEmpty);
      expect(control.diffs, isEmpty);
      expect(control.reverts, isEmpty);
    },
  );
}
