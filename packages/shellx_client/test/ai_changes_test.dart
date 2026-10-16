import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

const _sid = 'x.1';

/// A scripted desktop: its window offers [features]; [answer] says what it
/// answers to a V2-2b request (nothing when it returns null).
final class _Desktop implements AiEndpoint {
  _Desktop(this.features);

  final Set<String> features;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final received = <AiMessage>[];
  AiResult? Function(AiMessage message)? answer;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    received.add(message);
    if (message is AiList) {
      _out.add(
        OutboundMessage(
          mobileId,
          AiListResult(
            available: true,
            body: encodeBody(AiListing(features: features).toJson()),
          ),
        ),
      );
      return;
    }
    final result = answer?.call(message);
    if (result != null) _out.add(OutboundMessage(mobileId, result));
  }

  @override
  void phoneGone(String mobileId) {}

  @override
  void allPhonesGone() {}

  List<T> got<T extends AiMessage>() => received.whereType<T>().toList();
}

/// The phone's AI client, connected, its listing watched (so it knows what
/// the computer can do).
MachineAi _connect(Harness h) {
  h.run(h.phoneMachine.connect());
  h.run(h.phoneMachine.listSessions(includeDesktop: true));
  h.run(h.phoneMachine.ai.watch());
  settle(h.async);
  return h.phoneMachine.ai;
}

/// V2-2b B19: changes, one file's diff and a revert, from the phone.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  const both = {AiFeature.changes, AiFeature.revert};

  test('changes, a diff and a revert travel, and their bodies come back', () {
    fakeAsync((async) {
      final d = _Desktop(both);
      final h = Harness(async, keys, ai: d);
      final ai = _connect(h);
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
      final d = _Desktop(both);
      final h = Harness(async, keys, ai: d);
      final ai = _connect(h);
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
      final d = _Desktop(const {});
      final h = Harness(async, keys, ai: d);
      final ai = _connect(h);
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
      final d = _Desktop(both);
      final h = Harness(async, keys, ai: d);
      final ai = _connect(h);
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
