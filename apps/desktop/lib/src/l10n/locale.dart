import 'dart:ui';

const Locale kVietnamese = Locale('vi');
const Locale kEnglish = Locale('en');

/// The first preferred system locale ShellX supports; English otherwise.
Locale resolveAppLocale(List<Locale> preferred) {
  for (final locale in preferred) {
    if (locale.languageCode == 'vi') return kVietnamese;
    if (locale.languageCode == 'en') return kEnglish;
  }
  return kEnglish;
}
