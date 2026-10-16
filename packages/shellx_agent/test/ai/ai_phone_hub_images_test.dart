import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, //
]);
final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16]);

InitializeResult _takesImages(bool takes) => InitializeResult.fromJson({
  'protocolVersion': 1,
  'agentCapabilities': {
    'promptCapabilities': {'image': takes},
  },
});

/// Image [blob] in one part.
AiBlob _image(int rid, int blob, Uint8List bytes) => AiBlob(
  rid: rid,
  blob: blob,
  part: 0,
  parts: 1,
  mime: 'image/png',
  data: bytes,
);

Future<AiResult> _ask(HubRig rig, AiMessage m) async {
  rig.hub.handle(_phone, m);
  await pumpEventQueue();
  return rig.last<AiResult>(_phone);
}

/// V2-2b B12: images from the phone on the hub.
void main() {
  test('the listing offers images', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, const AiList());
    final r = rig.last<AiListResult>(_phone);
    expect(
      AiListing.fromJson(decodeBody(r.body)!, available: r.available).features,
      contains(AiFeature.blob),
    );
  });

  test('each part gets its answer; a prompt takes the image, of the type its '
      'bytes say', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!;
    rig.hub
      ..handle(
        _phone,
        AiBlob(
          rid: 1,
          blob: 7,
          part: 0,
          parts: 2,
          mime: 'image/heic', // what the phone said: the bytes say JPEG
          data: Uint8List.sublistView(_jpeg, 0, 3),
        ),
      )
      ..handle(
        _phone,
        AiBlob(
          rid: 2,
          blob: 7,
          part: 1,
          parts: 2,
          data: Uint8List.sublistView(_jpeg, 3),
        ),
      );
    expect(
      [for (final r in rig.to(_phone).whereType<AiResult>()) (r.rid, r.ok)],
      [(1, true), (2, true)],
    );
    final r = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 3, text: 'xem ảnh', blobs: [7]),
    );
    expect(r.ok, isTrue);
    final sent = control.prompts.single;
    expect(sent.text, 'xem ảnh');
    expect(sent.images.single.mime, 'image/jpeg');
    expect(sent.images.single.bytes, _jpeg);
    final again = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 4, text: 'lần nữa', blobs: [7]),
    );
    expect(again.code, 'refused', reason: 'taken: it is gone');
    expect(control.prompts, hasLength(1));
  });

  test('an image alone is a prompt; nothing at all is not', () async {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, _image(1, 1, _png));
    final alone = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 2, text: ' ', blobs: [1]),
    );
    expect(alone.ok, isTrue);
    final empty = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 3, text: ' '),
    );
    expect(empty.code, 'refused');
  });

  test('refused and nothing taken: an image not whole, unknown, twice, or no '
      'image ShellX sends; more than five: too_large; an agent that takes '
      'none: no_images', () async {
    final rig = HubRig()..source.add(-1);
    final control = rig.source.controls[-1]!;
    rig.hub
      ..handle(
        _phone,
        AiBlob(
          rid: 1,
          blob: 1,
          part: 0,
          parts: 2,
          mime: 'image/png',
          data: _png,
        ),
      )
      ..handle(_phone, _image(2, 2, Uint8List.fromList(utf8.encode('hello'))))
      ..handle(_phone, _image(3, 3, _png));
    Future<String?> code(int rid, List<int> blobs) async => (await _ask(
      rig,
      AiPrompt(sid: 'ep.-1', rid: rid, text: 'x', blobs: blobs),
    )).code;
    expect(await code(10, [1]), 'refused', reason: 'not whole');
    expect(await code(11, [2]), 'refused', reason: 'no image');
    expect(await code(12, [9]), 'refused', reason: 'unknown');
    expect(await code(13, [3, 3]), 'refused', reason: 'twice');
    expect(await code(14, [3, 4, 5, 6, 7, 8]), 'too_large');
    control.state.setAgent(_takesImages(false));
    expect(await code(15, [3]), 'no_images');
    control.state.setAgent(_takesImages(true));
    expect(await code(16, [3]), isNull, reason: 'image 3 was never taken');
    expect(control.sent, hasLength(1));
  });

  test('a part that does not fit gets its code', () {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(
      _phone,
      AiBlob(rid: 1, blob: 1, part: 2, parts: 2, data: _png),
    );
    expect(rig.last<AiResult>(_phone).code, 'refused');
  });

  test('a part at the limit is taken, and one message holds it (Review '
      'Focus 3)', () {
    final rig = HubRig()..source.add(-1);
    final largest = AiBlob(
      rid: 1 << 40,
      blob: 1 << 40,
      part: 0,
      parts: 2,
      mime: 'image/jpeg',
      data: Uint8List(kAiMaxBlobPartBytes),
    );
    expect(encodeBatch([largest]).length, lessThan(kMaxSealedBatchBytes));
    rig.hub.handle(_phone, largest);
    expect(rig.last<AiResult>(_phone).ok, isTrue);
    expect(
      encodeBatch([rig.last<AiResult>(_phone)]).length,
      lessThan(kMaxSealedBatchBytes),
    );
  });

  test('a phone that leaves takes its images with it', () async {
    final rig = HubRig()..source.add(-1);
    rig.hub.handle(_phone, _image(1, 1, _png));
    rig.hub.phoneGone(_phone);
    final gone = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 2, text: 'x', blobs: [1]),
    );
    expect(gone.code, 'refused');
    rig.hub.handle(_phone, _image(3, 2, _png));
    rig.hub.allPhonesGone();
    final allGone = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 4, text: 'x', blobs: [2]),
    );
    expect(allGone.code, 'refused');
  });

  test('a hub that is disposed lets go of the images and of the timer that '
      'watches them', () {
    fakeAsync((async) {
      final rig = HubRig(clock: async.getClock(aiT0).now)..source.add(-1);
      rig.hub.handle(_phone, _image(1, 1, _png));
      expect(async.pendingTimers, isNotEmpty, reason: 'it watches the image');
      rig.hub.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a part spends the budget like any request: over it, busy with its rid, '
      'and the image is not kept', () async {
    final rig = HubRig()..source.add(-1);
    // The rig's clock stands still: the 60 of the burst are all there is.
    for (var rid = 1; rid <= 60; rid++) {
      rig.hub.handle(_phone, _image(rid, rid, _png));
    }
    rig.hub.handle(_phone, _image(61, 99, _png));
    final busy = rig.last<AiResult>(_phone);
    expect((busy.rid, busy.ok, busy.code), (61, false, 'busy'));
    rig.now = rig.now.add(const Duration(seconds: 2)); // the budget is back
    final unknown = await _ask(
      rig,
      const AiPrompt(sid: 'ep.-1', rid: 62, text: 'x', blobs: [99]),
    );
    expect(
      unknown.code,
      'refused',
      reason: 'a part that got busy kept nothing',
    );
  });

  test('what an image holds never shows: not in its toString', () {
    expect(AiPhoneImage('image/png', _png).toString(), '…');
    expect(
      AiPhonePrompt(
        'xem',
        images: [AiPhoneImage('image/png', _png)],
      ).toString(),
      '…',
    );
  });

  test('an image nobody used for two minutes is dropped', () {
    fakeAsync((async) {
      final clock = async.getClock(aiT0);
      final rig = HubRig(clock: clock.now)..source.add(-1);
      rig.hub.handle(_phone, _image(1, 1, _png));
      async.elapse(const Duration(minutes: 1, seconds: 59));
      rig.hub.handle(
        _phone,
        const AiPrompt(sid: 'ep.-1', rid: 2, text: 'x', blobs: [1]),
      );
      async.flushMicrotasks();
      expect(rig.last<AiResult>(_phone).ok, isTrue, reason: 'still there');
      rig.hub.handle(_phone, _image(3, 2, _png));
      async.elapse(const Duration(minutes: 2));
      rig.hub.handle(
        _phone,
        const AiPrompt(sid: 'ep.-1', rid: 4, text: 'y', blobs: [2]),
      );
      async.flushMicrotasks();
      expect(rig.last<AiResult>(_phone).code, 'refused');
      rig.hub.dispose();
    });
  });
}
