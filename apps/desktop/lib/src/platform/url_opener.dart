import 'dart:io';

import 'package:shellx_core/shellx_core.dart' show webUriOf;

import 'editor_links.dart';

typedef UrlCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class UrlOpener {
  Future<void> open(Uri uri);

  /// A2 D9: `http://localhost:<port>/` in the default browser — the only
  /// non-https URL that ever opens. Throws [ArgumentError] for a port
  /// outside 1–65535.
  Future<void> openLocalPort(int port);

  /// A10 D6: a link the user clicked in the terminal — `http` or `https`
  /// only. Throws [ArgumentError] for anything else without running a
  /// command. [open] stays https-only: it is for links the app itself
  /// builds.
  Future<void> openWebLink(Uri uri);

  /// V2-3 D9: a tool page's `mailto:` or `tel:` link, handed to the
  /// system's mail or phone app. Throws [ArgumentError] for any other
  /// scheme, a link of more than 2 048 characters or one with a control
  /// character, without running a command.
  Future<void> openMailOrPhone(Uri uri);

  /// A10 D7: shows [path] (absolute) selected in Finder / Explorer — a
  /// folder too, so a `.app` bundle is never launched. Never runs the file. Throws [ArgumentError] for a path that is
  /// not absolute or holds a control character.
  Future<void> reveal(String path, {required bool isDirectory});

  /// `link-editor`: opens the FILE [path] (absolute) in [editor] at [line]
  /// and [column] through the editor's URL handler
  /// (`vscode://file/<path>:<line>:<col>`, see [editorFileUrl]). Only a
  /// URL with the editor's scheme reaches the OS — never the path itself,
  /// so nothing is run. Throws [ArgumentError] for a path that is not
  /// absolute or holds a control character, without running a command.
  Future<void> openInEditor(
    EditorApp editor,
    String path, {
    int? line,
    int? column,
  });
}

/// Opens URLs (download links, the macOS Full Disk Access pane) with the OS.
///
/// Opens only absolute `https` URLs, plus [fullDiskAccessPane] on macOS,
/// plus `http://localhost:<port>/` through [openLocalPort], plus the
/// `cursor:` / `vscode:` / `zed:` file URLs [openInEditor] builds, plus the
/// `mailto:` / `tel:` links [openMailOrPhone] takes; anything else
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

  @override
  Future<void> openWebLink(Uri uri) async {
    if (webUriOf(uri.toString()) == null) {
      throw ArgumentError.value(uri.scheme, 'uri', 'Only http(s) links open');
    }
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
    } else {
      await _run('/usr/bin/open', [uri.toString()]);
    }
  }

  @override
  Future<void> openMailOrPhone(Uri uri) async {
    final text = uri.toString();
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'mailto' && scheme != 'tel') ||
        text.length > 2048 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(text)) {
      throw ArgumentError.value(scheme, 'uri', 'Only mailto: and tel: open');
    }
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', text]);
    } else {
      await _run('/usr/bin/open', [text]);
    }
  }

  @override
  Future<void> reveal(String path, {required bool isDirectory}) async {
    final absolute = _isWindows
        ? RegExp(r'^[A-Za-z]:\\').hasMatch(path)
        : path.startsWith('/');
    if (!absolute || RegExp(r'[\u0000-\u001f\u007f]').hasMatch(path)) {
      throw ArgumentError.value('path', 'path', 'Not an absolute path');
    }
    // Always "show", never "open": a `.app` bundle is a directory, and
    // `open <dir>` (or explorer on an `.exe`) would start the program.
    // [isDirectory] only matters to the caller's menu text.
    if (_isWindows) {
      await _run('explorer.exe', ['/select,$path']);
    } else {
      await _run('/usr/bin/open', ['-R', path]);
    }
  }

  @override
  Future<void> openInEditor(
    EditorApp editor,
    String path, {
    int? line,
    int? column,
  }) async {
    // Built from a fixed scheme and the encoded path: a `-` or a space can
    // never start an option, and no `file:` URL reaches the handler.
    final url = editorFileUrl(
      editor,
      path,
      line: line,
      column: column,
      windows: _isWindows,
    );
    if (_isWindows) {
      await _run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await _run('/usr/bin/open', [url]);
    }
  }

  static bool _isHttps(Uri uri) =>
      uri.isAbsolute && uri.scheme == 'https' && uri.host.isNotEmpty;
}
