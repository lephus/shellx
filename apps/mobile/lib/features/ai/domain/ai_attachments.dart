import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shellx_ai/remote.dart' show aiImageMime, kAiImageMaxBytes, kAiImagesMax;
import 'package:shellx_core/shellx_core.dart' show kAiMaxBlobPartBytes, kAiMaxPromptFiles;

/// V2-2b B12: where the photos of a message come from.
enum AiImageOrigin { library, camera }

/// What the computer holds of a phone's images at once (V2-2b B12): past it the computer drops the message's
/// earliest images and the prompt that names them is refused, on every retry. So one message carries no more.
const int kAiMessageImageBytes = 20 << 20;

/// V2-2b B12: an image picked for the next message, as it will be sent: its bytes (made by the picker, at most
/// 2048 px a side, JPEG 85, and cleaned of their metadata by [aiWithoutMetadata]: the picker leaves it in) and
/// their type by their first bytes. Identity is the object: the same bytes picked twice are two images. Never
/// logged.
final class AiPickedImage {
  AiPickedImage(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;

  /// The `ai.blob` parts it takes (`MachineAi.uploadImage` sends it in pieces of [kAiMaxBlobPartBytes]).
  int get parts => bytes.isEmpty ? 1 : (bytes.length + kAiMaxBlobPartBytes - 1) ~/ kAiMaxBlobPartBytes;

  @override
  String toString() => 'AiPickedImage(…)';
}

/// Why a picked image did not join the message.
enum AiImageProblem {
  /// Not PNG, JPEG, GIF or WebP (a HEIC the picker did not convert, say), or one whose metadata cannot be taken
  /// out because its structure cannot be walked ([aiWithoutMetadata], F38).
  type,

  /// Over [kAiImageMaxBytes].
  size,

