import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Where the agent tells `shellx-term` how to reach it (spec §6.1): macOS
/// `$HOME/Library/Application Support/ShellX/term/endpoint`, Windows
/// `%LOCALAPPDATA%\ShellX\term\endpoint` — the same paths
/// `term/src/proto/endpoint.rs` reads.
String termEndpointPath({
  required Map<String, String> environment,
  required bool windows,
}) {
  final variable = windows ? 'LOCALAPPDATA' : 'HOME';
  final base = environment[variable];
  if (base == null || base.isEmpty) throw StateError('$variable is not set');
  return windows
      ? '$base\\ShellX\\term\\endpoint'
      : '$base/Library/Application Support/ShellX/term/endpoint';
}

/// The file's exact contents: three lines, trailing newline (spec §6.1).
String formatEndpoint(int port, Uint8List secret) =>
    'v=1\nport=$port\nsecret=${bytesToHex(secret).toLowerCase()}\n';

/// Writes and removes the `endpoint` file.
final class EndpointFile {
  EndpointFile(this.path, {bool? posix})
    : _posix = posix ?? !Platform.isWindows;

  final String path;
  final bool _posix;

  /// Writes atomically (temp file, then rename). On POSIX the directory is
  /// made 0700 and the temp file 0600 **before** the secret goes in, so the
  /// secret is never readable by another account, even briefly. Windows
  /// files inherit `%LOCALAPPDATA%`'s owner-only access. Returns the
  /// contents written, for [deleteIfOwned].
  Future<String> write(int port, Uint8List secret) async {
    final contents = formatEndpoint(port, secret);
    final directory = File(path).parent;
    await directory.create(recursive: true);
    if (_posix) await _chmod('700', directory.path);
    final temp = File(
      '$path.tmp-$pid-${Random.secure().nextInt(1 << 32).toRadixString(16)}',
    );
    try {
      await temp.writeAsBytes(const [], flush: true);
      if (_posix) await _chmod('600', temp.path);
      await temp.writeAsString(contents, flush: true);
      await temp.rename(path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
    return contents;
  }

  /// Deletes the file only while it still holds [contents]: a newer start
  /// (or another agent instance) may have replaced it. Never throws for a
  /// missing file.
  Future<void> deleteIfOwned(String contents) async {
    final file = File(path);
    try {
      if (await file.readAsString() == contents) await file.delete();
    } on FileSystemException {
      // Already gone, or unreadable: nothing of ours to remove.
    }
  }

  static Future<void> _chmod(String mode, String target) async {
    final result = await Process.run('/bin/chmod', [mode, target]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed', target);
    }
  }
}
