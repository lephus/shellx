import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  late List<String> ran;
  Future<ProcessResult> run(String exe, List<String> args) async {
    ran.add(jsonEncode([exe, ...args]));
    return ProcessResult(0, 0, '', '');
  }

  setUp(() => ran = []);

  group('openWebLink (A10 D6)', () {
    test('http and https open; the arguments are the address alone', () async {
      final mac = SystemUrlOpener(isWindows: false, run: run);
      await mac.openWebLink(Uri.parse('https://example.com/a?b=1'));
      await mac.openWebLink(Uri.parse('http://localhost:3000/'));
      expect(ran, [
        '["/usr/bin/open","https://example.com/a?b=1"]',
        '["/usr/bin/open","http://localhost:3000/"]',
      ]);
      ran.clear();
      await SystemUrlOpener(
        isWindows: true,
        run: run,
      ).openWebLink(Uri.parse('https://example.com/'));
      expect(
        ran.single,
        '["rundll32","url.dll,FileProtocolHandler","https://example.com/"]',
      );
    });

    test('nothing else ever reaches a command', () async {
      final opener = SystemUrlOpener(isWindows: false, run: run);
      for (final bad in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'ssh://host',
        'mailto:a@b.c',
        'x-apple.systempreferences:com.apple.preference.security',
        '/usr/bin/open',
        'https://',
      ]) {
        await expectLater(
          opener.openWebLink(Uri.parse(bad)),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(ran, isEmpty);
    });

    test('open() is still https only (the app\'s own links)', () async {
      final opener = SystemUrlOpener(isWindows: false, run: run);
      await expectLater(
        opener.open(Uri.parse('http://example.com')),
        throwsArgumentError,
      );
    });
  });

  group('reveal (A10 D7)', () {
    test('macOS: always -R, so nothing is ever launched', () async {
      final mac = SystemUrlOpener(isWindows: false, run: run);
      await mac.reveal('/Users/me/a b.txt', isDirectory: false);
      await mac.reveal('/Users/me/dir', isDirectory: true);
      // A .app bundle is a directory: `open <dir>` would start the program.
      await mac.reveal('/Applications/Evil.app', isDirectory: true);
      expect(ran, [
        '["/usr/bin/open","-R","/Users/me/a b.txt"]',
        '["/usr/bin/open","-R","/Users/me/dir"]',
        '["/usr/bin/open","-R","/Applications/Evil.app"]',
      ]);
    });

    test('Windows: always explorer /select, as one argument', () async {
      final win = SystemUrlOpener(isWindows: true, run: run);
      await win.reveal(r'C:\Users\me\a b.txt', isDirectory: false);
      await win.reveal(r'C:\Users\me\Evil.exe', isDirectory: true);
      expect(ran, [
        r'["explorer.exe","/select,C:\\Users\\me\\a b.txt"]',
        r'["explorer.exe","/select,C:\\Users\\me\\Evil.exe"]',
      ]);
    });

    test(
      'a relative path, an option or a control character is refused',
      () async {
        final mac = SystemUrlOpener(isWindows: false, run: run);
        for (final bad in ['a.txt', '-a', '../x', '/tmp/a\nb', '']) {
          await expectLater(
            mac.reveal(bad, isDirectory: false),
            throwsArgumentError,
            reason: bad,
          );
        }
        await expectLater(
          SystemUrlOpener(
            isWindows: true,
            run: run,
          ).reveal('a.txt', isDirectory: false),
          throwsArgumentError,
        );
        await expectLater(
          SystemUrlOpener(
            isWindows: true,
            run: run,
          ).reveal(r'\\server\share\x.exe', isDirectory: false),
          throwsArgumentError,
          reason: 'UNC',
        );
        expect(ran, isEmpty);
      },
    );
  });
}
