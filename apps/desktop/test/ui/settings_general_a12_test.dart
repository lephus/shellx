import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../support/config_workspace.dart';
import '../support/fakes.dart';

const cmd = LogicalKeyboardKey.metaLeft;

Future<void> openGeneral(WidgetTester t) async {
  await t.sendKeyDownEvent(cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(cmd);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.general')));
  await t.pumpAndSettle();
}

Finder opt(String wire) => find.byKey(Key('setting.app-language.opt.$wire'));

bool selected(WidgetTester t, String wire) =>
    t.widget<ChoiceChip>(opt(wire)).selected;

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  group('language', () {
    testWidgets('three choices; the system one is selected at first', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsOneWidget);
      expect(selected(t, 'system'), isTrue);
      expect(selected(t, 'en'), isFalse);
      expect(selected(t, 'vi'), isFalse);
      // Nothing is said before something is chosen.
      expect(
        find.byKey(const Key('setting.app-language.restart')),
        findsNothing,
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('choosing Tiếng Việt stores [vi] and says when it applies', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.tap(opt('vi'));
      await t.pumpAndSettle();
      final store = w.container.read(settingsStoreProvider);
      expect(store.getStrings(SettingKeys.appLanguage), ['vi']);
      expect(selected(t, 'vi'), isTrue);
      expect(selected(t, 'system'), isFalse);
      expect(
        find.text('Takes effect after you restart ShellX.'),
        findsOneWidget,
      );
      // The running window does not change.
      expect(find.text('Language'), findsOneWidget);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('and back to the system default', (t) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.tap(opt('en'));
      await t.pumpAndSettle();
      await t.tap(opt('system'));
      await t.pumpAndSettle();
      final store = w.container.read(settingsStoreProvider);
      expect(store.getStrings(SettingKeys.appLanguage), ['system']);
      expect(selected(t, 'system'), isTrue);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('a stored value nobody knows reads as the system default', (
      t,
    ) async {
      final w = await pumpConfiguredWorkspace(t);
      (w.container.read(settingsStoreProvider) as InMemorySettingsStore)
          .strings[SettingKeys.appLanguage] = [
        'klingon',
      ];
      await openGeneral(t);
      expect(selected(t, 'system'), isTrue);
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('Vietnamese labels and note', (t) async {
      final w = await pumpConfiguredWorkspace(t, locale: const Locale('vi'));
      await openGeneral(t);
      expect(find.text('Ngôn ngữ'), findsOneWidget);
      expect(find.text('Theo hệ thống'), findsOneWidget);
      await t.tap(opt('en'));
      await t.pumpAndSettle();
      expect(
        find.text('Có hiệu lực sau khi bạn khởi động lại ShellX.'),
        findsOneWidget,
      );
      await disposeWorkspace(t, w.container);
    }, variant: mac);

    testWidgets('the row is found by search, in either language', (t) async {
      final w = await pumpConfiguredWorkspace(t);
      await openGeneral(t);
      await t.enterText(find.byType(TextField).first, 'ngon ngu');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('setting.app-language')), findsOneWidget);
      await disposeWorkspace(t, w.container);
    }, variant: mac);
  });

  group('update', () {
    late TestHarness h;

    Future<ProviderContainer> boot(
      WidgetTester t, {
      String appVersion = '1.0.0',
      Locale locale = const Locale('en'),
    }) async {
      h = TestHarness(
        settings: {'onboarding_done': true},
        appVersion: appVersion,
      );
      await h.seedSignedIn();
      final w = await pumpConfiguredWorkspace(t, locale: locale, harness: h);
      return w.container;
    }

    Future<void> check(WidgetTester t) async {
      await t.tap(find.byKey(const Key('settings.update.check')));
      await t.pumpAndSettle();
    }

    void newer({String version = '1.2.0'}) {
      h.relay.version = {
        ...h.relay.version,
        'latest_agent': {
          'version': version,
          'mac_url': 'https://download.shellx.pro/desktop/$version/a.dmg',
          'win_url': 'https://download.shellx.pro/desktop/$version/a.exe',
        },
      };
    }

    testWidgets('the version line and a button; nothing is said before', (
      t,
    ) async {
      final c = await boot(t);
      await openGeneral(t);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
      expect(find.byKey(const Key('settings.update.result')), findsNothing);
      expect(
        h.relay.requests.where((r) => r.url.path == '/v1/version'),
        hasLength(lessThanOrEqualTo(1)),
      );
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('up to date', (t) async {
      final c = await boot(t);
      await openGeneral(t);
      await check(t);
      expect(find.text('You’re up to date (1.0.0).'), findsOneWidget);
      expect(find.byKey(const Key('settings.update.download')), findsNothing);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('a new version: its number, and Download opens the page', (
      t,
    ) async {
      final c = await boot(t);
      newer();
      await openGeneral(t);
      await check(t);
      expect(find.text('Version 1.2.0 is available.'), findsOneWidget);
      expect(
        find.text(
          'This version is too old. Update to keep using phone access.',
        ),
        findsNothing,
      );
      await t.tap(find.byKey(const Key('settings.update.download')));
      await t.pump();
      expect(
        h.urlOpener.opened.single.toString(),
        'https://download.shellx.pro/desktop/1.2.0/a.dmg',
      );
      // Nothing was installed or announced outside the window.
      expect(h.notifier.shown, isEmpty);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('below min_agent: the required line too', (t) async {
      final c = await boot(t, appVersion: '0.9.0');
      await openGeneral(t);
      await check(t);
      expect(find.text('Version 1.0.0 is available.'), findsOneWidget);
      expect(
        find.text(
          'This version is too old. Update to keep using phone access.',
        ),
        findsOneWidget,
      );
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('offline: "Couldn’t check right now."', (t) async {
      final c = await boot(t);
      h.relay.offline = true;
      await openGeneral(t);
      await check(t);
      expect(find.text('Couldn’t check right now.'), findsOneWidget);
      expect(find.byKey(const Key('settings.update.download')), findsNothing);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('a download link that is not ShellX\'s is a failure', (
      t,
    ) async {
      final c = await boot(t);
      h.relay.version = {
        ...h.relay.version,
        'latest_agent': {
          'version': '1.2.0',
          'mac_url': 'https://evil.example/a.dmg',
          'win_url': 'https://evil.example/a.exe',
        },
      };
      await openGeneral(t);
      await check(t);
      expect(find.text('Couldn’t check right now.'), findsOneWidget);
      expect(find.byKey(const Key('settings.update.download')), findsNothing);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('a relay that never answers: "Checking…", then a failure', (
      t,
    ) async {
      final c = await boot(t);
      final never = Completer<void>();
      h.relay.holds['GET /v1/version'] = never.future;
      await openGeneral(t);
      await t.tap(find.byKey(const Key('settings.update.check')));
      await t.pump();
      expect(find.text('Checking…'), findsOneWidget);
      // The button is off meanwhile: no second request.
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const Key('settings.update.check')),
            )
            .onPressed,
        isNull,
      );
      await t.pump(const Duration(seconds: 11));
      expect(find.text('Couldn’t check right now.'), findsOneWidget);
      never.complete();
      await t.pumpAndSettle();
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('the answer is a live region', (t) async {
      final sem = t.ensureSemantics();
      final c = await boot(t);
      await openGeneral(t);
      await check(t);
      final node = t.getSemantics(
        find.byKey(const Key('settings.update.result')),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      sem.dispose();
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('Vietnamese', (t) async {
      final c = await boot(t, locale: const Locale('vi'));
      newer();
      await openGeneral(t);
      expect(find.text('Kiểm tra cập nhật'), findsOneWidget);
      await check(t);
      expect(find.text('Đã có bản 1.2.0.'), findsOneWidget);
      expect(find.text('Tải xuống'), findsOneWidget);
      await disposeWorkspace(t, c);
    }, variant: mac);

    testWidgets('the palette entry opens Settings and shows the answer', (
      t,
    ) async {
      final c = await boot(t);
      newer();
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyP);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'check for updates');
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.byType(SettingsOverlay), findsOneWidget);
      expect(find.text('Version 1.2.0 is available.'), findsOneWidget);
      await disposeWorkspace(t, c);
    }, variant: mac);
  });
}
