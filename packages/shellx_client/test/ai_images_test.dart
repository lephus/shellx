import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';
import 'support/scripted_desktop.dart';

const _sid = 'ep.-1';

Matcher _aiError(String code) =>
    isA<AiRequestException>().having((e) => e.code, 'code', code);

/// Bytes [n] long, all [value].
Uint8List _bytes(int n, [int value = 7]) =>
    Uint8List(n)..fillRange(0, n, value);

/// V2-2b B12 on the phone's client: images go in parts.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('an image goes in parts of 48 KiB at most, four at a time; each part '
      'the computer took is counted', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob}); // holds
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      final bytes = _bytes(6 * kAiMaxBlobPartBytes - 10);
      final blob = ai.newBlobId();
      final progress = <(int, int)>[];
      var done = false;
      ai
          .uploadImage(
            blob,
            'image/jpeg',
            bytes,
            onProgress: (sent, parts) {
              progress.add((sent, parts));
            },
          )
          .then((_) => done = true);
      settle(async);
      expect(desktop.got<AiBlob>(), hasLength(4), reason: 'four in flight');
      for (var k = 0; k < 6; k++) {
        final part = desktop.got<AiBlob>()[k];
        desktop.say(AiResult(rid: part.rid, ok: true));
        settle(async);
      }
      expect(done, isTrue);
      final parts = desktop.got<AiBlob>();
      expect([for (final p in parts) p.part], [0, 1, 2, 3, 4, 5]);
      expect({for (final p in parts) (p.blob, p.parts)}, {(blob, 6)});
      expect(
        [for (final p in parts) p.mime],
        ['image/jpeg', null, null, null, null, null],
      );
      expect(
        [for (final p in parts) p.data.length],
        [...List.filled(5, kAiMaxBlobPartBytes), kAiMaxBlobPartBytes - 10],
      );
      expect(Uint8List.fromList([for (final p in parts) ...p.data]), bytes);
      expect(progress.last, (6, 6));
    });
  });

  test('a part the computer was too busy for goes again; another refusal ends '
      'the upload', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob});
      var busy = true;
      desktop.answer = (m) {
        if (m is! AiBlob) return null;
        if (m.part == 1 && busy) {
          busy = false;
          return AiResult(rid: m.rid, ok: false, code: 'busy');
        }
        return AiResult(rid: m.rid, ok: true);
      };
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      h.run(
        ai.uploadImage(
          ai.newBlobId(),
          'image/png',
          _bytes(2 * kAiMaxBlobPartBytes),
        ),
      );
      expect([for (final p in desktop.got<AiBlob>()) p.part], [0, 1, 1]);
      desktop.answer = (m) => m is AiBlob
          ? AiResult(rid: m.rid, ok: false, code: 'too_large')
          : null;
      expect(
        () => h.run(ai.uploadImage(ai.newBlobId(), 'image/png', _bytes(10))),
        throwsA(_aiError('too_large')),
      );
    });
  });

  test('a refusal in the middle of an upload ends it: the parts still in '
      'flight begin no new one', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob}); // holds
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      Object? error;
      ai
          .uploadImage(
            ai.newBlobId(),
            'image/png',
            _bytes(6 * kAiMaxBlobPartBytes),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      settle(async);
      final inFlight = desktop.got<AiBlob>();
      expect(inFlight, hasLength(4));
      desktop.say(AiResult(rid: inFlight[1].rid, ok: false, code: 'too_large'));
      settle(async);
      for (final k in [0, 2, 3]) {
        desktop.say(AiResult(rid: inFlight[k].rid, ok: true));
        settle(async);
      }
      expect(error, _aiError('too_large'));
      expect(desktop.got<AiBlob>(), hasLength(4), reason: 'no part 4 or 5');
    });
  });

  test('the largest parts travel the real channel and leave it up (Review '
      'Focus 3)', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob});
      desktop.answer = (m) =>
          m is AiBlob ? AiResult(rid: m.rid, ok: true) : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      h.run(
        ai.uploadImage(
          ai.newBlobId(),
          'image/png',
          _bytes(2 * kAiMaxBlobPartBytes),
        ),
      );
      expect(
        [for (final p in desktop.got<AiBlob>()) p.data.length],
        [kAiMaxBlobPartBytes, kAiMaxBlobPartBytes],
      );
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test('a channel lost in the middle of an upload fails it, and no part is '
      'sent again: the image is uploaded again, never the prompt by itself '
      '(D13)', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob}); // holds
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      Object? error;
      ai
          .uploadImage(
            ai.newBlobId(),
            'image/png',
            _bytes(6 * kAiMaxBlobPartBytes),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      settle(async);
      expect(desktop.got<AiBlob>(), hasLength(4), reason: 'four in flight');
      h.disconnectPhone();
      expect(error, isA<MachineConnectionException>());
      h.reconnectPhone();
      settle(async, const Duration(seconds: 2));
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(desktop.got<AiBlob>(), hasLength(4), reason: 'none sent again');
    });
  });

  test('a prompt names its images; none, or too many, or too big, sends '
      'nothing', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob});
      desktop.answer = (m) =>
          m is AiPrompt ? AiResult(rid: m.rid, ok: true) : null;
      final h = Harness(async, keys, ai: desktop);
      final ai = readyAi(h);
      h.run(ai.prompt(_sid, 'xem', blobs: [1, 2]));
      expect(desktop.got<AiPrompt>().single.blobs, [1, 2]);
      expect(
        () => h.run(ai.prompt(_sid, 'x', blobs: [1, 2, 3, 4, 5, 6])),
        throwsA(_aiError('too_large')),
      );
      expect(
        () => h.run(ai.uploadImage(ai.newBlobId(), 'image/png', Uint8List(0))),
        throwsA(_aiError('too_large')),
      );
      expect(
        () => h.run(
          ai.uploadImage(
            ai.newBlobId(),
            'image/png',
            Uint8List(kAiImageMaxBytes + 1),
          ),
        ),
        throwsA(_aiError('too_large')),
      );
      expect(desktop.got<AiPrompt>(), hasLength(1));
      expect(desktop.got<AiBlob>(), isEmpty);
    });
  });

  test('a computer that cannot (ai 1): no image is sent, unsupported at once; '
      'a prompt without images still goes (B1, Review Focus 2)', () {
    fakeAsync((async) {
      final desktop = ScriptedDesktop(features: {AiFeature.blob});
      desktop.answer = (m) =>
          m is AiPrompt ? AiResult(rid: m.rid, ok: true) : null;
      final h = Harness(async, keys, ai: desktop, aiProtocol: 1);
      final ai = readyAi(h);
      expect(
        () => h.run(ai.uploadImage(ai.newBlobId(), 'image/png', _bytes(10))),
        throwsA(_aiError('unsupported')),
      );
      expect(
        () => h.run(ai.prompt(_sid, 'x', blobs: [1])),
        throwsA(_aiError('unsupported')),
      );
      h.run(ai.prompt(_sid, 'chỉ chữ'));
      expect(desktop.got<AiBlob>(), isEmpty);
      expect([for (final p in desktop.got<AiPrompt>()) p.blobs], [<int>[]]);
    });
  });

  test("blob numbers are the phone's own: never the same twice", () {
    fakeAsync((async) {
      final h = Harness(async, keys, ai: ScriptedDesktop());
      final ai = h.phoneMachine.ai;
      final ids = [for (var i = 0; i < 5; i++) ai.newBlobId()];
      expect(ids.toSet(), hasLength(5));
    });
  });
}
