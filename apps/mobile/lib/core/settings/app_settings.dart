import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';

/// User preferences (spec §9.2 #5), as signals. Stored in the same secure store as the account
/// so the app has a single persistence mechanism.
@lazySingleton
class AppSettings {
  AppSettings(this._store);

  static const String fontSizeKey = 'settings_font_size';
  static const String biometricLockKey = 'settings_biometric_lock';
  static const double defaultFontSize = 14;
  static const double minFontSize = 8;
  static const double maxFontSize = 32;

  final KeyValueStore _store;
  final Signal<double> _fontSize = signal(defaultFontSize);

  /// Spec §5.6: the biometric lock is on by default.
  final Signal<bool> _biometricLock = signal(true);

  ReadonlySignal<double> get fontSize => _fontSize;
  ReadonlySignal<bool> get biometricLock => _biometricLock;

  static double clampFontSize(double value) => value.clamp(minFontSize, maxFontSize).toDouble();

  @PostConstruct(preResolve: true)
  Future<void> load() async {
    final storedSize = double.tryParse(await _store.read(fontSizeKey) ?? '');
    final biometricLock = await _store.read(biometricLockKey) != 'false';
    batch(() {
      _fontSize.value = clampFontSize(storedSize ?? defaultFontSize);
      _biometricLock.value = biometricLock;
    });
  }

  Future<void> setFontSize(double value) async {
    _fontSize.value = clampFontSize(value);
    await _store.write(fontSizeKey, _fontSize.peek().toString());
  }

  Future<void> setBiometricLock(bool enabled) async {
    _biometricLock.value = enabled;
    await _store.write(biometricLockKey, enabled.toString());
  }
}
