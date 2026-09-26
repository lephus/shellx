import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/theme_data_factory.dart';
import 'package:shellx_mobile/features/app/font_licenses.dart';
import 'features/app/splash_page.dart';

// No cryptography_flutter: shellx_core pins the pure-Dart X25519 / ChaCha20-Poly1305 / BLAKE2s
// backends that pass the Noise vectors.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final themeMode = await AdaptiveTheme.getThemeMode() ?? AdaptiveThemeMode.system;
  runApp(
    AdaptiveTheme(
      light: ThemeDataFactory.create(Brightness.light),
      dark: ThemeDataFactory.create(Brightness.dark),
      initial: themeMode,
      builder: (lightTheme, darkTheme) {
        /// * [RootApp]
        return const SplashPage();
      },
    ),
  );
}
