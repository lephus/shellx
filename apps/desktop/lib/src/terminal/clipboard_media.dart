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
  const SystemClipboardMedia();

  static const _limit = Duration(seconds: 2);

  @override
  Future<List<String>> files() async {
    try {
      return await Pasteboard.files().timeout(_limit);
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

/// Pasted images live in the system temp folder (A10 D15).
final pasteImageStoreProvider = Provider<PasteImageStore>((ref) {
  final store = PasteImageStore(Directory.systemTemp);
  return store;
});
