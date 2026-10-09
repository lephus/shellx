import 'dart:io';
import 'dart:math';

import 'package:shellx_desktop/src/browser/browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeClearer implements WebsiteDataClearer {
  int clears = 0;
  @override
  Future<void> clearWebsiteData() async => clears++;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('a6profile'));
  tearDown(() => tmp.delete(recursive: true));

  String root() => '${tmp.path}/ShellX/webview';

  group('Windows', () {
    test(
      'a fresh per-run folder; earlier runs removed; kept profile untouched',
      () async {
        await Directory('${root()}/s-old1').create(recursive: true);
        await Directory('${root()}/profile').create(recursive: true);
        final p = BrowserProfile(
          isWindows: true,
          keepData: () => false,
          localAppData: tmp.path,
          random: Random(1),
        );
        await p.prepare();
        expect(p.userDataPath, startsWith('${root()}/s-'));
        expect(p.userDataPath!.split('/').last, hasLength(18)); // s- + 16 hex
        expect(Directory('${root()}/s-old1').existsSync(), isFalse);
        expect(Directory('${root()}/profile').existsSync(), isTrue);
        expect(Directory(p.userDataPath!).existsSync(), isTrue);
      },
    );

    test('keep data → the profile folder', () async {
      final p = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await p.prepare();
      expect(p.userDataPath, '${root()}/profile');
    });

    test('clearing the kept profile in use waits for the next start', () async {
      final p = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await p.prepare();
      await File('${root()}/profile/Cookies').writeAsString('x');
      expect(await p.clearNow(), isFalse);
      final next = BrowserProfile(
        isWindows: true,
        keepData: () => true,
        localAppData: tmp.path,
      );
      await next.prepare();
      expect(File('${root()}/profile/Cookies').existsSync(), isFalse);
      expect(File('${root()}/clear-profile').existsSync(), isFalse);
    });
  });

  group('macOS', () {
    test('clears at start and quit unless kept', () async {
      final c = FakeClearer();
      var keep = false;
      final p = BrowserProfile(
        isWindows: false,
        keepData: () => keep,
        clearer: c,
      );
      await p.prepare();
      await p.onQuit();
      expect(c.clears, 2);
      keep = true;
      await p.prepare();
      await p.onQuit();
      expect(c.clears, 2);
      expect(await p.clearNow(), isTrue);
      expect(c.clears, 3);
    });
  });
}
