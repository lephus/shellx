import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A5b D5: what the `mux/endpoint` file says. Secret and instance are new
/// every time the host starts.
final class MuxEndpointInfo {
  const MuxEndpointInfo({
    required this.address,
    required this.secret,
    required this.pid,
    required this.instance,
    required this.protocol,
    required this.app,
  });

  /// Socket path (macOS) or pipe name (Windows).
  final String address;
  final Uint8List secret;
  final int pid;

  /// 32 hex.
  final String instance;
  final int protocol;

  /// `x.y.z`.
  final String app;

  /// The file's exact contents: seven lines, trailing newline.
  String format() =>
      'v=1\n'
      'address=$address\n'
      'secret=${bytesToHex(secret).toLowerCase()}\n'
      'pid=$pid\n'
      'instance=$instance\n'
      'protocol=$protocol\n'
      'app=$app\n';

  /// Null unless `v=1` and every key is present and well-formed.
  static MuxEndpointInfo? parse(String text) {
    final values = <String, String>{};
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final at = line.indexOf('=');
      if (at <= 0) return null;
      values[line.substring(0, at)] = line.substring(at + 1);
    }
    if (values['v'] != '1') return null;
    final address = values['address'];
    final secretHex = values['secret'];
    final pid = int.tryParse(values['pid'] ?? '');
    final instance = values['instance'];
    final protocol = int.tryParse(values['protocol'] ?? '');
    final app = values['app'];
    if (address == null ||
        address.isEmpty ||
        secretHex == null ||
        secretHex.length != 64 ||
        pid == null ||
        instance == null ||
        protocol == null ||
        app == null) {
      return null;
    }
    final Uint8List secret;
    try {
      secret = hexToBytes(secretHex);
    } on FormatException {
      return null;
    }
    if (secret.length != 32) return null;
    return MuxEndpointInfo(
      address: address,
      secret: secret,
      pid: pid,
      instance: instance,
      protocol: protocol,
      app: app,
    );
  }
}

/// Writes, reads and removes the `mux/endpoint` file — the same steps as
/// `EndpointFile` (`term_endpoint.dart`).
final class MuxEndpointFile {
  MuxEndpointFile(this.path, {bool? posix})
    : _posix = posix ?? !Platform.isWindows;

  final String path;
  final bool _posix;

  /// Writes atomically (temp file, then rename). On POSIX the directory is
  /// made 0700 and the temp file 0600 **before** the secret goes in.
  /// Windows files inherit `%LOCALAPPDATA%`'s owner-only access. Returns
  /// the contents written, for [deleteIfOwned].
  Future<String> write(MuxEndpointInfo info) async {
    final contents = info.format();
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

  /// Null when the file is missing, unreadable or malformed.
  Future<MuxEndpointInfo?> read() async {
    try {
      return MuxEndpointInfo.parse(await File(path).readAsString());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Deletes the file only while it still holds [contents]: a newer host
  /// may have replaced it. Never throws for a missing file.
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
