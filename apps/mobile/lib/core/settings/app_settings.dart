import 'package:flutter/foundation.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

/// User preferences (spec §9.2 #5), as signals. Stored in the same secure store as the account
/// so the app has a single persistence mechanism.
@lazySingleton
class AppSettings {
  AppSettings(this._store);

  static const String fontSizeKey = 'settings_font_size';
  static const String biometricLockKey = 'settings_biometric_lock';
  static const String voiceLocaleKey = 'settings_voice_locale';
  static const double defaultFontSize = 14;
  static const double minFontSize = 8;
  static const double maxFontSize = 32;

  final KeyValueStore _store;
  final Signal<double> _fontSize = signal(defaultFontSize);

  /// Spec §5.6: the biometric lock is on by default.
  final Signal<bool> _biometricLock = signal(true);

  /// Voice spec V2: the language the composer listens in; null until the user picks one (the
  /// composer then follows the app language).
  final Signal<VoiceLocale?> _voiceLocale = signal(null);

  ReadonlySignal<double> get fontSize => _fontSize;
  ReadonlySignal<bool> get biometricLock => _biometricLock;
  ReadonlySignal<VoiceLocale?> get voiceLocale => _voiceLocale;

  static double clampFontSize(double value) => value.clamp(minFontSize, maxFontSize).toDouble();

  /// Runs before the first frame. A store that cannot be read keeps the defaults — the biometric
  /// lock on — so the app still starts, locked.
  @PostConstruct(preResolve: true)
  Future<void> load() async {
    final double? storedSize;
    final bool biometricLock;
    final String? voiceCode;
    try {
      storedSize = double.tryParse(await _store.read(fontSizeKey) ?? '');
      biometricLock = await _store.read(biometricLockKey) != 'false';
      voiceCode = await _store.read(voiceLocaleKey);
    } catch (error) {
      if (kDebugMode) debugPrint('AppSettings load error: ${error.runtimeType}');
      return;
    }
    batch(() {
      _fontSize.value = clampFontSize(storedSize ?? defaultFontSize);
      _biometricLock.value = biometricLock;
      _voiceLocale.value = VoiceLocale.values.where((l) => l.languageCode == voiceCode).firstOrNull;
    });
  }

  /// Shows [value] without storing it (the Settings slider while it moves).
  void previewFontSize(double value) => _fontSize.value = clampFontSize(value);

  Future<void> setFontSize(double value) async {
    _fontSize.value = clampFontSize(value);
    await _store.write(fontSizeKey, _fontSize.peek().toString());
  }

  /// Stored first: the setting (and the lock that reads it) only changes once it is saved, so a
  /// failed write leaves both as they were.
  Future<void> setBiometricLock(bool enabled) async {
    await _store.write(biometricLockKey, enabled.toString());
    _biometricLock.value = enabled;
  }

  Future<void> setVoiceLocale(VoiceLocale locale) async {
    _voiceLocale.value = locale;
    await _store.write(voiceLocaleKey, locale.languageCode);
  }
}
