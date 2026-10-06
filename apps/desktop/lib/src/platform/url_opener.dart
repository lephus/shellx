import 'dart:io';

typedef UrlCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class UrlOpener {
  Future<void> open(Uri uri);

  /// A2 D9: `http://localhost:<port>/` in the default browser — the only
  /// non-https URL that ever opens. Throws [ArgumentError] for a port
  /// outside 1–65535.
  Future<void> openLocalPort(int port);
}

/// Opens URLs (download links, the macOS Full Disk Access pane) with the OS.
///
/// Opens only absolute `https` URLs, plus [fullDiskAccessPane] on macOS,
/// plus `http://localhost:<port>/` through [openLocalPort]; anything else
/// throws [ArgumentError] without running a command. Windows'
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

  @override
  Future<void> openLocalPort(int port) async {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Not a TCP port');
    }
    // Built from the number alone: nothing user-typed reaches the command.
    final url = 'http://localhost:$port/';
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await _run('/usr/bin/open', [url]);
    }
  }

  static bool _isHttps(Uri uri) =>
      uri.isAbsolute && uri.scheme == 'https' && uri.host.isNotEmpty;
}
