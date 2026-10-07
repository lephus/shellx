import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:shellx_desktop/src/config/config_files.dart';
import 'package:shellx_desktop/src/config/config_writer.dart';

/// A9: an in-memory [ConfigFs]; every write bumps a fake modification time.
final class MemoryConfigFs implements ConfigFs, ConfigFileStore {
  final Map<String, Uint8List> files = {};
  final Map<String, int> _modified = {};
  final Set<String> unreadable = {};
  int _clock = 0;
  int reads = 0;

  /// Every [replace] that was made, in order (path only).
  final List<String> replaced = [];

  /// Runs inside [replace] after the writer read the file and before the
  /// check: a test changes the file there, like another process would.
  void Function(String path)? beforeReplace;

  /// When set, [replace] throws it (a disk that refuses the write).
  Object? replaceError;

  /// When set, [read] throws it (a bug in the platform layer, D10).
  Object? readError;

  /// When set, [read] takes the file's bytes, then waits for it (a slow
  /// disk): tests use it to see what runs while a read is in flight.
  Future<void>? readGate;

  /// Like [readGate], for [stamp] (a slow `stat`).
  Future<void>? stampGate;

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
    final gate = readGate;
    if (gate != null) await gate;
    if (bytes != null && bytes.length > kConfigMaxBytes) {
      throw const ConfigTooLarge();
    }
    return bytes;
  }

  @override
  Future<FileStamp> stamp(String path) async {
    final gate = stampGate;
    if (gate != null) await gate;
    final bytes = files[path];
    return bytes == null
        ? const FileStamp.missing()
        : FileStamp(
            exists: true,
            size: bytes.length,
            modifiedMs: _modified[path]!,
          );
  }

  @override
  Future<void> replace(
    String path,
    Uint8List bytes, {
    Uint8List? expected,
    bool mustNotExist = false,
  }) async {
    beforeReplace?.call(path);
    final error = replaceError;
    if (error != null) throw error;
    final now = files[path];
    final unchanged = mustNotExist
        ? now == null
        : expected == null || (now != null && listEquals(now, expected));
    if (!unchanged) throw const ConfigWriteRefused(ConfigWriteRefusal.changed);
    replaced.add(path);
    writeBytes(path, bytes);
  }
}