  /// Would bring the images of the message past what is left of [kAiMessageImageBytes] (F34).
  total,
}

/// V2-2b B12: what of [picked] can go with the next message, [room] places left (of [kAiImagesMax]) and
/// [bytesLeft] bytes left of [kAiMessageImageBytes] (what the images already in the message left): the images
/// of a type a computer takes, by their first bytes, cleaned of their metadata ([aiWithoutMetadata], F38: the
/// picker keeps it, the place the photo was taken included), of at most [kAiImageMaxBytes] after that, in order,
/// together within [bytesLeft] (F34: a photo that would pass it stays out, a smaller one after it may still
/// join). [problem] says why one was left out (the last reason met); null when none was. An image whose
/// metadata cannot be taken out stays out, as a [AiImageProblem.type] (it is never sent as it is). Images beyond
/// [room] are left out silently (the picker was asked for no more).
({List<AiPickedImage> images, AiImageProblem? problem}) aiTakePicked(
  List<Uint8List> picked, {
  required int room,
  int bytesLeft = kAiMessageImageBytes,
}) {
  final images = <AiPickedImage>[];
  AiImageProblem? problem;
  var taken = 0;
  for (final original in picked) {
    if (images.length >= room) break;
    final mime = aiImageMime(original);
    final bytes = mime == null ? null : aiWithoutMetadata(original, mime);
    if (mime == null || bytes == null) {
      problem = AiImageProblem.type;
      continue;
    }
    if (bytes.length > kAiImageMaxBytes) {
      problem = AiImageProblem.size;
      continue;
    }
    if (taken + bytes.length > bytesLeft) {
      problem = AiImageProblem.total;
      continue;
    }
    taken += bytes.length;
    images.add(AiPickedImage(bytes, mime));
  }
  return (images: images, problem: problem);
}

/// V2-2b B12 (F38): [bytes], an image of type [mime], without the metadata the picker left in it — where it was
/// taken (GPS), when, with what device, a thumbnail, the author's text. `image_picker` keeps it (iOS) or copies it
/// (Android) into the photo it hands over, whatever `requestFullMetadata` says (that flag only keeps iOS from asking
/// for the photo library); it would go on to the computer and the agent. Only what draws the picture stays.
///
/// - JPEG: every APP1 (Exif, XMP), APP13 (IPTC) and COM segment before the scan is dropped; every other segment
///   and the scan on are copied as they are. Both pickers keep the sensor's pixels of a camera photo and its Exif
///   Orientation, so when the first Exif held one of 2-8 an Exif that holds only it is put back, after the JFIF
///   segment (right after the start of the image when there is none): the photo would otherwise turn sideways.
///   Everything after the end of the picture (its first EOI) goes: some cameras append further images there (MPF
///   depth or gain maps), each with an Exif and an XMP of its own. Between the scans of a progressive picture
///   metadata is not looked for: the pickers write none there. A picture cut before its EOI is kept to its end.
/// - PNG: the `eXIf`, `tEXt`, `iTXt`, `zTXt` and `tIME` chunks are dropped, the rest copied as it is. Bytes after
///   `IEND` are no part of the picture and go.
/// - WebP: the `EXIF` and `XMP ` chunks are dropped, their flags cleared in `VP8X`, the RIFF size written again.
///   Bytes after the RIFF go.
/// - GIF: as it is. It has no Exif, and the pickers write no comment or XMP block into one.
///
/// The very same bytes come back when there is nothing to remove. Null when the structure cannot be walked (cut
/// short, a length that runs past the end, no scan) or [mime] is none of these: an image whose metadata cannot be
/// taken out is not sent (it fails closed). Nothing of [bytes] is ever logged.
Uint8List? aiWithoutMetadata(Uint8List bytes, String mime) => switch (mime) {
  'image/jpeg' => _jpegWithoutMetadata(bytes),
  'image/png' => _pngWithoutMetadata(bytes),
  'image/webp' => _webpWithoutMetadata(bytes),
  'image/gif' => bytes,
  _ => null,
};

Uint8List _view(Uint8List b, int start, int end) => Uint8List.sublistView(b, start, end);

Uint8List? _jpegWithoutMetadata(Uint8List b) {
  final n = b.length;
  if (n < 2 || b[0] != 0xFF || b[1] != 0xD8) return null;
  // The segments before the scan that stay: their bytes (the fill bytes ahead of them with them) and whether
  // each one is APP0 (JFIF, JFXX).
  final kept = <({int start, int end, bool app0})>[];
  var dropped = false;
  var exifSeen = false;
  int? orientation;
  var i = 2;
  while (true) {
    var j = i; // the marker code, after at least one 0xFF (more are fill bytes)
    while (j < n && b[j] == 0xFF) {
      j++;
    }
    if (j == i || j >= n) return null; // a stray byte where a marker belongs, or the end before any scan
    final code = b[j];
    if (code == 0xDA) {
      // The scan header: it and all that follows stay as they are, up to the end of the picture.
      final stop = _jpegEnd(b, i);
      if (stop == null) return null;
      if (!dropped) return stop == n ? b : Uint8List.fromList(_view(b, 0, stop));
      final out = BytesBuilder(copy: false)..add(_view(b, 0, 2));
      var k = 0;
      while (k < kept.length && kept[k].app0) {
        out.add(_view(b, kept[k].start, kept[k].end));
        k++;
      }
      if (orientation != null && orientation > 1) out.add(_orientationExif(orientation));
      for (; k < kept.length; k++) {
        out.add(_view(b, kept[k].start, kept[k].end));
      }
      out.add(_view(b, i, stop));
      return out.takeBytes();
    }
    // SOI, EOI, RSTn, TEM and the reserved markers have no length and have no place before the scan.
    if (code < 0xC0 || (code >= 0xD0 && code <= 0xD9)) return null;
    if (j + 2 >= n) return null; // the length is cut
    final length = (b[j + 1] << 8) | b[j + 2];
    final end = j + 1 + length;
    if (length < 2 || end > n) return null;
    if (code == 0xE1 || code == 0xED || code == 0xFE) {
      dropped = true;
      if (code == 0xE1 && !exifSeen && _isExif(b, j + 3, end)) {
        exifSeen = true; // the first Exif is the one a reader goes by
        orientation = _exifOrientation(b, j + 3, end);
      }
    } else {
      kept.add((start: i, end: end, app0: code == 0xE0));
    }
    i = end;
  }
}

/// Where the picture of [b] ends: just after its first EOI, walked from the first scan header at [from] — segments by
/// their lengths, the entropy-coded data of each scan byte by byte (a 0xFF in it is followed by 0x00, a restart marker
/// or more 0xFF before a marker). The end of [b] when there is no EOI (a picture cut short); null when a segment does
/// not walk (a length past the end or under 2, a marker that has no place there).
int? _jpegEnd(Uint8List b, int from) {
  final n = b.length;
  var i = from;
  while (i < n) {
    var j = i; // the marker code, after at least one 0xFF (more are fill bytes)
    while (j < n && b[j] == 0xFF) {
      j++;
    }
    if (j == i) return null; // a stray byte where a marker belongs
    if (j >= n) return n;
    final code = b[j];
    if (code == 0xD9) return j + 1;
    if (code < 0xC0 || code == 0xD8) return null; // SOI, TEM, a reserved marker: no place after a scan
    if (code >= 0xD0 && code <= 0xD7) {
      i = j + 1; // a restart marker outside a scan's data: no length
      continue;
    }
    if (j + 2 >= n) return null;
    final length = (b[j + 1] << 8) | b[j + 2];
    final end = j + 1 + length;
    if (length < 2 || end > n) return null;
    i = end;
    if (code != 0xDA) continue;
    // The scan's data, up to the next marker.
    while (i < n) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      var k = i + 1;
      while (k < n && b[k] == 0xFF) {
        k++;
      }
      if (k >= n) return n;
      final next = b[k];
      if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
        i = k + 1; // a stuffed 0xFF or a restart: still the scan's data
        continue;
      }
      break; // a marker: i is at its first 0xFF
    }
  }
  return n;
}

