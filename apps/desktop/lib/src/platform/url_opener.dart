import 'dart:io';

typedef UrlCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class UrlOpener {
  Future<void> open(Uri uri);
}

/// Opens URLs (download links, the macOS Full Disk Access pane) with the OS.
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
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
    } else {
      await _run('/usr/bin/open', [uri.toString()]);
    }
  }
}
