import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shellx_mobile/features/ai/data/image_picker_source.dart';

/// What the system pickers hand over: files the plugin wrote (a scaled copy, the photo's metadata still in it).
class _FakePicker implements ImagePicker {
  List<XFile> library = [];
  XFile? camera;

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async => library;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => camera;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A file the picker named that cannot be read (gone, or a disk error).
class _Unreadable extends XFile {
  _Unreadable(super.path);

  @override
  Future<Uint8List> readAsBytes() => Future.error(const FileSystemException('unreadable'));
}

XFile _photo(String path, List<int> bytes) => XFile.fromData(Uint8List.fromList(bytes), path: path);

/// V2-2b B12, F55: the files the pickers write — in the app's cache (Android) or temporary folder (iOS), with the
/// photo's metadata in them, its place included — are deleted as soon as their bytes are read, whatever comes of
/// them: ShellX keeps no photo.
void main() {
  late _FakePicker picker;
  late List<String> deleted;
  late ImagePickerSource source;

  setUp(() {
    picker = _FakePicker();
    deleted = [];
    source = ImagePickerSource.withPicker(picker, delete: (path) async => deleted.add(path));
  });

  test('the library: every photo is read, then its file deleted', () async {
    picker.library = [
      _photo('/cache/a.jpg', [1, 2, 3]),
      _photo('/cache/b.jpg', [4, 5]),
    ];
    final photos = await source.pickPhotos(limit: 2);
    expect(photos, [
      [1, 2, 3],
      [4, 5],
    ]);
    expect(deleted, ['/cache/a.jpg', '/cache/b.jpg']);
  });

  test('a read that fails: every file picked is deleted all the same, and the error reaches the page', () async {
    picker.library = [
      _photo('/cache/a.jpg', [1]),
      _Unreadable('/cache/b.jpg'),
      _photo('/cache/c.jpg', [3]),
    ];
    await expectLater(source.pickPhotos(limit: 3), throwsA(isA<FileSystemException>()));
    expect(deleted, ['/cache/a.jpg', '/cache/b.jpg', '/cache/c.jpg']);
  });

  test('a file that cannot be deleted changes nothing for the photos', () async {
    final failing = ImagePickerSource.withPicker(
      picker,
      delete: (path) => Future.error(const FileSystemException('busy')),
    );
    picker.library = [
      _photo('/cache/a.jpg', [1]),
    ];
    expect(await failing.pickPhotos(limit: 1), [
      [1],
    ]);
  });

  test('the camera: the photo is read, then its file deleted; none taken, nothing to delete', () async {
    picker.camera = _photo('/tmp/cam.jpg', [9, 9]);
    expect(await source.takePhoto(), [9, 9]);
    expect(deleted, ['/tmp/cam.jpg']);
    picker.camera = _Unreadable('/tmp/cam2.jpg');
    await expectLater(source.takePhoto(), throwsA(isA<FileSystemException>()));
    expect(deleted, ['/tmp/cam.jpg', '/tmp/cam2.jpg']);
    picker.camera = null;
    expect(await source.takePhoto(), isNull);
    expect(deleted, hasLength(2));
  });
}
