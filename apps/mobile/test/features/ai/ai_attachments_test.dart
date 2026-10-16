import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart' show aiImageMime;
import 'package:shellx_core/shellx_core.dart' show kAiMaxBlobPartBytes, kAiMaxPromptFiles;
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';

import '../../support/fake_image_source.dart';

TextEditingValue _at(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

// What a photo from the picker carries (V2-2b F38): built here, byte by byte, so that a test can say what must stay.

/// A JPEG segment: 0xFF, [marker], the length of [payload] plus these two bytes, then [payload].
List<int> _segment(int marker, List<int> payload) => [
  0xFF,
  marker,
  (payload.length + 2) >> 8,
  (payload.length + 2) & 0xFF,
  ...payload,
];

/// The TIFF of an Exif segment in [order]: IFD0 holds the make, the Orientation [orientation] (when given) and a
/// pointer to a GPS IFD that holds a latitude. Its offsets are right, so a reader that walks it finds all of it.
List<int> _tiff(Endian order, {int? orientation}) {
  final big = order == Endian.big;
  List<int> u16(int v) => big ? [v >> 8, v & 0xFF] : [v & 0xFF, v >> 8];
  List<int> u32(int v) => big
      ? [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
      : [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24];
  List<int> entry(int tag, int type, int count, List<int> value) => [
    ...u16(tag),
    ...u16(type),
    ...u32(count),
    ...value,
    ...List.filled(4 - value.length, 0),
  ];
  final entries = orientation == null ? 2 : 3;
  final makeAt = 8 + 2 + 12 * entries + 4;
  final gpsAt = makeAt + 6;
  final latitudeAt = gpsAt + 2 + 12 * 2 + 4;
  return [
    ...(big ? 'MM' : 'II').codeUnits, ...u16(42), ...u32(8), // the header: IFD0 at 8
    ...u16(entries),
    ...entry(0x010F, 2, 6, u32(makeAt)), // Make
    if (orientation != null) ...entry(0x0112, 3, 1, u16(orientation)), // Orientation, a SHORT
    ...entry(0x8825, 4, 1, u32(gpsAt)), // the pointer to the GPS IFD
    ...u32(0),
    ...'Apple\u0000'.codeUnits,
    ...u16(2), ...entry(1, 2, 2, [0x4E, 0]), ...entry(2, 5, 3, u32(latitudeAt)), ...u32(0), // GPS: "N", Latitude
    for (final degrees in [37, 46, 29]) ...[...u32(degrees), ...u32(1)],
  ];
}

List<int> _exif(Endian order, {int? orientation}) =>
    _segment(0xE1, ['Exif\u0000\u0000'.codeUnits, _tiff(order, orientation: orientation)].expand((l) => l).toList());

/// What is put back for an Orientation of [o]: an Exif that holds nothing else, 36 bytes (written out here, not built).
List<int> _minimalExif(int o) => [
  0xFF, 0xE1, 0x00, 0x22, // APP1, 34 bytes with its length
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
  0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian TIFF, IFD0 at 8
  0x00, 0x01, // one entry
  0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, o, 0x00, 0x00, // Orientation, SHORT, 1 value
  0x00, 0x00, 0x00, 0x00, // no next IFD
];

const _soi = [0xFF, 0xD8];
final _jfif = _segment(0xE0, [...'JFIF'.codeUnits, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
final _dqt = _segment(0xDB, [0, ...List.generate(64, (i) => i + 1)]);
final _xmp = _segment(0xE1, [
  ...'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits,
  ...'<x:xmpmeta><exif:GPSLatitude>37,46.29N</exif:GPSLatitude></x:xmpmeta>'.codeUnits,
]);
final _iptc = _segment(0xED, [
  ...'Photoshop 3.0\u0000'.codeUnits,
  ...'8BIM'.codeUnits,
  ...[4, 4, 0, 0, 0, 0, 0, 10], // an IPTC resource: its id, its (empty) name, its size
  ...'By Someone'.codeUnits,
]);
final _comment = _segment(0xFE, 'taken at home'.codeUnits);
const _sos = [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00]; // the scan header
const _scan = [0x12, 0x34, 0xFF, 0x00, 0x56, 0xFF, 0xD9]; // the scan (one stuffed 0xFF), EOI

/// What must not be left in a photo that went through [aiTakePicked]: found in the metadata built above.
const _secrets = ['Apple', 'xmpmeta', 'GPSLatitude', 'Photoshop', 'By Someone', 'taken at home'];

/// The markers of the segments of [jpeg] up to the scan header (0xDA) included: a walk of a JPEG by its lengths.
List<int> _markers(List<int> jpeg) {
  final found = <int>[];
  var i = 2;
  while (i + 3 < jpeg.length) {
    while (jpeg[i + 1] == 0xFF) {
      i++; // fill bytes
    }
    final marker = jpeg[i + 1];
    found.add(marker);
    if (marker == 0xDA) break;
    i += 2 + ((jpeg[i + 2] << 8) | jpeg[i + 3]);
  }
  return found;
}

/// A PNG chunk: its length, its four characters, [data], and four bytes where the CRC is (the cleaning never reads it).
List<int> _pngChunk(String type, List<int> data) => [
  data.length >> 24,
  (data.length >> 16) & 0xFF,
  (data.length >> 8) & 0xFF,
  data.length & 0xFF,
  ...type.codeUnits,
  ...data,
  0xC0,
  0xFF,
  0xEE,
  0x01,
];

List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24];

/// A RIFF chunk: its four characters, its size, [payload], and one byte of padding after an odd payload.
List<int> _riffChunk(String fourcc, List<int> payload) => [
  ...fourcc.codeUnits,
  ..._le32(payload.length),
  ...payload,
  if (payload.length.isOdd) 0,
];

/// The VP8X chunk of a 10 × 10 canvas with the feature flags [flags].
List<int> _vp8x(int flags) => _riffChunk('VP8X', [flags, 0, 0, 0, 9, 0, 0, 9, 0, 0]);

/// A WebP made of [chunks], with the RIFF size they make.
Uint8List _webp(List<List<int>> chunks) {
  final body = [for (final chunk in chunks) ...chunk];
  return Uint8List.fromList([...'RIFF'.codeUnits, ..._le32(4 + body.length), ...'WEBP'.codeUnits, ...body]);
}

/// V2-2b B12, B13: what the AI composer takes as images, and its `@` mentions.
void main() {
  group('picked images (B12)', () {
    // Images the composer can walk (V2-2b F38 removes their metadata, and takes no others): see jpegOfSize.
    final jpeg = jpegOfSize(24);
    final heic = Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

    test('PNG, JPEG, GIF and WebP join, by their first bytes, in order', () {
      final gif = Uint8List.fromList('GIF89a'.codeUnits);
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits, 16, 0, 0, 0, ...'WEBP'.codeUnits, //
        ...'VP8 '.codeUnits, 4, 0, 0, 0, 1, 2, 3, 4,
      ]);
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
      final big = jpegOfSize(10 * 1024 * 1024 + 1);
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
    test('one message carries at most 20 MiB of images: the photo that would pass it stays out, and says so', () {
      expect(kAiMessageImageBytes, 20 * 1024 * 1024);
      final taken = aiTakePicked([jpegOfSize(8 << 20), jpegOfSize(8 << 20), jpegOfSize(8 << 20)], room: 5);
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
      final taken = aiTakePicked([jpegOfSize(9 << 20), jpegOfSize(9 << 20), jpegOfSize(9 << 20), kTinyPng], room: 5);
      expect(taken.images.map((i) => i.mime), ['image/jpeg', 'image/jpeg', 'image/png']);
      expect(taken.problem, AiImageProblem.total);
    });

    test('a photo too big on its own says size, not total; a type the computer does not take says type', () {
      final big = jpegOfSize(10 * 1024 * 1024 + 1);
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

  group('photos leave without their metadata (F38)', () {
    // The picker keeps the photo's metadata (iOS) or copies it (Android), the place it was taken included, whatever
    // `requestFullMetadata` says: what goes to the computer, and on to the agent, is cleaned here.
    final dirty = Uint8List.fromList([
      ..._soi,
      ..._jfif,
      ..._exif(Endian.big, orientation: 6),
      ..._xmp,
      ..._iptc,
      ..._comment,
      ..._dqt,
      ..._sos,
      ..._scan, //
    ]);

    test('the Exif with its location, the XMP, the IPTC and the comment are gone; the picture and its turn stay', () {
      for (final secret in _secrets) {
        expect(latin1.decode(dirty), contains(secret), reason: 'the fixture carries $secret');
      }
      final taken = aiTakePicked([dirty], room: 5);
      expect(taken.problem, isNull);
      final image = taken.images.single;
      expect(image.mime, 'image/jpeg');
      expect(image.bytes, [..._soi, ..._jfif, ..._minimalExif(6), ..._dqt, ..._sos, ..._scan]);
      for (final secret in _secrets) {
        expect(latin1.decode(image.bytes), isNot(contains(secret)), reason: secret);
      }
    });

    test(
      'the size checks count the bytes after the cleaning: 10 MiB of metadata around a small picture is no size',
      () {
        final builder = BytesBuilder()..add([..._soi, ..._jfif]);
        final filler = Uint8List.fromList(_segment(0xE1, List.filled(65533, 0x41))); // 64 KiB of an APP1
        for (var i = 0; i < 170; i++) {
          builder.add(filler);
        }
        builder.add([..._dqt, ..._sos, ..._scan]);
        final fat = builder.takeBytes();
        expect(fat.length, greaterThan(10 * 1024 * 1024));
        final taken = aiTakePicked([fat], room: 5);
        expect(taken.problem, isNull);
        expect(taken.images.single.bytes, [..._soi, ..._jfif, ..._dqt, ..._sos, ..._scan]);
      },
    );

    test('the budget of a message counts the bytes after the cleaning too', () {
      final fat = Uint8List.fromList([
        ..._soi,
        ..._jfif,
        ..._segment(0xE1, List.filled(60000, 0x41)),
        ..._dqt,
        ..._sos,
        ..._scan,
      ]);
      final clean = fat.length - 60004;
      final taken = aiTakePicked([fat, fat, fat], room: 5, bytesLeft: clean * 2);
      expect(taken.images, hasLength(2), reason: 'two cleaned photos fit, though two uncleaned ones would not');
      expect(taken.problem, AiImageProblem.total);
    });

    test('a photo whose structure cannot be walked stays out as a type the computer does not take (fail closed)', () {
      final truncated = Uint8List.fromList([..._soi, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78, 0x69, 0x66]);
      final taken = aiTakePicked([truncated, kTinyPng], room: 5);
      expect(taken.images.map((i) => i.mime), ['image/png']);
      expect(taken.problem, AiImageProblem.type);
    });

    test('a PNG, a GIF and a photo with nothing to remove go as they are', () {
      final gif = Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0, 0x21, 0xFE, 2, 0x68, 0x69, 0, 0x3B]);
      final clean = jpegOfSize(40);
      final taken = aiTakePicked([kTinyPng, gif, clean], room: 5);
      expect(taken.problem, isNull);
      expect(taken.images.map((i) => i.bytes), [kTinyPng, gif, clean]);
    });
  });

  group('aiWithoutMetadata (F38)', () {
    Uint8List jpeg(List<List<int>> segments) =>
        Uint8List.fromList([..._soi, for (final s in segments) ...s, ..._sos, ..._scan]);

    void expectClean(Uint8List? clean, String mime, List<int> expected, {String? reason}) {
      expect(clean, expected, reason: reason);
      expect(aiImageMime(clean!), mime, reason: 'it is still a $mime');
    }

    test('JPEG: the Exif with its GPS, the XMP, the IPTC and the comment go; a turned photo keeps its Orientation, in '
        'an Exif of its own after the JFIF; everything else stays, byte for byte', () {
      for (final (order, orientation) in [(Endian.big, 6), (Endian.little, 8)]) {
        final dirty = jpeg([_jfif, _xmp, _exif(order, orientation: orientation), _iptc, _comment, _dqt]);
        final clean = aiWithoutMetadata(dirty, 'image/jpeg');
        expectClean(clean, 'image/jpeg', [..._soi, ..._jfif, ..._minimalExif(orientation), ..._dqt, ..._sos, ..._scan]);
        expect(_markers(clean!), [0xE0, 0xE1, 0xDB, 0xDA], reason: '$order: one APP1, the Orientation');
        expect(_minimalExif(orientation), hasLength(36));
      }
    });

    test('JPEG: the Exif ahead of the JFIF (as Android writes it) is dropped, the Orientation goes after the JFIF', () {
      final dirty = jpeg([_exif(Endian.little, orientation: 3), _jfif, _dqt]);
      expectClean(aiWithoutMetadata(dirty, 'image/jpeg'), 'image/jpeg', [
        ..._soi,
        ..._jfif,
        ..._minimalExif(3),
        ..._dqt,
        ..._sos,
        ..._scan,
      ]);
      // And with no JFIF at all it goes right after SOI.
      expectClean(aiWithoutMetadata(jpeg([_exif(Endian.big, orientation: 5), _dqt]), 'image/jpeg'), 'image/jpeg', [
        ..._soi,
        ..._minimalExif(5),
        ..._dqt,
        ..._sos,
        ..._scan,
      ]);
    });

    test(
      'JPEG: an Orientation of 1, none, an unreadable Exif, or a value that is none of 1-8: no Exif is put back',
      () {
        final expected = [..._soi, ..._jfif, ..._dqt, ..._sos, ..._scan];
        final exifOf = {
          'orientation 1': _exif(Endian.big, orientation: 1),
          'orientation 0': _exif(Endian.big, orientation: 0),
          'orientation 9': _exif(Endian.little, orientation: 9),
          'no orientation': _exif(Endian.big),
          'junk': _segment(0xE1, [...'Exif\u0000\u0000'.codeUnits, 1, 2, 3]),
          'a TIFF whose IFD is out of the segment': _segment(0xE1, [
            ...'Exif\u0000\u0000'.codeUnits,
            ...'MM'.codeUnits,
            0, 42, 0x7F, 0xFF, 0xFF, 0xFF, //
          ]),
        };
        for (final MapEntry(:key, :value) in exifOf.entries) {
          expectClean(aiWithoutMetadata(jpeg([_jfif, value, _dqt]), 'image/jpeg'), 'image/jpeg', expected, reason: key);
        }
        // A comment and an XMP alone: nothing put back either.
        expectClean(aiWithoutMetadata(jpeg([_jfif, _xmp, _comment, _dqt]), 'image/jpeg'), 'image/jpeg', expected);
      },
    );

    test(
      'JPEG: only the first Exif tells the Orientation; the other segments keep their order, fill bytes with them',
      () {
        final icc = _segment(0xE2, [...'ICC_PROFILE\u0000'.codeUnits, 1, 1, 9, 9, 9]);
        final adobe = _segment(0xEE, [...'Adobe'.codeUnits, 0, 100, 0, 0, 0, 0, 1]);
        final sof = _segment(0xC0, [8, 0, 1, 0, 1, 1, 1, 0x11, 0]);
        final dht = _segment(0xC4, [0x00, ...List.filled(16, 0), 1, 2]);
        final dri = _segment(0xDD, [0, 8]);
        final dirty = jpeg([
          [0xFF, ..._jfif], // a fill byte
          icc,
          [0xFF, 0xFF, ..._exif(Endian.big, orientation: 3)],
          _exif(Endian.big, orientation: 6),
          adobe,
          [0xFF, ..._dqt],
          sof,
          dht,
          dri,
        ]);
        expectClean(aiWithoutMetadata(dirty, 'image/jpeg'), 'image/jpeg', [
          ..._soi,
          0xFF, ..._jfif, //
          ..._minimalExif(3),
          ...icc,
          ...adobe,
          0xFF, ..._dqt, //
          ...sof,
          ...dht,
          ...dri,
          ..._sos,
          ..._scan,
        ]);
      },
    );

    test('JPEG: what follows the end of the picture goes — the images a camera appends after it (MPF depth or gain '
        'maps), each with an Exif and an XMP of its own', () {
      final appended = [..._soi, ..._exif(Endian.big, orientation: 6), ..._xmp, ..._dqt, ..._sos, ..._scan];
      final picture = [..._soi, ..._jfif, ..._dqt, ..._sos, ..._scan];
      final clean = aiWithoutMetadata(Uint8List.fromList([...picture, ...appended]), 'image/jpeg');
      expectClean(clean, 'image/jpeg', picture);
      expect(String.fromCharCodes(clean!), isNot(contains('Exif')));
      expect(String.fromCharCodes(clean), isNot(contains('xmpmeta')));
      // With metadata before the scan too: both go.
      expectClean(
        aiWithoutMetadata(
          Uint8List.fromList([..._soi, ..._jfif, ..._xmp, ..._dqt, ..._sos, ..._scan, ...appended]),
          'image/jpeg',
        ),
        'image/jpeg',
        picture,
      );
    });

    test('JPEG: the end of the picture is found past restart markers, stuffed bytes, fill bytes and further scans '
        '(progressive); a picture without one stays as it is', () {
      final dht = _segment(0xC4, [0x00, ...List.filled(16, 0), 1, 2]);
      final progressive = [
        ..._soi, ..._jfif, ..._dqt, //
        ..._sos, 0x12, 0xFF, 0x00, 0xFF, 0xD0, 0x34, 0xFF, 0xD7, 0x56, // a scan: a stuffed 0xFF, restarts
        0xFF, ...dht, // a fill byte, then a table for the next scan
        ..._sos, 0x78, 0xFF, 0x00, 0x9A, 0xFF, 0xFF, 0xD9, // the next scan, a fill byte, the end
      ];
      expectClean(
        aiWithoutMetadata(
          Uint8List.fromList([...progressive, ..._soi, ..._exif(Endian.little), 0x01, 0x02]),
          'image/jpeg',
        ),
        'image/jpeg',
        progressive,
      );
      final cut = Uint8List.fromList([..._soi, ..._jfif, ..._dqt, ..._sos, 0x12, 0x34, 0xFF, 0x00]);
      expect(aiWithoutMetadata(cut, 'image/jpeg'), cut);
      // A segment between scans that runs past the end: what cannot be walked is none.
      expect(
        aiWithoutMetadata(
          Uint8List.fromList([..._soi, ..._jfif, ..._sos, 0x12, 0xFF, 0xC4, 0x7F, 0xFF, 0x00]),
          'image/jpeg',
        ),
        isNull,
      );
    });

    test('JPEG: nothing to remove: the same bytes', () {
      final plain = jpeg([_jfif, _dqt]);
      expect(aiWithoutMetadata(plain, 'image/jpeg'), plain);
      expect(aiWithoutMetadata(jpegOfSize(30), 'image/jpeg'), jpegOfSize(30));
    });

    test('JPEG: what cannot be walked is none: a length past the end or under 2, no scan, a stray byte, a marker that '
        'has no place there', () {
      final cases = <String, List<int>>{
        'a segment longer than the file': [..._soi, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78],
        'a length of 1': [..._soi, 0xFF, 0xE1, 0x00, 0x01],
        'the length cut': [..._soi, 0xFF, 0xE1, 0x00],
        'a marker cut': [..._soi, ..._jfif, 0xFF],
        'no scan': [..._soi, ..._jfif, ..._dqt],
        'a stray byte between segments': [..._soi, ..._jfif, 0x12, 0x34, ..._dqt, ..._sos, ..._scan],
        'the end of the picture before any scan': [..._soi, ..._jfif, 0xFF, 0xD9],
        'a restart marker before any scan': [..._soi, 0xFF, 0xD3, ..._dqt, ..._sos, ..._scan],
        'a 0x00 marker': [..._soi, 0xFF, 0x00, 0x00, 0x02, ..._sos, ..._scan],
        'no start of image': [0x01, 0x02, 0x03, 0x04, ..._dqt, ..._sos],
        'nothing': <int>[],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(aiWithoutMetadata(Uint8List.fromList(value), 'image/jpeg'), isNull, reason: key);
      }
    });

    test('PNG: eXIf, tEXt, iTXt, zTXt and tIME go; the signature and every other chunk stay, byte for byte', () {
      final signature = kTinyPng.sublist(0, 8);
      final header = kTinyPng.sublist(8, 33); // IHDR
      final picture = kTinyPng.sublist(33); // IDAT, IEND
      final phys = _pngChunk('pHYs', [0, 0, 0x0E, 0xC4, 0, 0, 0x0E, 0xC4, 1]);
      final icc = _pngChunk('iCCP', [...'sRGB\u0000'.codeUnits, 0, 1, 2, 3]);
      final dirty = Uint8List.fromList([
        ...signature, ...header, //
        ..._pngChunk('tIME', [7, 234, 10, 15, 9, 30, 0]),
        ...phys,
        ..._pngChunk('eXIf', [...'MM'.codeUnits, 0, 42, ...'Apple GPSLatitude'.codeUnits]),
        ..._pngChunk('tEXt', 'Comment\u0000taken at home'.codeUnits),
        ...icc,
        ..._pngChunk('iTXt', [...'XML:com.adobe.xmp'.codeUnits, 0, 0, 0, 0, 0, ...'By Someone'.codeUnits]),
        ..._pngChunk('zTXt', [...'Author'.codeUnits, 0, 0, 1, 2, 3]),
        ...picture,
      ]);
      expectClean(aiWithoutMetadata(dirty, 'image/png'), 'image/png', [
        ...signature,
        ...header,
        ...phys,
        ...icc,
        ...picture,
      ]);
      // Bytes after IEND are no part of the picture.
      expectClean(aiWithoutMetadata(Uint8List.fromList([...kTinyPng, 1, 2, 3]), 'image/png'), 'image/png', kTinyPng);
    });

    test('PNG: the tiny PNG comes out as it went in; what cannot be walked is none', () {
      expect(aiWithoutMetadata(kTinyPng, 'image/png'), kTinyPng);
      final cases = <String, List<int>>{
        'a signature that is not whole': [...kTinyPng.sublist(0, 4), 0x0D, 0x0A, 0x1A, 0x0B, ...kTinyPng.sublist(8)],
        'a chunk longer than the file': [...kTinyPng.sublist(0, 33), 0x00, 0x00, 0xFF, 0xFF, ...'IDAT'.codeUnits, 1, 2],
        'no IEND': kTinyPng.sublist(0, kTinyPng.length - 12),
        'a chunk cut in its header': [...kTinyPng.sublist(0, 33), 0x00, 0x00, 0x00],
        'a length over what a chunk may be': [
          ...kTinyPng.sublist(0, 33),
          0x80,
          0x00,
          0x00,
          0x00,
          ...'IDAT'.codeUnits,
          0,
          0,
          0,
          0,
        ],
        'only the signature': kTinyPng.sublist(0, 8),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(aiWithoutMetadata(Uint8List.fromList(value), 'image/png'), isNull, reason: key);
      }
    });

    test('WebP: the EXIF and XMP chunks go (padding with them), their flags are cleared in VP8X, the RIFF size is '
        'rewritten; the other chunks stay', () {
      final icc = _riffChunk('ICCP', [1, 2, 3, 4]);
      final picture = _riffChunk('VP8L', [0x2F, 1, 2, 3, 4]); // odd: padded
      final exif = _riffChunk('EXIF', [
        ...'Exif\u0000\u0000'.codeUnits,
        ...'MM'.codeUnits,
        ...'Apple'.codeUnits,
      ]); // 13: odd
      final xmp = _riffChunk('XMP ', 'GPSLatitude'.codeUnits); // 11: odd
      const flags = 0x20 | 0x10; // ICC profile, alpha
      final dirty = _webp([_vp8x(flags | 0x08 | 0x04), icc, exif, picture, xmp]);
      final clean = aiWithoutMetadata(dirty, 'image/webp');
      expectClean(clean, 'image/webp', _webp([_vp8x(flags), icc, picture]));
      final size = clean![4] | (clean[5] << 8) | (clean[6] << 16) | (clean[7] << 24);
      expect(size, clean.length - 8, reason: 'the RIFF size is the length of the file less its first 8 bytes');
      // A file without VP8X (a plain lossy one) loses an EXIF it should not have had, all the same.
      expectClean(
        aiWithoutMetadata(
          _webp([
            _riffChunk('VP8 ', [1, 2, 3, 4]),
            exif,
          ]),
          'image/webp',
        ),
        'image/webp',
        _webp([
          _riffChunk('VP8 ', [1, 2, 3, 4]),
        ]),
      );
      // Flags without chunks: cleared.
      expectClean(
        aiWithoutMetadata(_webp([_vp8x(flags | 0x08 | 0x04), picture]), 'image/webp'),
        'image/webp',
        _webp([_vp8x(flags), picture]),
      );
    });

    test('WebP: nothing to remove: the same bytes; what cannot be walked is none', () {
      final plain = _webp([
        _vp8x(0x10),
        _riffChunk('VP8L', [0x2F, 1, 2, 3, 4]),
      ]);
      expect(aiWithoutMetadata(plain, 'image/webp'), plain);
      final cases = <String, List<int>>{
        'a RIFF size past the end': [...plain.sublist(0, 4), ..._le32(plain.length), ...plain.sublist(8)],
        'a chunk longer than the file': _webp([
          _vp8x(0x10),
          [...'VP8L'.codeUnits, ..._le32(99), 1, 2, 3],
        ]),
        'a chunk cut in its header': [...'RIFF'.codeUnits, ..._le32(8), ...'WEBP'.codeUnits, ...'VP8L'.codeUnits],
        'a VP8X with no flags': _webp([_riffChunk('VP8X', <int>[])]),
        'not a WebP': [...'RIFF'.codeUnits, ..._le32(4), ...'WAVE'.codeUnits],
        'less than a header': 'RIFF'.codeUnits,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(aiWithoutMetadata(Uint8List.fromList(value), 'image/webp'), isNull, reason: key);
      }
    });

    test(
      'GIF: as it is (no Exif; the pickers write no comment or XMP block), and a type that is none of these is none',
      () {
        final gif = Uint8List.fromList([
          ...'GIF89a'.codeUnits,
          1,
          0,
          1,
          0,
          0,
          0,
          0,
          0x21,
          0xFE,
          2,
          0x68,
          0x69,
          0,
          0x3B,
        ]);
        expect(aiWithoutMetadata(gif, 'image/gif'), gif);
        expect(aiWithoutMetadata(kTinyPng, 'image/heic'), isNull);
        expect(aiWithoutMetadata(kTinyPng, 'image/avif'), isNull);
        expect(aiWithoutMetadata(kTinyPng, ''), isNull);
      },
    );
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
