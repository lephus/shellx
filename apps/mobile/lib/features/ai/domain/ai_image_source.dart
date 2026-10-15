import 'dart:typed_data';

/// V2-2b B12: where the photos of a message come from — the phone's photo library (several at once) or its
/// camera. Each comes back at most 2048 px on its longer side, JPEG of quality 85 when the picker re-encodes it
/// (a HEIC photo becomes a JPEG then; the composer checks the type anyway), without its metadata. Throws what the
/// platform throws (a permission refused); the composer says so.
abstract interface class AiImageSource {
  /// Up to [limit] (1–5) photos of the library, in the order picked; empty when none was.
  Future<List<Uint8List>> pickPhotos({required int limit});

  /// One photo from the camera; null when none was taken.
  Future<Uint8List?> takePhoto();
}
