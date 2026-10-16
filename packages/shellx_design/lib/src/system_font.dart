import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'type_scale.dart';

/// Why [ShellxSystemFont.load] registered nothing (V2-5a §6.3).
enum ShellxFontFallbackReason {
  /// Not iOS or macOS, switched off ([ShellxSystemFont.enabled], a
  /// platform's switch, or `FORCE_BUNDLED_MONO` in a debug build).
  unsupported,

  /// The native side failed, is missing, or answered something unreadable.
  channel,

  /// No answer within the time limit.
  timeout,

  /// The system font lacks a Vietnamese letter or combining mark.
  coverage,

  /// The engine refused the bytes.
  loader,
}

/// What [ShellxSystemFont.load] did: SF Mono registered, or the app runs on
/// the bundled JetBrains Mono for [reason].
@immutable
final class ShellxFontStatus {
  const ShellxFontStatus.loaded() : reason = null;

  const ShellxFontStatus.fallback(ShellxFontFallbackReason this.reason);

  /// Null when SF Mono was registered.
  final ShellxFontFallbackReason? reason;

  bool get isLoaded => reason == null;

  @override
  bool operator ==(Object other) =>
      other is ShellxFontStatus && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'ShellxFontStatus(…)';
}

/// Registers the font files under a family (production: [FontLoader]).
typedef ShellxFontRegistrar =
    Future<void> Function(String family, List<Uint8List> fonts);

/// V2-5a §6.3: the system's SF Mono on iOS and macOS. Its real name is
/// hidden (`.SF NS Mono`), so the runner rebuilds it in memory from its
/// tables (`SystemMonoFont.swift`) and Dart registers the bytes as
/// [ShellxFonts.systemMono] before `runApp`.
///
/// A32: the bytes stay in this process's memory. Nothing is written,
/// cached, sent or logged; Android and Windows never ask for the family.
abstract final class ShellxSystemFont {
  /// A32: one switch that stops reading the system font everywhere.
  static const bool enabled = true;

  /// The spike's per-platform result (plan Task 1): false sends that
  /// platform to JetBrains Mono.
  static const bool enabledOnMacOS = true;
  static const bool enabledOnIOS = true;

  /// The runner's channel (`SystemMonoFont.swift` in both apps).
  static const MethodChannel channel = MethodChannel(
    'pro.shellx.design/system_font',
  );

  /// §6.3: how long `main` waits for the runner.
  static const Duration timeout = Duration(milliseconds: 500);

  /// Debug builds only: `--dart-define=FORCE_BUNDLED_MONO=true` tries the
  /// fallback; release builds ignore it.
  static const bool _forceBundled = bool.fromEnvironment('FORCE_BUNDLED_MONO');

  /// Called once by each app's `main`, after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  /// Never throws.
  static Future<ShellxFontStatus> load({Duration timeout = timeout}) {
    final platform = defaultTargetPlatform;
    final on =
        enabled &&
        !(kDebugMode && _forceBundled) &&
        switch (platform) {
          TargetPlatform.macOS => enabledOnMacOS,
          TargetPlatform.iOS => enabledOnIOS,
          _ => false,
        };
    return loadWith(platform: platform, enabled: on, timeout: timeout);
  }

  /// [load] with its parts given (tests).
  @visibleForTesting
  static Future<ShellxFontStatus> loadWith({
    required TargetPlatform platform,
    required bool enabled,
    Duration timeout = timeout,
    MethodChannel channel = ShellxSystemFont.channel,
    ShellxFontRegistrar register = registerFonts,
    void Function(String message) log = _log,
  }) async {
    ShellxFontStatus fail(ShellxFontFallbackReason reason) {
      log('ShellX: SF Mono not loaded (${reason.name})');
      return ShellxFontStatus.fallback(reason);
    }

    if (!enabled || !ShellxFonts.isApple(platform)) {
      return const ShellxFontStatus.fallback(
        ShellxFontFallbackReason.unsupported,
      );
    }
    Object? answer;
    try {
      answer = await channel
          .invokeMethod<Object?>('monospaced')
          .timeout(timeout);
    } on TimeoutException {
      return fail(ShellxFontFallbackReason.timeout);
    } catch (_) {
      return fail(ShellxFontFallbackReason.channel);
    }
    if (answer is! Map) return fail(ShellxFontFallbackReason.channel);
    final regular = answer['regular'];
    final italic = answer['italic'];
    final missing = answer['missing'];
    if (regular is! Uint8List || regular.isEmpty || missing is! List) {
      return fail(ShellxFontFallbackReason.channel);
    }
    if (missing.isNotEmpty) return fail(ShellxFontFallbackReason.coverage);
    try {
      await register(ShellxFonts.systemMono, [
        regular,
        if (italic is Uint8List && italic.isNotEmpty) italic,
      ]);
    } catch (_) {
      return fail(ShellxFontFallbackReason.loader);
    }
    return const ShellxFontStatus.loaded();
  }

  /// Production [ShellxFontRegistrar]: one [FontLoader] for the family.
  static Future<void> registerFonts(String family, List<Uint8List> fonts) {
    final loader = FontLoader(family);
    for (final bytes in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    return loader.load();
  }

  static void _log(String message) => debugPrint(message);
}
