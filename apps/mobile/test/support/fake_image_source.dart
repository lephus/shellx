import 'dart:typed_data';

import 'package:shellx_mobile/features/ai/domain/ai_image_source.dart';

/// A real 1×1 PNG (68 bytes): it decodes, so a thumbnail of it draws.
final Uint8List kTinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, //
  0x89, 0x00, 0x00, 0x00, 0x0b, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0xe9, 0xfa, 0xdc, 0xd8, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, //
  0xae, 0x42, 0x60, 0x82,
]);

/// A JPEG of exactly [length] bytes (at least 19) that is no picture but walks like one: SOI, a quantization table,
/// the scan header, zeros for the scan and EOI. For tests of sizes: the composer takes only images whose structure
/// it can walk, to remove their metadata (V2-2b F38), and counts their bytes after that.
Uint8List jpegOfSize(int length) {
  const head = [0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x03, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00];
  const tail = [0xFF, 0xD9];
  assert(length >= head.length + tail.length, 'too short for a JPEG that walks');
  return Uint8List(length)
    ..setAll(0, head)
    ..setAll(length - tail.length, tail);
}

/// The phone's photos in tests (V2-2b B12): what the library and the camera give, every call recorded.
class FakeAiImageSource implements AiImageSource {
  /// What the library gives (the first `limit` of them).
  List<Uint8List> photos = [];

  /// What the camera gives; null: the user took none.
  Uint8List? photo;

  /// Thrown by both (a permission refused, a picker that failed).
  Object? error;

  final List<int> limits = [];
  int cameraCalls = 0;

  @override
  Future<List<Uint8List>> pickPhotos({required int limit}) async {
    limits.add(limit);
    final failure = error;
    if (failure != null) throw failure;
    return photos.take(limit).toList();
  }

  @override
  Future<Uint8List?> takePhoto() async {
    cameraCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return photo;
  }
}
