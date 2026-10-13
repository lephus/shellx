import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart' show LinkEditor;
import 'package:shellx_desktop/src/platform/editor_links.dart';

/// An [EditorDetector] that sees only [installed] on disk.
EditorDetector detector(
  Set<String> installed, {
  bool windows = false,
  Map<String, String> env = const {},
  String? home = '/Users/me',
}) => EditorDetector(
  windows: windows,
  env: env,
  home: home,
  exists: (path) async => installed.contains(path),
);

void main() {
  group('editorFileUrl (⌘-click a path:line)', () {
    test('scheme, absolute path, then :line:col when known', () {
      expect(
        editorFileUrl(
          EditorApp.vscode,
          '/Users/me/src/app.dart',
          line: 12,
          column: 3,
          windows: false,
        ),
        'vscode://file/Users/me/src/app.dart:12:3',
      );
      expect(
        editorFileUrl(EditorApp.cursor, '/a/b.ts', line: 7, windows: false),
        'cursor://file/a/b.ts:7',
      );
      expect(
        editorFileUrl(EditorApp.zed, '/a/b.ts', windows: false),
        'zed://file/a/b.ts',
      );
    });

    test('a column without a line is dropped (":col" alone means a line)', () {
      expect(
        editorFileUrl(EditorApp.zed, '/a/b.ts', column: 4, windows: false),
        'zed://file/a/b.ts',
      );
    });

    test(
      'each segment is percent-encoded: spaces, Vietnamese, emoji, #, %, ?',
      () {
        expect(
          editorFileUrl(
            EditorApp.vscode,
            '/Users/me/Tài liệu/a b#1%?.md',
            line: 2,
            windows: false,
          ),
          'vscode://file/Users/me/T%C3%A0i%20li%E1%BB%87u/a%20b%231%25%3F.md:2',
        );
        expect(
          editorFileUrl(EditorApp.cursor, '/x/🚀.txt', windows: false),
          'cursor://file/x/%F0%9F%9A%80.txt',
        );
        // The path's own colon cannot be read as the line suffix.
        expect(
          editorFileUrl(
            EditorApp.vscode,
            '/x/a:b.txt',
            line: 1,
            windows: false,
          ),
          'vscode://file/x/a%3Ab.txt:1',
        );
      },
    );

    test('Windows: C:\\a\\b becomes /C:/a/b, the drive colon kept', () {
      expect(
        editorFileUrl(
          EditorApp.vscode,
          r'C:\Users\me\My Code\main.rs',
          line: 40,
          column: 9,
          windows: true,
        ),
        'vscode://file/C:/Users/me/My%20Code/main.rs:40:9',
      );
    });

    test(
      'a relative path, an option, UNC or a control character is refused',
      () {
        for (final bad in [
          'a.txt',
          '-a',
          '../x',
          '/tmp/a\nb',
          '',
          '/tmp/\x7f',
        ]) {
          expect(
            () => editorFileUrl(EditorApp.vscode, bad, windows: false),
            throwsArgumentError,
            reason: bad,
          );
        }
        for (final bad in ['a.txt', r'\\server\share\x.rs', '/unix/style']) {
          expect(
            () => editorFileUrl(EditorApp.vscode, bad, windows: true),
            throwsArgumentError,
            reason: bad,
          );
        }
      },
    );
  });

  group('EditorDetector', () {
    test('macOS: /Applications and ~/Applications bundles', () {
      final d = detector(const {});
      expect(d.candidates(EditorApp.cursor), [
        '/Applications/Cursor.app',
        '/Users/me/Applications/Cursor.app',
      ]);
      expect(d.candidates(EditorApp.vscode), [
        '/Applications/Visual Studio Code.app',
        '/Users/me/Applications/Visual Studio Code.app',
      ]);
      expect(d.candidates(EditorApp.zed), [
        '/Applications/Zed.app',
        '/Users/me/Applications/Zed.app',
      ]);
    });

    test('Windows: the usual install folders, from the environment', () {
      final d = detector(
        const {},
        windows: true,
        env: const {
          'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
          'ProgramFiles': r'C:\Program Files',
        },
      );
      expect(d.candidates(EditorApp.cursor), [
        r'C:\Users\me\AppData\Local\Programs\cursor\Cursor.exe',
      ]);
      expect(d.candidates(EditorApp.vscode), [
        r'C:\Users\me\AppData\Local\Programs\Microsoft VS Code\Code.exe',
        r'C:\Program Files\Microsoft VS Code\Code.exe',
      ]);
      expect(d.candidates(EditorApp.zed), [
        r'C:\Users\me\AppData\Local\Programs\Zed\Zed.exe',
      ]);
      // No environment: nothing to look at (never a relative path).
      expect(
        detector(const {}, windows: true).candidates(EditorApp.vscode),
        isEmpty,
      );
    });

    test('auto: Cursor first, then VS Code, then Zed', () async {
      expect(
        await detector({
          '/Applications/Zed.app',
          '/Applications/Visual Studio Code.app',
          '/Users/me/Applications/Cursor.app',
        }).firstInstalled(),
        EditorApp.cursor,
      );
      expect(
        await detector({
          '/Applications/Zed.app',
          '/Applications/Visual Studio Code.app',
        }).firstInstalled(),
        EditorApp.vscode,
      );
      expect(
        await detector({'/Applications/Zed.app'}).firstInstalled(),
        EditorApp.zed,
      );
      expect(await detector(const {}).firstInstalled(), isNull);
    });

    test('a check that throws counts as not installed', () async {
      final d = EditorDetector(
        windows: false,
        env: const {},
        home: '/Users/me',
        exists: (path) async => path == '/Applications/Zed.app'
            ? true
            : throw const FormatException('unreadable'),
      );
      expect(await d.firstInstalled(), EditorApp.zed);
    });
  });

  group('editorFor (link-editor)', () {
    test(
      'finder: never an editor; a named one: that one, installed or not',
      () async {
        final none = detector(const {});
        expect(await editorFor(LinkEditor.finder, none), isNull);
        expect(await editorFor(LinkEditor.vscode, none), EditorApp.vscode);
        expect(await editorFor(LinkEditor.cursor, none), EditorApp.cursor);
        expect(await editorFor(LinkEditor.zed, none), EditorApp.zed);
      },
    );

    test('auto: the first installed, or none (reveal as before)', () async {
      expect(await editorFor(LinkEditor.auto, detector(const {})), isNull);
      expect(
        await editorFor(
          LinkEditor.auto,
          detector({'/Applications/Visual Studio Code.app'}),
        ),
        EditorApp.vscode,
      );
    });
  });
}
