import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// An image bigger than this is not pasted (A10 D15).
const int kMaxPasteImageBytes = 20 * 1024 * 1024;

/// At most this many pasted images are kept; older ones go first.
const int kMaxPasteImageFiles = 50;

/// A pasted image older than this is deleted.
const Duration kPasteImageMaxAge = Duration(hours: 24);

final class PasteImageTooLarge implements Exception {
  const PasteImageTooLarge();
}

final class PasteImageUnreadable implements Exception {
  const PasteImageUnreadable();
}

/// The file extension for the image whose first bytes are [bytes], or null
/// when they are none of the formats a clipboard gives.
String? imageExtension(Uint8List bytes) {
  bool starts(List<int> magic) =>
      bytes.length >= magic.length &&
      [
        for (var i = 0; i < magic.length; i++) bytes[i] == magic[i],
      ].every((e) => e);
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (starts(const [0x42, 0x4D])) return 'bmp';
  if (starts(const [0x49, 0x49, 0x2A, 0x00]) ||
      starts(const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'tiff';
  }
  return null;
}

/// A10 D15: keeps a pasted image as a file in a private folder (the app's
/// support folder) so its
/// path can be pasted. The folder is 0700 and the files 0600 (POSIX); files
/// older than [kPasteImageMaxAge] and any beyond [kMaxPasteImageFiles] are
/// deleted whenever a new one is saved. Nothing here logs a path or a size.
class PasteImageStore {
  PasteImageStore(
    this.base, {
    DateTime Function()? now,
    Random? random,
    bool? posix,
    Future<bool> Function(String mode, List<String> paths)? chmod,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure(),
       _posix = posix ?? !Platform.isWindows,
       _chmod = chmod ?? _systemChmod;

  /// The app's private support folder (`getApplicationSupportDirectory`).
  final Directory base;
  final DateTime Function() _now;
  final Random _random;
  final bool _posix;
  final Future<bool> Function(String mode, List<String> paths) _chmod;

  Directory get directory => Directory(p.join(base.path, 'paste-images'));

  /// Saves [bytes] and returns the file's path. Throws
  /// [PasteImageTooLarge], [PasteImageUnreadable] (empty, or not an image),
  /// or a [FileSystemException].
  Future<String> save(Uint8List bytes) async {
    if (bytes.length > kMaxPasteImageBytes) throw const PasteImageTooLarge();
    final ext = imageExtension(bytes);
    if (bytes.isEmpty || ext == null) throw const PasteImageUnreadable();
    // A link in place of the folder (planted by another process) would send
    // the image elsewhere: refuse.
    _requirePlainDirectory(allowMissing: true);
    await directory.create(recursive: true);
    _requirePlainDirectory(allowMissing: false);
    if (_posix && !await _chmod('700', [directory.path])) {
      throw const FileSystemException('chmod 700 failed');
    }
    await _clean();
    final at = _now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    final id = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    final file = File(p.join(directory.path, 'paste-$stamp-$id.$ext'));
    // 0600 before any content goes in.
    await file.create(exclusive: true);
    if (_posix && !await _chmod('600', [file.path])) {
      await _delete(file);
      throw const FileSystemException('chmod 600 failed');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void _requirePlainDirectory({required bool allowMissing}) {
    final type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    if (type == FileSystemEntityType.directory) return;
    if (type == FileSystemEntityType.notFound && allowMissing) return;
    throw const FileSystemException('the image folder is not a plain folder');
  }

  /// Deletes what is too old, then the oldest beyond the cap (room for the
  /// one about to be saved).
  Future<void> _clean() async {
    final files = <(File, DateTime)>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        files.add((entity, (await entity.stat()).modified));
      }
    } on FileSystemException {
      return;
    }
    final cutoff = _now().subtract(kPasteImageMaxAge);
    final keep = <(File, DateTime)>[];
    for (final f in files) {
      if (f.$2.isBefore(cutoff)) {
        await _delete(f.$1);
      } else {
        keep.add(f);
      }
    }
    keep.sort((a, b) => a.$2.compareTo(b.$2));
    while (keep.length >= kMaxPasteImageFiles) {
      await _delete(keep.removeAt(0).$1);
    }
  }

  /// Quit: nothing a closed app needs is left.
  Future<void> deleteAll() async {
    try {
      // Never through a link: that would empty somewhere else.
      final type = FileSystemEntity.typeSync(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.directory) {
        await directory.delete(recursive: true);
      } else if (type == FileSystemEntityType.link) {
        await Link(directory.path).delete();
      }
    } on FileSystemException {
      // Best effort.
    }
  }

  static Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  static Future<bool> _systemChmod(String mode, List<String> paths) async {
    try {
      final result = await Process.run('/bin/chmod', [mode, ...paths]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
