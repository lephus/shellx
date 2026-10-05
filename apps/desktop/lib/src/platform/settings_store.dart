import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret switches (spec §8.4: shared_preferences).
abstract final class SettingKeys {
  static const String remoteAccess = 'remote_access_enabled';
  static const String keepAwake = 'keep_awake_enabled';
  static const String launchAtStartup = 'launch_at_startup_enabled';
  static const String onboardingDone = 'onboarding_done';
  static const String terminalSharing = 'terminal_sharing_enabled';

  /// Startup files the last enable changed (a string list): disable cleans
  /// them even when PowerShell no longer reports a profile.
  static const String terminalSharingFiles = 'terminal_sharing_files';

  static const Set<String> all = {
    remoteAccess,
    keepAwake,
    launchAtStartup,
    onboardingDone,
    terminalSharing,
    terminalSharingFiles,
  };
}

abstract interface class SettingsStore {
  bool getBool(String key, {required bool defaultValue});
  Future<void> setBool(String key, bool value);
  List<String> getStrings(String key);
  Future<void> setStrings(String key, List<String> values);
}

final class SharedPrefsSettingsStore implements SettingsStore {
  SharedPrefsSettingsStore._(this._prefs);

  static Future<SharedPrefsSettingsStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: SettingKeys.all,
      ),
    );
    return SharedPrefsSettingsStore._(prefs);
  }

  final SharedPreferencesWithCache _prefs;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      _prefs.getBool(key) ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  List<String> getStrings(String key) => _prefs.getStringList(key) ?? const [];

  @override
  Future<void> setStrings(String key, List<String> values) =>
      _prefs.setStringList(key, values);
}

final class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, bool>? values]) : values = values ?? {};

  final Map<String, bool> values;

  /// Simulates a storage failure (a tray action that fails, Task 9).
  bool fail = false;

  @override
  bool getBool(String key, {required bool defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> setBool(String key, bool value) async {
    if (fail) throw StateError('settings write failed');
    values[key] = value;
  }

  final Map<String, List<String>> strings = {};

  @override
  List<String> getStrings(String key) => strings[key] ?? const [];

  @override
  Future<void> setStrings(String key, List<String> values) async {
    if (fail) throw StateError('settings write failed');
    strings[key] = List.of(values);
  }
}
