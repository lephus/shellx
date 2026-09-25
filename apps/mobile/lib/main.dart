import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter/material.dart';
import 'package:shellx_mobile/core/design/theme_data_factory.dart';
import 'features/app/splash_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
