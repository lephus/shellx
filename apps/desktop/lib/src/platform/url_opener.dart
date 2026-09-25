import 'dart:io';

typedef UrlCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class UrlOpener {
  Future<void> open(Uri uri);
}

/// Opens URLs (download links, the macOS Full Disk Access pane) with the OS.
///
/// Opens only absolute `https` URLs, plus [fullDiskAccessPane] on macOS;
/// anything else throws [ArgumentError] without running a command. Windows'
/// `url.dll,FileProtocolHandler` runs `file:` and UNC executables, and
/// macOS `open` opens any app or file (and reads a leading `-` as an
/// option), so nothing else may reach them.
final class SystemUrlOpener implements UrlOpener {
  SystemUrlOpener({bool? isWindows, UrlCommandRunner? run})
    : _isWindows = isWindows ?? Platform.isWindows,
      _run = run ?? Process.run;

  static final Uri fullDiskAccessPane = Uri.parse(
    'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
  );

  final bool _isWindows;
  final UrlCommandRunner _run;

  @override
  Future<void> open(Uri uri) async {
    final allowed = _isWindows
        ? _isHttps(uri)
        : _isHttps(uri) || uri == fullDiskAccessPane;
    if (!allowed) {
      throw ArgumentError.value(uri.scheme, 'uri', 'Only https URLs open');
    }
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
    } else {
      await _run('/usr/bin/open', [uri.toString()]);
    }
  }

  static bool _isHttps(Uri uri) =>
      uri.isAbsolute && uri.scheme == 'https' && uri.host.isNotEmpty;
}
