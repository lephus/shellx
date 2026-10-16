import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';
import 'support/scripted_desktop.dart';

const _sid = 'x.1';

/// V2-2b B19: changes, one file's diff and a revert, from the phone.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  const both = {AiFeature.changes, AiFeature.revert};

  test('changes, a diff and a revert travel, and their bodies come back', () {
    fakeAsync((async) {
      final d = ScriptedDesktop(features: both);
      final h = Harness(async, keys, ai: d);
      final ai = readyAi(h);
      d.answer = (m) => switch (m) {
        AiChanges(:final rid) => AiResult(
          rid: rid,
          ok: true,
          body: encodeChangesView(
            const AiChangesView(
              scope: 'turn',
              turn: 1,
              files: [
                AiChangedFile(path: 'a.ts', kind: 'm', plus: 2, minus: 1),
              ],
            ),
          ),
        ),
        AiDiff(:final rid) => AiResult(
          rid: rid,
          ok: true,
          body: encodeBody({'path': 'a.ts', 'old': 'x', 'new': 'y'}),
        ),
        AiRevert(:final rid) => AiResult(
          rid: rid,
          ok: true,
          body: encodeBody({'reverted': 1}),
        ),
        _ => null,
      };
      final view = h.run(ai.changes(_sid, turn: 1));
      expect(view.files.single.path, 'a.ts');
      expect(aiFileDiffOf(h.run(ai.diff(_sid, 'a.ts', turn: 1)))!.newText, 'y');
      expect(h.run(ai.revert(_sid, turn: 1)), 1);
      final sent = d.got<AiRevert>().single;
      expect((sent.sid, sent.turn, sent.keep), (_sid, 1, null));
      expect(d.got<AiChanges>().single.turn, 1);
      expect(d.got<AiDiff>().single.path, 'a.ts');
    });
  });

  test('confirm comes back with its question; keep goes with the next one', () {
    fakeAsync((async) {
      final d = ScriptedDesktop(features: both);
      final h = Harness(async, keys, ai: d);
      final ai = readyAi(h);
      d.answer = (m) => switch (m) {
        AiRevert(:final rid, keep: null) => AiResult(
          rid: rid,
          ok: false,
          code: 'confirm',
          body: encodeRevertConfirm(
            touched: ['b.txt'],
            someClean: true,
            total: 2,
          ),
        ),
        AiRevert(:final rid) => AiResult(
          rid: rid,
          ok: true,
          body: encodeBody({'reverted': 1}),
        ),
        _ => null,
      };
      expect(
        () => h.run(ai.revert(_sid, turn: 1)),
        throwsA(
          isA<AiRequestException>()
              .having((e) => e.code, 'code', 'confirm')
              .having(
                (e) => AiRevertConfirm.fromJson(e.body!).touched,
                'touched',
                ['b.txt'],
              ),
        ),
      );
      expect(h.run(ai.revert(_sid, turn: 1, keep: 'clean')), 1);
      expect([for (final r in d.got<AiRevert>()) r.keep], [null, 'clean']);
    });
  });

  test('a computer that cannot: unsupported at once, nothing sent (R15)', () {
    fakeAsync((async) {
      final d = ScriptedDesktop();
      final h = Harness(async, keys, ai: d);
      final ai = readyAi(h);
      for (final call in <Future<Object?> Function()>[
        () => ai.changes(_sid),
        () => ai.diff(_sid, 'a.ts'),
        () => ai.revert(_sid),
      ]) {
        expect(
          () => h.run(call()),
          throwsA(
            isA<AiRequestException>().having((e) => e.code, 'c', 'unsupported'),
          ),
        );
      }
      expect(d.got<AiChanges>(), isEmpty);
      expect(d.got<AiDiff>(), isEmpty);
      expect(d.got<AiRevert>(), isEmpty);
    });
  });

  test('a revert lost with its channel fails and is never sent again', () {
    fakeAsync((async) {
      final d = ScriptedDesktop(features: both);
      final h = Harness(async, keys, ai: d);
      final ai = readyAi(h);
      Object? failure;
      unawaited(
        ai
            .revert(_sid, turn: 1)
            .then<void>(
              (_) {},
              onError: (Object e) {
                failure = e;
              },
            ),
      );
      settle(async);
      expect(d.got<AiRevert>(), hasLength(1));
      h.disconnectPhone();
      settle(async);
      expect(failure, isA<MachineConnectionException>());
      h.reconnectPhone();
      settle(async, const Duration(seconds: 5));
      expect(d.got<AiRevert>(), hasLength(1));
    });
  });
}