bool _isExif(Uint8List b, int start, int end) =>
    end - start >= 6 &&
    b[start] == 0x45 && // E
    b[start + 1] == 0x78 && // x
    b[start + 2] == 0x69 && // i
    b[start + 3] == 0x66 && // f
    b[start + 4] == 0 &&
    b[start + 5] == 0;

/// The Orientation (1-8) in the Exif segment of [b] whose payload is [start] to [end]; null when it holds none, or
/// none that reads (the segment is dropped all the same).
int? _exifOrientation(Uint8List b, int start, int end) {
  final tiff = start + 6; // after "Exif\0\0"
  if (end - tiff < 8) return null;
  final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D; // "MM"
  if (!big && !(b[tiff] == 0x49 && b[tiff + 1] == 0x49)) return null; // "II"
  int u16(int at) => big ? (b[at] << 8) | b[at + 1] : b[at] | (b[at + 1] << 8);
  int u32(int at) => big
      ? (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]
      : b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);
  if (u16(tiff + 2) != 42) return null;
  final ifd = tiff + u32(tiff + 4); // IFD0, from the start of the TIFF
  if (ifd < tiff + 8 || ifd + 2 > end) return null;
  final count = u16(ifd);
  for (var k = 0; k < count; k++) {
    final entry = ifd + 2 + 12 * k;
    if (entry + 12 > end) return null;
    if (u16(entry) == 0x0112) {
      if (u16(entry + 2) != 3 || u32(entry + 4) != 1) return null; // a SHORT, one value (left in the 4 bytes)
      final value = u16(entry + 8);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}

/// An Exif segment that holds the Orientation [orientation] and nothing else: 36 bytes, big-endian.
Uint8List _orientationExif(int orientation) => Uint8List.fromList([
  0xFF, 0xE1, 0x00, 0x22, // APP1, 34 bytes with its length
  0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
  0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // "MM", 42, IFD0 at 8
  0x00, 0x01, // one entry
  0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00, // Orientation, SHORT, one value
  0x00, 0x00, 0x00, 0x00, // no next IFD
]);

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// The PNG chunks that carry metadata: Exif, text (plain, compressed, international) and the time of the last change.
const _pngMetadata = {'eXIf', 'tEXt', 'iTXt', 'zTXt', 'tIME'};

Uint8List? _pngWithoutMetadata(Uint8List b) {
  final n = b.length;
  if (n < _pngSignature.length) return null;
  for (var k = 0; k < _pngSignature.length; k++) {
    if (b[k] != _pngSignature[k]) return null;
  }
  final out = BytesBuilder(copy: false)..add(_view(b, 0, _pngSignature.length));
  var dropped = false;
  var i = _pngSignature.length;
  while (true) {
    if (i + 12 > n) return null; // a chunk is its length, its type and its CRC at least
    final length = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    final end = i + 12 + length;
    if (length > 0x7FFFFFFF || end > n) return null;
    final type = String.fromCharCodes(b, i + 4, i + 8);
    if (type == 'IEND') {
      out.add(_view(b, i, end));
      return !dropped && end == n ? b : out.takeBytes(); // what follows IEND is no part of the picture
    }
    if (_pngMetadata.contains(type)) {
      dropped = true;
    } else {
      out.add(_view(b, i, end));
    }
    i = end;
  }
}

int _u32le(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

Uint8List? _webpWithoutMetadata(Uint8List b) {
  final n = b.length;
  if (n < 12 || String.fromCharCodes(b, 0, 4) != 'RIFF' || String.fromCharCodes(b, 8, 12) != 'WEBP') return null;
  final end = 8 + _u32le(b, 4); // the RIFF size is the rest of the file; what follows it is no part of the picture
  if (end < 12 || end > n) return null;
  var dropped = end < n;
  final chunks = <Uint8List>[];
  var i = 12;
  while (i < end) {
    if (i + 8 > end) return null;
    final size = _u32le(b, i + 4);
    final next = i + 8 + size + (size & 1); // an odd chunk is followed by a byte of padding
    if (next > end) return null;
    final fourcc = String.fromCharCodes(b, i, i + 4);
    if (fourcc == 'EXIF' || fourcc == 'XMP ') {
      dropped = true;
    } else if (fourcc == 'VP8X') {
      if (size < 10) return null;
      final flags = b[i + 8];
      final cleared = flags & 0xF3; // no EXIF (0x08), no XMP (0x04)
      if (cleared == flags) {
        chunks.add(_view(b, i, next));
      } else {
        dropped = true;
        chunks.add(Uint8List.fromList(_view(b, i, next))..[8] = cleared);
      }
    } else {
      chunks.add(_view(b, i, next));
    }
    i = next;
  }
  if (!dropped) return b;
  final size = 4 + chunks.fold<int>(0, (total, chunk) => total + chunk.length); // "WEBP" and the chunks
  final out = BytesBuilder(copy: false)
    ..add(
      Uint8List.fromList([
        ...'RIFF'.codeUnits,
        size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, (size >> 24) & 0xFF, //
        ...'WEBP'.codeUnits,
      ]),
    );
  chunks.forEach(out.add);
  return out.takeBytes();
}

/// V2-2b B13: a file mention being typed — the `@` at [start] and the [query] after it, up to the cursor.
typedef AiMentionToken = ({int start, String query});

/// V2-2b B13: `@` mentions in the AI composer, as the desktop's composer has them (D16): the token being typed
/// at the cursor, the path that replaces it, and the paths still mentioned when the message goes.
abstract final class AiMentions {
  /// The longest query sent to the computer, in UTF-8 bytes; a longer one asks nothing.
  static const int maxQueryBytes = 200;

  /// The most suggestions shown.
  static const int maxSuggestions = 8;

  /// The `@query` that ends at the cursor of [value]: an `@` at the start of the text or after a space, then at
  /// least one character and no space up to the cursor. Null for anything else: no collapsed cursor, no `@`
  /// (or one inside a word: `me@host`), an empty or too long query.
  static AiMentionToken? tokenAt(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final text = value.text;
    final end = selection.baseOffset;
    if (end <= 0 || end > text.length) return null;
    var at = end - 1;
    while (at >= 0 && text[at] != '@') {
      if (text[at].trim().isEmpty) return null;
      at--;
    }
    if (at < 0) return null;
    if (at > 0 && text[at - 1].trim().isNotEmpty) return null;
    final query = text.substring(at + 1, end);
    if (query.isEmpty || utf8.encode(query).length > maxQueryBytes) return null;
    return (start: at, query: query);
  }

  /// [value] with [token] replaced by `@path ` and the cursor after it.
  static TextEditingValue insert(TextEditingValue value, AiMentionToken token, String path) {
    final mention = '@$path ';
    final end = token.start + 1 + token.query.length;
    final text = value.text.replaceRange(token.start, end, mention);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: token.start + mention.length),
    );
  }

  /// The paths of [remembered] whose `@path` is still in [text], at most [kAiMaxPromptFiles]: a mention deleted
  /// from the text does not go.
  static List<String> stillMentioned(String text, Iterable<String> remembered) => [
    for (final path in remembered)
      if (text.contains('@$path')) path,
  ].take(kAiMaxPromptFiles).toList();
}
