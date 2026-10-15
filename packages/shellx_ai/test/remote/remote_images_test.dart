import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

InitializeResult _image(bool takes) => InitializeResult.fromJson({
  'protocolVersion': 1,
  'agentCapabilities': {
    'promptCapabilities': {'image': takes},
  },
});

/// V2-2b B12: what the desktop and the phone hub both know of images.
void main() {
  test('the type of an image by its first bytes: PNG, JPEG, GIF, WebP', () {
    expect(aiImageMime(_png), 'image/png');
    expect(
      aiImageMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(aiImageMime(Uint8List.fromList(utf8.encode('GIF89a'))), 'image/gif');
    expect(
      aiImageMime(
        Uint8List.fromList([
          ...utf8.encode('RIFF'),
          0,
          0,
          0,
          0,
          ...utf8.encode('WEBP'),
        ]),
      ),
      'image/webp',
    );
    expect(aiImageMime(Uint8List.fromList(utf8.encode('hello'))), isNull);
    expect(aiImageMime(Uint8List(0)), isNull);
    // An iPhone photo that was not re-encoded (HEIC) is no image ShellX sends.
    expect(
      aiImageMime(
        Uint8List.fromList([0, 0, 0, 24, ...utf8.encode('ftypheic')]),
      ),
      isNull,
    );
  });

  test('an agent takes no images only once it said so', () {
    final s = _state();
    expect(aiTakesNoImages(s), isFalse, reason: 'it has said nothing yet');
    s.setAgent(_image(false));
    expect(aiTakesNoImages(s), isTrue);
    s.setAgent(_image(true));
    expect(aiTakesNoImages(s), isFalse);
    expect((kAiImagesMax, kAiImageMaxBytes), (5, 10 << 20));
  });

  test(
    'a user message with images says how many (img); the phone reads it',
    () {
      final s = _state()
        ..beginTurn([
          const TextBlock('xem hai ảnh'),
          const ImageBlock(data: 'AAAA', mimeType: 'image/png'),
          const ImageBlock(data: 'BBBB', mimeType: 'image/jpeg'),
        ], DateTime.utc(2026, 10, 15));
      final record = encodeItem(s.timeline.items.single, 0);
      expect(record['img'], 2);
      final mirror = AiMirror()
        ..apply({
          'g': 1,
          'from': 0,
          'n': 1,
          'reset': true,
          'items': [record],
        }, snapshot: true);
      final text = mirror.at(0)! as MirrorText;
      expect((text.text, text.images), ('xem hai ảnh', 2));
    },
  );

  test('a message without images, and agent text, carry no img', () {
    final s = _state()
      ..beginTurn([const TextBlock('chỉ chữ')], DateTime.utc(2026));
    expect(encodeItem(s.timeline.items.single, 0).containsKey('img'), isFalse);
    s.applyUpdate(
      SessionUpdate.fromJson({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'ok'},
      }),
      DateTime.utc(2026),
    );
    expect(encodeItem(s.timeline.items.last, 1).containsKey('img'), isFalse);
  });
}
