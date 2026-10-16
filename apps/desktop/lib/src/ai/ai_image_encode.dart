import 'dart:convert';
import 'dart:typed_data';

import 'ai_off_thread.dart';

/// Above this many bytes of images in a message, base64 runs off the UI
/// isolate (smoothness: 10 MiB is ~100 ms of it).
const int kAiInlineEncodeBytes = 256 << 10;

String _base64(Uint8List bytes) => base64Encode(bytes);

/// [images] as base64 for the `image` blocks, off the UI isolate when they
/// are many bytes (the composer's, V2-1 D16, and a phone's, V2-2b B12).
Future<List<String>> aiEncodeImages(OffThread run, List<Uint8List> images) {
  final bytes = images.fold<int>(0, (n, b) => n + b.length);
  return bytes > kAiInlineEncodeBytes
      ? Future.wait([for (final b in images) run(_base64, b)])
      : Future.value([for (final b in images) _base64(b)]);
}
