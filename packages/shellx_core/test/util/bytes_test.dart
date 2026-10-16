import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

void main() {
  group('uuid', () {
    const uuid = '0f8fad5b-d9cb-469f-a165-70867728950e';

    test('round-trips through 16 big-endian bytes', () {
      final bytes = uuidToBytes(uuid);
      expect(bytes, hasLength(16));
      expect(bytes.first, 0x0f);
      expect(bytes.last, 0x0e);
      expect(uuidFromBytes(bytes), uuid);
    });

    test('accepts uppercase input and always formats lowercase', () {
      expect(uuidFromBytes(uuidToBytes(uuid.toUpperCase())), uuid);
    });

    test('nil uuid is 16 zero bytes', () {
      expect(uuidToBytes(nilUuid), Uint8List(16));
      expect(uuidFromBytes(Uint8List(16)), nilUuid);
    });

    test('rejects malformed uuids', () {
      for (final bad in [
        '',
        '0f8fad5bd9cb469fa16570867728950e',
        '0f8fad5b-d9cb-469f-a165-70867728950',
        '0f8fad5b-d9cb-469f-a165-70867728950g',
        ' 0f8fad5b-d9cb-469f-a165-70867728950e',
      ]) {
        expect(() => uuidToBytes(bad), throwsFormatException, reason: bad);
      }
    });

    test('uuidFromBytes rejects wrong length', () {
      expect(() => uuidFromBytes(Uint8List(15)), throwsArgumentError);
    });
  });

  group('base64url', () {
    test('encodes without padding', () {
      expect(base64UrlNoPad(Uint8List.fromList([0xfb, 0xff])), '-_8');
      expect(base64UrlNoPad(Uint8List(32)), hasLength(43));
    });

    test('decodes with or without padding', () {
      expect(fromBase64UrlNoPad('-_8'), [0xfb, 0xff]);
      expect(fromBase64UrlNoPad('-_8='), [0xfb, 0xff]);
      expect(fromBase64UrlNoPad(''), isEmpty);
    });

    test('round-trips 32 random-looking bytes', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
      expect(fromBase64UrlNoPad(base64UrlNoPad(bytes)), bytes);
    });

    test('rejects standard alphabet and bad lengths', () {
      for (final bad in ['+/8', 'ab/c', 'a', 'abcde', 'ab c']) {
        expect(
          () => fromBase64UrlNoPad(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('constantTimeEquals', () {
    test('compares content', () {
      expect(
        constantTimeEquals(
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([1, 2]),
        ),
        isTrue,
      );
      expect(
        constantTimeEquals(
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([1, 3]),
        ),
        isFalse,
      );
      expect(
        constantTimeEquals(Uint8List.fromList([1]), Uint8List.fromList([1, 2])),
        isFalse,
      );
    });
  });

  group('hex helpers', () {
    test('round-trip', () {
      expect(bytesToHex(hexToBytes('00ff10')), '00ff10');
      expect(() => hexToBytes('abc'), throwsFormatException);
    });

    test('concatBytes joins chunks in order', () {
      expect(
        concatBytes([
          [1],
          [],
          [2, 3],
        ]),
        [1, 2, 3],
      );
    });
  });
}
