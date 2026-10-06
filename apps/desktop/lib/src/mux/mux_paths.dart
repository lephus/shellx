import 'package:shellx_agent/shellx_agent.dart';

/// The macOS bundle id: `path_provider`'s application support directory
/// for this unsandboxed app is `~/Library/Application Support/<id>`.
const kMacBundleId = 'pro.shellx.desktop';

/// A5b D5 / A7 D30: macOS `$HOME/Library/Application Support/
/// pro.shellx.desktop/mux`, Windows `%LOCALAPPDATA%\ShellX\mux`. Built from
/// the environment, as `term/` (Rust) does, so both read the same file.
/// Throws [StateError] when `HOME` / `LOCALAPPDATA` is not set.
String muxDirectoryPath({
  required bool windows,
  required Map<String, String> environment,
}) {
  final variable = windows ? 'LOCALAPPDATA' : 'HOME';
  final base = environment[variable];
  if (base == null || base.isEmpty) throw StateError('$variable is not set');
  return windows
      ? '$base\\ShellX\\mux'
      : '$base/Library/Application Support/$kMacBundleId/mux';
}

/// Where the mux host keeps its endpoint file and lock, and the address it
/// listens on (A5b Task 7).
final class MuxPaths {
  MuxPaths({
    required this.muxDirectory,
    required this.tmpDirectory,
    required this.uid,
    required this.windows,
    this.pipeName,
  }) : assert(!windows || pipeName != null, 'Windows needs a pipe name');

  final String muxDirectory;
  final String tmpDirectory;
  final int uid;
  final bool windows;

  /// `pipeNameForUser(currentUserSid())` on Windows.
  final String? pipeName;

  String get _separator => windows ? r'\' : '/';

  String get endpoint => '$muxDirectory${_separator}endpoint';

  String get lock => '$muxDirectory${_separator}mux.lock';

  /// The pipe name (Windows) or the socket path (macOS, with the TMPDIR
  /// fallback for paths over 103 bytes).
  String get address => windows
      ? pipeName!
      : socketPathFor(
          muxDirectory: muxDirectory,
          tmpDirectory: tmpDirectory,
          uid: uid,
        );
}
