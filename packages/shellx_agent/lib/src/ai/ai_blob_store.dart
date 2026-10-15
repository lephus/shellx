import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_ai/remote.dart' show kAiImageMaxBytes, kAiImagesMax;
import 'package:shellx_core/shellx_core.dart';

/// One image a phone is uploading, or has uploaded.
final class _Blob {
  _Blob(int parts) : pieces = List<Uint8List?>.filled(parts, null);

  final List<Uint8List?> pieces;
  String? mime;
  int bytes = 0;
  late DateTime touched;

  /// Every part came: the image, whole (the pieces are let go then).
  Uint8List? whole;
}

/// V2-2b B12: the images phones upload for their next prompt (`ai.blob`, in
/// parts of at most [kAiMaxBlobPartBytes]), held in memory until a prompt
/// takes them — never written anywhere, never logged. Per phone at most
/// [kAiImagesMax] images, [kAiImageMaxBytes] each and [phoneBytes] in all: an
/// image that needs room takes it from the phone's least recently used ones
/// (a prompt names [kAiImagesMax] at most, and a phone whose upload failed
/// uploads its images again under new numbers). An image nothing touched for
/// [idle] is dropped — at once by any use, and by a timer within twice
/// [idle] without one — and everything a phone uploaded goes when it leaves
/// ([dropPhone]).
final class AiBlobStore {
  AiBlobStore({
    DateTime Function()? now,
    this.idle = const Duration(minutes: 2),
    this.phoneBytes = 20 << 20,
  }) : _now = now ?? DateTime.now;

  /// The most parts an image of [kAiImageMaxBytes] takes.
  static const int maxParts =
      (kAiImageMaxBytes + kAiMaxBlobPartBytes - 1) ~/ kAiMaxBlobPartBytes;

  final DateTime Function() _now;
  final Duration idle;
  final int phoneBytes;

  /// Per phone, its images by number, the least recently used first.
  final _phones = <String, Map<int, _Blob>>{};
  Timer? _sweeper;

  /// Takes [part] of [phone]'s image [AiBlob.blob]. Null when taken — a part
  /// sent again replaces itself, and one of an image already whole changes
  /// nothing —, else the code of its `ai.result`: `refused` for a part that
  /// does not fit (a count of parts other than before, a number out of range,
  /// nothing or too much in it, no type on part 0), `too_large` for an image
  /// over [kAiImageMaxBytes] or [phoneBytes] (it is dropped).
  String? put(String phone, AiBlob part) {
    _sweep();
    final n = part.parts;
    if (n < 1 ||
        n > maxParts ||
        part.part < 0 ||
        part.part >= n ||
        part.data.isEmpty ||
        part.data.length > kAiMaxBlobPartBytes) {
      return 'refused';
    }
    final mime = part.mime;
    final typed = mime != null && mime.isNotEmpty && mime.length <= 100;
    final held = _phones[phone]?[part.blob];
    if ((part.part == 0 && !typed) ||
        (held != null && held.pieces.length != n)) {
      return 'refused';
    }
    final blobs = _phones.putIfAbsent(phone, () => {});
    final blob = blobs.remove(part.blob) ?? _Blob(n);
    blobs[part.blob] = blob..touched = _now(); // the most recently used, last
    if (blob.whole != null) return null;
    final size =
        blob.bytes - (blob.pieces[part.part]?.length ?? 0) + part.data.length;
    if (size > kAiImageMaxBytes || size > phoneBytes) {
      blobs.remove(part.blob);
      if (blobs.isEmpty) _phones.remove(phone);
      return 'too_large';
    }
    blob.pieces[part.part] = part.data;
    blob.bytes = size;
    if (part.part == 0) blob.mime = mime;
    // Room for it: the least recently used images go (this one is last).
    while (blobs.length > kAiImagesMax || _held(blobs) > phoneBytes) {
      blobs.remove(blobs.keys.first);
    }
    if (blob.pieces.every((p) => p != null)) {
      final whole = BytesBuilder(copy: false);
      for (final piece in blob.pieces) {
        whole.add(piece!);
      }
      blob.whole = whole.takeBytes();
      blob.pieces.fillRange(0, n, null);
    }
    _arm();
    return null;
  }

  /// Whether [phone]'s image [blob] came whole.
  bool complete(String phone, int blob) {
    _sweep();
    return _phones[phone]?[blob]?.whole != null;
  }

  /// [phone]'s image [blob] when it came whole, left in the store (used:
  /// it is the most recently used now); null otherwise.
  ({String? mime, Uint8List bytes})? peek(String phone, int blob) {
    _sweep();
    final blobs = _phones[phone];
    final b = blobs?.remove(blob);
    if (blobs == null || b == null) return null;
    blobs[blob] = b..touched = _now();
    final whole = b.whole;
    return whole == null ? null : (mime: b.mime, bytes: whole);
  }

  /// [peek], and the image leaves the store: a prompt took it.
  ({String? mime, Uint8List bytes})? take(String phone, int blob) {
    final image = peek(phone, blob);
    if (image == null) return null;
    final blobs = _phones[phone]!..remove(blob);
    if (blobs.isEmpty) _phones.remove(phone);
    return image;
  }

  /// The bytes [phone] holds here now.
  int heldBy(String phone) => _held(_phones[phone] ?? const {});

  /// [phone] left: what it uploaded goes.
  void dropPhone(String phone) => _phones.remove(phone);

  /// Everything goes: every phone left, or the hub is disposed.
  void clear() {
    _phones.clear();
    _sweeper?.cancel();
    _sweeper = null;
  }

  int _held(Map<int, _Blob> blobs) =>
      blobs.values.fold(0, (n, b) => n + b.bytes);

  /// Drops every image nothing touched for [idle]. A clock set back says
  /// nothing of how long ago: nothing goes then.
  void _sweep() {
    final now = _now();
    _phones.removeWhere((_, blobs) {
      blobs.removeWhere((_, b) {
        final since = now.difference(b.touched);
        return !since.isNegative && since >= idle;
      });
      return blobs.isEmpty;
    });
  }

  /// Wakes the store [idle] from now, and again while it holds images: what
  /// nobody uses goes without waiting for the next request.
  void _arm() {
    if (_sweeper != null) return;
    _sweeper = Timer(idle, () {
      _sweeper = null;
      _sweep();
      if (_phones.isNotEmpty) _arm();
    });
  }
}
