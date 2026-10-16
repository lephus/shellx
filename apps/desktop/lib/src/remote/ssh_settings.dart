import 'package:shellx_agent/shellx_agent.dart';

import '../platform/settings_store.dart';

const int kRecentTargets = 10;

/// D11: the global switch ([globalOn], `AgentViewState.sshRemoteHook`: the
/// daemon owns it, A5b D13) and the per-server list (UI-owned).
bool sshHookFor(SettingsStore settings, String key, {required bool globalOn}) =>
    globalOn && !settings.getStrings(SettingKeys.sshPlainTargets).contains(key);

/// D6: stored keys that still parse canonically (the file is user-editable).
List<SshTarget> recentTargets(SettingsStore settings) => [
  for (final key in settings.getStrings(SettingKeys.sshRecentTargets))
    ?SshTarget.parseKey(key),
].take(kRecentTargets).toList();

/// Stores [SshTarget.key], never what the user typed.
Future<void> rememberTarget(SettingsStore settings, SshTarget target) {
  final next = [
    target.key,
    for (final t in recentTargets(settings))
      if (t.key != target.key) t.key,
  ].take(kRecentTargets).toList();
  return settings.setStrings(SettingKeys.sshRecentTargets, next);
}

Future<void> setPlainTarget(
  SettingsStore settings,
  String key, {
  required bool plain,
}) {
  final current = settings
      .getStrings(SettingKeys.sshPlainTargets)
      .where((k) => k != key);
  return settings.setStrings(SettingKeys.sshPlainTargets, [
    ...current,
    if (plain) key,
  ]);
}

Future<void> clearRecentTargets(SettingsStore settings) =>
    settings.setStrings(SettingKeys.sshRecentTargets, const []);
