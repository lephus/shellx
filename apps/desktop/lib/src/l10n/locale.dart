import 'dart:ui';

import '../platform/settings_store.dart';

const Locale kVietnamese = Locale('vi');
const Locale kEnglish = Locale('en');

/// A12 D19: the words the stored choice can be.
const List<String> kAppLanguageChoices = ['system', 'en', 'vi'];

/// The language ShellX shows: [override] `en` or `vi` wins; `system`, null
/// or anything else is the first preferred system locale ShellX supports,
/// English otherwise.
Locale resolveAppLocale(List<Locale> preferred, {String? override}) {
  switch (override) {
    case 'en':
      return kEnglish;
    case 'vi':
      return kVietnamese;
  }
  for (final locale in preferred) {
    if (locale.languageCode == 'vi') return kVietnamese;
    if (locale.languageCode == 'en') return kEnglish;
  }
  return kEnglish;
}

/// The stored choice as one of [kAppLanguageChoices]; a missing, empty or
/// strange value is `system`.
String appLanguageChoice(SettingsStore settings) {
  final stored = settings.getStrings(SettingKeys.appLanguage);
  final word = stored.isEmpty ? null : stored.first;
  return kAppLanguageChoices.contains(word) ? word! : 'system';
}

/// What [resolveAppLocale] takes: `en` / `vi`, or null for the system.
String? appLanguageOverride(SettingsStore settings) {
  final choice = appLanguageChoice(settings);
  return choice == 'system' ? null : choice;
}
