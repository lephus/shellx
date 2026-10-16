import '../platform/settings_store.dart';

/// Push spec N6/§7: the choices of "Thông báo khi lệnh chạy lâu xong", in
/// seconds; 0 is "Tắt".
const List<int> kNotifyThresholdChoices = [0, 10, 30, 60, 300];

/// 30 seconds until the user picks another.
const int kDefaultNotifyThresholdSeconds = 30;

/// The stored choice; the default when none (or an unknown value) is stored.
int notifyThresholdSeconds(SettingsStore settings) {
  final stored = settings.getInt(SettingKeys.notifyThreshold);
  return stored != null && kNotifyThresholdChoices.contains(stored)
      ? stored
      : kDefaultNotifyThresholdSeconds;
}

/// What the agent's command tracker reads when a command ends (null = off).
/// Reads [settings] on every call, so a change applies to the next command.
Duration? notifyThreshold(SettingsStore settings) {
  final seconds = notifyThresholdSeconds(settings);
  return seconds == 0 ? null : Duration(seconds: seconds);
}
