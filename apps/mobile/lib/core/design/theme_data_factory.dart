import 'package:universal_back_gesture/universal_back_gesture.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

class ThemeDataFactory {
  static ThemeData create(Brightness brightness) {
    final appColors = brightness.appColors;
    // Material widgets (switches, sliders, text buttons) take the ShellX tokens, not the M3 seed.
    final colorScheme = ColorScheme.fromSeed(seedColor: appColors.primary, brightness: brightness).copyWith(
      primary: appColors.primary,
      onPrimary: appColors.onPrimary,
      primaryContainer: appColors.primarySoft,
      surface: appColors.surface,
      onSurface: appColors.primaryText,
      onSurfaceVariant: appColors.secondaryText,
      error: appColors.error,
      outline: appColors.border,
      outlineVariant: appColors.divider,
    );
    return ThemeData(
      colorScheme: colorScheme,
      primaryColor: appColors.primary,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: BackGesturePageTransitionsBuilder(
              parentTransitionBuilder: const CupertinoPageTransitionsBuilder(),
              config: BackGestureConfig(
                swipeTransitionRange: const GestureMeasurement.percentage(1.0),
                commitAnimationDuration: Duration(milliseconds: 100),
                commitAnimationCurve: Curves.easeOutQuart,
                animationProgressCompleteThreshold: 0.4,
              ),
            ),
        },
      ),
      iconTheme: IconThemeData(
        color: appColors.primary,
      ),
      brightness: brightness,
      useMaterial3: true,
      fontFamily: FontFamily.raleway,
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: appColors.primary,
      ),
      scaffoldBackgroundColor: appColors.background,
      dividerColor: appColors.divider,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: appColors.white,
        selectedItemColor: appColors.primaryText,
        unselectedItemColor: appColors.secondaryText,
        showUnselectedLabels: true,
        showSelectedLabels: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appColors.background,
        foregroundColor: appColors.primary,
        surfaceTintColor: appColors.background,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: appColors.primaryText,
          fontFamily: FontFamily.raleway,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFeatures: AppTypography.liningFigures,
        ),
        iconTheme: IconThemeData(
          color: appColors.primary,
        ),
      ),
    );
  }
}
