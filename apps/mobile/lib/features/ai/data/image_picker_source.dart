import 'dart:io';

import 'package:flutter/foundation.dart';
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
///
/// The files the pickers write for it (in the app's cache folder on Android, its temporary folder on iOS) are deleted
/// as soon as their bytes are read (F55), whatever comes of them — a photo the composer refuses, a read that failed:
/// ShellX keeps no photo.
@LazySingleton(as: AiImageSource)
class ImagePickerSource implements AiImageSource {
  ImagePickerSource() : this.withPicker(ImagePicker());

  /// Over [picker], deleting with [delete] (a test's).
  @visibleForTesting
  ImagePickerSource.withPicker(this._picker, {Future<void> Function(String path)? delete})
    : _delete = delete ?? _deleteFile;

  final ImagePicker _picker;
  final Future<void> Function(String path) _delete;

  static Future<void> _deleteFile(String path) => File(path).delete();

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
    try {
      return [for (final file in files) await file.readAsBytes()];
    } finally {
      await _deleteAll(files);
    }
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
    if (file == null) return null;
    try {
      return await file.readAsBytes();
    } finally {
      await _deleteAll([file]);
    }
  }

  /// F55: the picker's files go, each on its own: one that cannot be deleted is left to the system's cleaning of that
  /// folder (nothing about it is logged but its error's type).
  Future<void> _deleteAll(List<XFile> files) async {
    for (final file in files) {
      try {
        await _delete(file.path);
      } catch (error) {
        if (kDebugMode) debugPrint('AI image delete error: ${error.runtimeType}');
      }
    }
  }
}
