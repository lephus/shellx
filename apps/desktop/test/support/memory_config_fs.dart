import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_desktop/src/config/config_files.dart';

/// A9: an in-memory [ConfigFs]; every write bumps a fake modification time.
final class MemoryConfigFs implements ConfigFs {
  final Map<String, Uint8List> files = {};
  final Map<String, int> _modified = {};
  final Set<String> unreadable = {};
  int _clock = 0;
  int reads = 0;

  /// When set, [read] throws it (a bug in the platform layer, D10).
  Object? readError;

  void write(String path, String text) => writeBytes(path, utf8.encode(text));

  void writeBytes(String path, List<int> bytes) {
    files[path] = Uint8List.fromList(bytes);
    _modified[path] = ++_clock;
  }

  void delete(String path) {
    files.remove(path);
    _modified.remove(path);
  }

  String text(String path) => utf8.decode(files[path]!);

  @override
  Future<Uint8List?> read(String path) async {
    reads++;
    final error = readError;
    if (error != null) throw error;
    if (unreadable.contains(path)) {
      throw FileSystemException('denied', path);
    }
    final bytes = files[path];
    if (bytes != null && bytes.length > kConfigMaxBytes) {
      throw const ConfigTooLarge();
    }
    return bytes;
  }

  @override
  Future<FileStamp> stamp(String path) async {
    final bytes = files[path];
    return bytes == null
        ? const FileStamp.missing()
        : FileStamp(
            exists: true,
            size: bytes.length,
            modifiedMs: _modified[path]!,
          );
  }
}
