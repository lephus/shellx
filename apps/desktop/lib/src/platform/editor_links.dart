import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/shellx_config.dart' show LinkEditor;

/// An editor that opens `<scheme>://file/<path>:<line>:<col>` (VS Code's
/// URL handler; Cursor, a VS Code fork, and Zed take the same form). The
/// order is `auto`'s (`link-editor`): Cursor, then VS Code, then Zed.
enum EditorApp {
  cursor('cursor'),
  vscode('vscode'),
  zed('zed');

  const EditorApp(this.scheme);

  /// The URL scheme the editor registers with the OS.
  final String scheme;
}

final RegExp _control = RegExp(r'[\u0000-\u001f\u007f]');
final RegExp _drive = RegExp(r'^[A-Za-z]:\\');

/// The URL that opens [path] (absolute, normalised) in [editor] at [line]
/// and [column] (1-based, as the terminal printed them). A column without a
/// line is dropped. Each path segment is percent-encoded, so a space,
/// Vietnamese, an emoji, `#`, `%`, `?` or a `:` in a name can never become
/// part of the scheme's syntax (`/a:b.txt` → `/a%3Ab.txt`, never line `b`).
/// On Windows `C:\a\b` is `/C:/a/b` (the drive colon kept, as the editors
/// expect).
///
/// Throws [ArgumentError] for a path that is not absolute (a UNC path is
/// not: a network share is never opened), or holds a control character —
/// the rule `UrlOpener.reveal` follows. The message never holds the path
/// (A10 §5).
String editorFileUrl(
  EditorApp editor,
  String path, {
  int? line,
  int? column,
  required bool windows,
}) {
  final absolute = windows ? _drive.hasMatch(path) : path.startsWith('/');
  if (!absolute || _control.hasMatch(path)) {
    throw ArgumentError.value('path', 'path', 'Not an absolute path');
  }
  final String encoded;
  if (windows) {
    final parts = path.split(r'\');
    // parts.first is the drive (`C:`): kept as it is.
    encoded =
        '/${parts.first}/${parts.skip(1).map(Uri.encodeComponent).join('/')}';
  } else {
    encoded = path.split('/').map(Uri.encodeComponent).join('/');
  }
  final at = line == null ? '' : ':$line${column == null ? '' : ':$column'}';
  return '${editor.scheme}://file$encoded$at';
}

/// Whether something exists at a path (a file or an app bundle folder).
typedef PathExists = Future<bool> Function(String path);

/// `link-editor = auto`: which editors are installed, found by where their
/// app lives — the bundle in `/Applications` or `~/Applications` on macOS,
/// the usual install folders on Windows (per-user under `%LOCALAPPDATA%`,
/// VS Code's system install under `%ProgramFiles%`). Elsewhere none is
/// known, so a file is revealed as before. [exists] is injectable: tests
/// never look at the real disk.
final class EditorDetector {
  EditorDetector({
    required this.windows,
    required this.env,
    required this.home,
    PathExists? exists,
    this.macos = true,
  }) : _exists = exists ?? _defaultExists;

  final bool windows;

  /// Read for `LOCALAPPDATA` and `ProgramFiles` on Windows.
  final Map<String, String> env;
  final String? home;

  /// Not Windows and not macOS (Linux): no editor is looked for.
  final bool macos;
  final PathExists _exists;

  /// A bundle is a folder, Code.exe a file: either counts.
  static Future<bool> _defaultExists(String path) async =>
      await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

  /// Where [editor] may be installed, in the order looked at. Only
  /// absolute paths: an unset variable gives no candidate.
  List<String> candidates(EditorApp editor) {
    if (windows) {
      final local = env['LOCALAPPDATA'];
      final programs = env['ProgramFiles'];
      final w = p.windows;
      final hasLocal = local != null && w.isAbsolute(local);
      final hasPrograms = programs != null && w.isAbsolute(programs);
      return switch (editor) {
        EditorApp.cursor => [
          if (hasLocal) w.join(local, 'Programs', 'cursor', 'Cursor.exe'),
        ],
        EditorApp.vscode => [
          if (hasLocal)
            w.join(local, 'Programs', 'Microsoft VS Code', 'Code.exe'),
          if (hasPrograms) w.join(programs, 'Microsoft VS Code', 'Code.exe'),
        ],
        EditorApp.zed => [
          if (hasLocal) w.join(local, 'Programs', 'Zed', 'Zed.exe'),
        ],
      };
    }
    if (!macos) return const [];
    final bundle = switch (editor) {
      EditorApp.cursor => 'Cursor.app',
      EditorApp.vscode => 'Visual Studio Code.app',
      EditorApp.zed => 'Zed.app',
    };
    final h = home;
    return [
      '/Applications/$bundle',
      if (h != null && h.startsWith('/'))
        p.posix.join(h, 'Applications', bundle),
    ];
  }

  /// The first of Cursor, VS Code, Zed that is installed, or null. A check
  /// that fails counts as "not installed".
  Future<EditorApp?> firstInstalled() async {
    for (final editor in EditorApp.values) {
      for (final path in candidates(editor)) {
        try {
          if (await _exists(path)) return editor;
        } on Object {
          // Unreadable: not there.
        }
      }
    }
    return null;
  }
}

/// The editor a file path opens in for [pref], or null to reveal it in
/// Finder / Explorer. A named editor is used whether or not it was found
/// (the OS says so when its URL has no handler); `auto` asks [detector].
Future<EditorApp?> editorFor(LinkEditor pref, EditorDetector detector) =>
    switch (pref) {
      LinkEditor.finder => Future.value(),
      LinkEditor.auto => detector.firstInstalled(),
      LinkEditor.vscode => Future.value(EditorApp.vscode),
      LinkEditor.cursor => Future.value(EditorApp.cursor),
      LinkEditor.zed => Future.value(EditorApp.zed),
    };
