import 'dart:ui';

import 'package:adaptive_theme/adaptive_theme.dart';

extension AdaptiveThemeModeX on AdaptiveThemeMode {
  Brightness get brightness {
    switch (this) {
      case AdaptiveThemeMode.light:
        return Brightness.light;
      case AdaptiveThemeMode.dark:
        return Brightness.dark;
      case AdaptiveThemeMode.system:
        return PlatformDispatcher.instance.platformBrightness;
    }
  }
}
