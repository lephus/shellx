import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/editor_links.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  late List<String> ran;
  Future<ProcessResult> run(String exe, List<String> args) async {
    ran.add(jsonEncode([exe, ...args]));
    return ProcessResult(0, 0, '', '');
  }

  setUp(() => ran = []);

  group('openInEditor (⌘-click a path:line)', () {
    test('macOS: open with the editor URL alone', () async {
      final mac = SystemUrlOpener(isWindows: false, run: run);
      await mac.openInEditor(
        EditorApp.cursor,
        '/Users/me/a b.dart',
        line: 3,
        column: 5,
      );
      await mac.openInEditor(EditorApp.zed, '/Users/me/x.rs');
      expect(ran, [
        '["/usr/bin/open","cursor://file/Users/me/a%20b.dart:3:5"]',
        '["/usr/bin/open","zed://file/Users/me/x.rs"]',
      ]);
    });

    test('Windows: the URL protocol handler, drive path with /', () async {
      final win = SystemUrlOpener(isWindows: true, run: run);
      await win.openInEditor(EditorApp.vscode, r'C:\src\main.rs', line: 10);
      expect(
        ran.single,
        '["rundll32","url.dll,FileProtocolHandler",'
        '"vscode://file/C:/src/main.rs:10"]',
      );
    });

    test(
      'a relative path or a control character never runs a command',
      () async {
        final mac = SystemUrlOpener(isWindows: false, run: run);
        for (final bad in ['a.txt', '-a', '/tmp/a\nb', '']) {
          await expectLater(
            mac.openInEditor(EditorApp.vscode, bad),
            throwsArgumentError,
            reason: bad,
          );
        }
        await expectLater(
          SystemUrlOpener(
            isWindows: true,
            run: run,
          ).openInEditor(EditorApp.vscode, r'\\server\share\x.rs'),
          throwsArgumentError,
        );
        expect(ran, isEmpty);
      },
    );
  });
}
