import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_desktop/src/browser/browser_profile.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
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
      'a fresh per-run folder; earlier runs removed; a kept profile is removed when keeping is off (S2)',
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
        expect(Directory('${root()}/profile').existsSync(), isFalse);
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

  test('Windows without LOCALAPPDATA never falls back to Default (S9)', () {
    final p = BrowserProfile(isWindows: true, keepData: () => false);
    expect(p.prepare(), throwsA(isA<StateError>()));
    expect(Directory(r'C:\Users\Default').existsSync(), isFalse);
  });

  test(
    'turning keep-data off clears at once when the folder is idle (S2)',
    () async {
      await Directory('${root()}/profile').create(recursive: true);
      var keep = false;
      final p = BrowserProfile(
        isWindows: true,
        keepData: () => keep,
        localAppData: tmp.path,
      );
      await p.prepare(); // runs on a per-run folder
      expect(await p.clearNow(), isTrue);
      expect(Directory('${root()}/profile').existsSync(), isFalse);
      keep = true;
    },
  );

  test('the real app container wires the macOS clearer (S2)', () {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(browserProfileProvider).hasClearer, isTrue);
  }, skip: !Platform.isMacOS);

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
