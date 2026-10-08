import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/l10n/locale.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/tray/tray_action.dart';
import 'package:shellx_desktop/src/tray/tray_actions.dart';

import '../support/fakes.dart';

void main() {
  group('resolveAppLocale', () {
    const en = [Locale('en')];

    test('an override of en or vi wins over the system', () {
      expect(resolveAppLocale(en, override: 'vi'), kVietnamese);
      expect(resolveAppLocale(const [Locale('vi')], override: 'en'), kEnglish);
    });

    test('system, null, unknown or empty: the system rule', () {
      for (final o in ['system', null, 'fr', '', 'klingon', 'EN', 'vi ']) {
        expect(resolveAppLocale(en, override: o), kEnglish, reason: '$o');
        expect(
          resolveAppLocale(const [Locale('vi')], override: o),
          kVietnamese,
          reason: '$o',
        );
      }
    });

    test('the system rule is as before', () {
      expect(resolveAppLocale(const [Locale('de'), Locale('vi')]), kVietnamese);
      expect(resolveAppLocale(const [Locale('de')]), kEnglish);
      expect(resolveAppLocale(const []), kEnglish);
    });
  });

  group('the stored choice', () {
    String? override(List<String>? stored) {
      final s = InMemorySettingsStore();
      if (stored != null) s.strings[SettingKeys.appLanguage] = stored;
      return appLanguageOverride(s);
    }

    test('missing, empty, corrupt: system (no override)', () {
      expect(override(null), isNull);
      expect(override([]), isNull);
      expect(override(['']), isNull);
      expect(override(['klingon']), isNull);
      expect(override(['system']), isNull);
      expect(override(['vi ']), isNull);
    });

    test('en and vi are the override', () {
      expect(override(['vi']), 'vi');
      expect(override(['en']), 'en');
    });

    test('appLanguageChoice is always one of the three words', () {
      String choice(List<String>? v) {
        final s = InMemorySettingsStore();
        if (v != null) s.strings[SettingKeys.appLanguage] = v;
        return appLanguageChoice(s);
      }

      expect(choice(null), 'system');
      expect(choice(['vi']), 'vi');
      expect(choice(['en']), 'en');
      expect(choice(['zz']), 'system');
    });

    test('the key is the window\'s, not the service\'s (A5b D13)', () {
      expect(UiSettingKeys.all, contains(SettingKeys.appLanguage));
      expect(DaemonSettingKeys.all, isNot(contains(SettingKeys.appLanguage)));
      expect(SettingKeys.all, contains(SettingKeys.appLanguage));
      expect(UiSettingKeys.all, contains(SettingKeys.agentCommandApproved));
      expect(
        DaemonSettingKeys.all,
        isNot(contains(SettingKeys.agentCommandApproved)),
      );
    });
  });

  group('SetAppLanguage', () {
    late TestHarness h;
    late ProviderContainer c;

    setUp(() async {
      h = TestHarness();
      c = ProviderContainer.test(
        overrides: [desktopServicesProvider.overrideWithValue(h.services())],
      );
      await h.seedSignedIn();
      await c
          .read(agentControllerProvider.notifier)
          .bootstrap(watchForWake: false);
    });

    test('vi and en are stored as a one-element list', () async {
      await c.read(trayActionsProvider).handle(const SetAppLanguage('vi'));
      expect(h.settings.strings[SettingKeys.appLanguage], ['vi']);
      await c.read(trayActionsProvider).handle(const SetAppLanguage('en'));
      expect(h.settings.strings[SettingKeys.appLanguage], ['en']);
      await c.read(trayActionsProvider).handle(const SetAppLanguage('system'));
      expect(h.settings.strings[SettingKeys.appLanguage], ['system']);
    });

    test('anything else is stored as system', () async {
      for (final word in ['klingon', '', 'VI', 'vi\n', 'fr']) {
        await c.read(trayActionsProvider).handle(SetAppLanguage(word));
        expect(h.settings.strings[SettingKeys.appLanguage], [
          'system',
        ], reason: word);
      }
    });

    test('nothing happens to the running window', () async {
      await c.read(trayActionsProvider).handle(const SetAppLanguage('vi'));
      expect(h.notifier.shown, isEmpty);
    });
  });
}
