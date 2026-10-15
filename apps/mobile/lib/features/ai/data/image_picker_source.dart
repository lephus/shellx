import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_image_source.dart';

/// [AiImageSource] over `image_picker` (V2-2b B12): the system photo picker (PHPicker on iOS, the Photo Picker on
/// Android — no permission asked for the library; `requestFullMetadata: false` keeps iOS from asking for the photo
/// library at all) and the system camera (iOS asks for the camera with `NSCameraUsageDescription`; Android asks at
/// run time for the CAMERA permission the app already declares).
///
/// `requestFullMetadata: false` only spares that permission. It does not take the photo's metadata out: iOS applies
/// the original's to the file it re-encodes (`FLTImagePickerMetaDataUtil`), Android copies its Exif, the GPS tags
/// among them (`ExifDataCopier`). What this hands over still carries it; the composer removes it
/// (`aiWithoutMetadata`, F38) before anything is sent.
@LazySingleton(as: AiImageSource)
class ImagePickerSource implements AiImageSource {
  final ImagePicker _picker = ImagePicker();

  /// The longer side of a photo sent (B12): enough for an agent to read a screenshot, light on the channel.
  static const double _side = 2048;
  static const int _quality = 85;

  @override
  Future<List<Uint8List>> pickPhotos({required int limit}) async {
    final files = await _picker.pickMultiImage(
      maxWidth: _side,
      maxHeight: _side,
      imageQuality: _quality,
      limit: limit,
      requestFullMetadata: false,
    );
    return [for (final file in files) await file.readAsBytes()];
  }

  @override
  Future<Uint8List?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _side,
      maxHeight: _side,
      imageQuality: _quality,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }
}
