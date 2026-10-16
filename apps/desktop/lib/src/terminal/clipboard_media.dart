import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';

import 'paste_image_store.dart';

/// What the system clipboard holds besides text (A10 D15). Flutter's own
/// `Clipboard` reads text only.
abstract interface class ClipboardMedia {
  /// Absolute paths of files copied in Finder / Explorer; empty when none.
  Future<List<String>> files();

  /// An image on the clipboard (PNG, JPEG, BMP, ...); null when none.
  Future<Uint8List?> image();
}

/// `pasteboard` (macOS and Windows). A plugin that fails or hangs is "no
/// files / no image": a paste never waits on it for more than 2 s.
final class SystemClipboardMedia implements ClipboardMedia {
  const SystemClipboardMedia({
    Future<List<String>> Function() readFiles = Pasteboard.files,
    bool Function(String path) exists = _onDisk,
  }) : _readFiles = readFiles,
       _exists = exists;

  final Future<List<String>> Function() _readFiles;
  final bool Function(String path) _exists;

  static const _limit = Duration(seconds: 2);

  static bool _onDisk(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// Only paths that exist: on macOS a copied web link (`https://host/a.png`)
  /// also reads as the "file" `/a.png`, and pasting that would swallow the
  /// link.
  @override
  Future<List<String>> files() async {
    try {
      final paths = await _readFiles().timeout(_limit);
      return [
        for (final path in paths)
          if (_exists(path)) path,
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<Uint8List?> image() async {
    try {
      return await Pasteboard.image.timeout(_limit);
    } on Object {
      return null;
    }
  }
}

final clipboardMediaProvider = Provider<ClipboardMedia>(
  (ref) => const SystemClipboardMedia(),
);

/// Pasted images live in the app's private support folder (A10 D15):
/// `main` overrides this with `getApplicationSupportDirectory()`. The
/// default (tests) is the system temp folder.
final pasteImageStoreProvider = Provider<PasteImageStore>(
  (ref) => PasteImageStore(Directory.systemTemp),
);
