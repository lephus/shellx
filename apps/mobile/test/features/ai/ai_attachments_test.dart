import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart' show kAiMaxBlobPartBytes, kAiMaxPromptFiles;
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';

import '../../support/fake_image_source.dart';

TextEditingValue _at(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

/// V2-2b B12, B13: what the AI composer takes as images, and its `@` mentions.
void main() {
  group('picked images (B12)', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    final heic = Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

    test('PNG, JPEG, GIF and WebP join, by their first bytes, in order', () {
      final gif = Uint8List.fromList('GIF89a'.codeUnits);
      final webp = Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]);
      final taken = aiTakePicked([kTinyPng, jpeg, gif, webp], room: 5);
      expect(taken.images.map((i) => i.mime), ['image/png', 'image/jpeg', 'image/gif', 'image/webp']);
      expect(taken.problem, isNull);
    });

    test('a type the computer does not take (HEIC left as it was) stays out, and says so', () {
      final taken = aiTakePicked([heic, kTinyPng], room: 5);
      expect(taken.images.single.mime, 'image/png');
      expect(taken.problem, AiImageProblem.type);
    });

    test('over 10 MiB stays out, and says so', () {
      final big = Uint8List(10 * 1024 * 1024 + 1)..setAll(0, [0xFF, 0xD8, 0xFF]);
      final taken = aiTakePicked([big], room: 5);
      expect(taken.images, isEmpty);
      expect(taken.problem, AiImageProblem.size);
    });

    test('no more than the room left', () {
      expect(aiTakePicked([kTinyPng, kTinyPng, kTinyPng], room: 2).images, hasLength(2));
      expect(aiTakePicked([kTinyPng], room: 0).images, isEmpty);
    });

    // F34: the computer keeps 20 MiB of a phone's images at once (V2-2b B12) and past that evicts the message's
    // earliest images, so the prompt would fail on every retry: the phone keeps one message within it.
    Uint8List jpegOf(int length) => Uint8List(length)..setAll(0, [0xFF, 0xD8, 0xFF]);

    test('one message carries at most 20 MiB of images: the photo that would pass it stays out, and says so', () {
      expect(kAiMessageImageBytes, 20 * 1024 * 1024);
      final taken = aiTakePicked([jpegOf(8 << 20), jpegOf(8 << 20), jpegOf(8 << 20)], room: 5);
      expect(taken.images, hasLength(2));
      expect(taken.problem, AiImageProblem.total);
    });

    test('bytesLeft is what the images already in the message left; exactly that much still fits', () {
      final size = kTinyPng.length;
      final fits = aiTakePicked([kTinyPng, kTinyPng], room: 5, bytesLeft: size);
      expect(fits.images, hasLength(1), reason: 'the first fills it up, the second would pass it');
      expect(fits.problem, AiImageProblem.total);
      expect(aiTakePicked([kTinyPng], room: 5, bytesLeft: size).problem, isNull);
      expect(aiTakePicked([kTinyPng], room: 5, bytesLeft: size - 1).images, isEmpty);
      expect(aiTakePicked([kTinyPng], room: 5, bytesLeft: size - 1).problem, AiImageProblem.total);
      expect(aiTakePicked([kTinyPng], room: 5, bytesLeft: 0).images, isEmpty);
      expect(aiTakePicked([kTinyPng], room: 5, bytesLeft: -1).images, isEmpty);
    });

    test('a photo that would pass the budget stays out, a smaller one after it still joins', () {
      final taken = aiTakePicked([jpegOf(9 << 20), jpegOf(9 << 20), jpegOf(9 << 20), kTinyPng], room: 5);
      expect(taken.images.map((i) => i.mime), ['image/jpeg', 'image/jpeg', 'image/png']);
      expect(taken.problem, AiImageProblem.total);
    });

    test('a photo too big on its own says size, not total; a type the computer does not take says type', () {
      final big = jpegOf(10 * 1024 * 1024 + 1);
      expect(aiTakePicked([big], room: 5, bytesLeft: 1).problem, AiImageProblem.size);
      expect(aiTakePicked([Uint8List(8)], room: 5, bytesLeft: 0).problem, AiImageProblem.type);
    });

    test('the parts an image takes on the wire; never logged', () {
      expect(AiPickedImage(kTinyPng, 'image/png').parts, 1);
      expect(AiPickedImage(Uint8List(kAiMaxBlobPartBytes), 'image/png').parts, 1);
      expect(AiPickedImage(Uint8List(kAiMaxBlobPartBytes + 1), 'image/png').parts, 2);
      expect(AiPickedImage(kTinyPng, 'image/png').toString(), 'AiPickedImage(…)');
    });
  });

  group('@ mentions (B13)', () {
    test('the token being typed: after the start or a space, up to the cursor', () {
      expect(AiMentions.tokenAt(_at('@sr')), (start: 0, query: 'sr'));
      expect(AiMentions.tokenAt(_at('sửa @src/ma')), (start: 4, query: 'src/ma'));
      expect(AiMentions.tokenAt(_at('sửa @src rồi', 8)), (start: 4, query: 'src'));
    });

    test('no token: a bare @, an address, a space after it, a selection', () {
      expect(AiMentions.tokenAt(_at('@')), isNull);
      expect(AiMentions.tokenAt(_at('me@host')), isNull);
      expect(AiMentions.tokenAt(_at('@src ')), isNull);
      expect(AiMentions.tokenAt(_at('không có')), isNull);
      expect(
        AiMentions.tokenAt(
          const TextEditingValue(text: '@src', selection: TextSelection(baseOffset: 1, extentOffset: 3)),
        ),
        isNull,
      );
      expect(AiMentions.tokenAt(_at('@${'a' * (AiMentions.maxQueryBytes + 1)}')), isNull);
    });

    test('a pick replaces the token with @path and a space, the cursor after it', () {
      final value = _at('sửa @sr giúp', 7);
      final token = AiMentions.tokenAt(value)!;
      final next = AiMentions.insert(value, token, 'src/main.ts');
      expect(next.text, 'sửa @src/main.ts  giúp');
      expect(next.selection, const TextSelection.collapsed(offset: 'sửa @src/main.ts '.length));
    });

    test('only the mentions still in the text go, at most 20', () {
      expect(AiMentions.stillMentioned('xem @src/a.ts và @b.ts', ['src/a.ts', 'c.ts', 'b.ts']), ['src/a.ts', 'b.ts']);
      final many = [for (var i = 0; i < 30; i++) 'f$i.ts'];
      expect(AiMentions.stillMentioned(many.map((p) => '@$p').join(' '), many), hasLength(kAiMaxPromptFiles));
    });
  });
}
