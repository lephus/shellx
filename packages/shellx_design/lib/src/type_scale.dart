import 'package:flutter/foundation.dart';

/// V2-5a A31, §6.1: the font families by platform. SF Mono is the system's
/// own on iOS and macOS, loaded at run time ([ShellxSystemFont]) and never
/// bundled; JetBrains Mono ships in both apps and is used everywhere else,
/// and on iOS and macOS when SF Mono did not load.
abstract final class ShellxFonts {
  /// The family [ShellxSystemFont] registers the system's SF Mono under.
  static const String systemMono = 'SF Mono';

  /// Bundled by both apps (`assets/fonts/JetBrainsMono-*.ttf`).
  static const String bundledMono = 'JetBrainsMono';

  /// The desktop's Light cut as its own family (the terminal default).
  static const String bundledMonoLight = 'JetBrainsMonoLight';

  /// iOS and macOS: the platforms whose system font ShellX may display.
  static bool isApple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// The UI family of [platform]. A32: never "SF Mono" off Apple platforms,
  /// not even when the user installed it there.
  static String uiFamily(TargetPlatform platform) =>
      isApple(platform) ? systemMono : bundledMono;

  /// What the engine falls back to when [uiFamily] is not registered.
  static List<String> uiFallback(TargetPlatform platform) =>
      isApple(platform) ? const [bundledMono] : const [];
}
