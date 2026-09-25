import 'package:universal_back_gesture/universal_back_gesture.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

class ThemeDataFactory {
  static ThemeData create(Brightness brightness) {
    final appColors = brightness.appColors;
    return ThemeData(
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
        color: appColors.white,
      ),
      scaffoldBackgroundColor: appColors.background,
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: appColors.white,
        selectedItemColor: appColors.primaryText,
        unselectedItemColor: appColors.secondaryText,
        showUnselectedLabels: true,
        showSelectedLabels: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appColors.background,
        foregroundColor: appColors.white,
        shadowColor: Colors.black26,
        surfaceTintColor: appColors.background,
        centerTitle: true,
        elevation: 1,
        titleTextStyle: TextStyle(
          color: appColors.primary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(
          color: appColors.primaryText,
        ),
      ),
    );
  }
}
