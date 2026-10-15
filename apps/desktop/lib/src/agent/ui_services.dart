import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';
import '../platform/keep_awake.dart';
import '../platform/launch_at_login.dart';
import '../platform/notifier.dart';
import '../platform/secure_key_value_store.dart';
import '../platform/settings_store.dart';
import '../platform/url_opener.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal_sharing/terminal_sharing_setup.dart';
import 'desktop_services.dart';

/// A5b: the [DesktopServices] of a window that attaches to the background
/// service. The shells and the agent are the service's: what only they use
/// (the relay, the keychain, keep-awake, launch at login) is inert here, and
/// no runtime is ever built. What the window uses is real: settings, text,
/// notifications, links, and the quit steps.
DesktopServices buildUiServices({
  required SettingsStore settings,
  required SystemNotifier notifier,
  required AppLocalizations l10n,
  required String appVersion,
  required Uri relayBase,
  required String deviceName,
  required TerminalSharingSetup? sharingSetup,
  required Future<void> Function() quitApp,
  Future<void> Function()? deletePastedImages,
  void Function()? stopRemoteRetries,
  Future<void> Function()? shutdownRemote,
  DevicePlatform? platform,
  required bool windows,
}) => DesktopServices(
  secureStore: SecureKeyValueStore(),
  settings: settings,
  // Contract §1: every request reports this build's x.y.z.
  api: ShellxApi(baseUri: relayBase, clientVersion: appVersion),
  createApi: () => ShellxApi(baseUri: relayBase, clientVersion: appVersion),
  runtimeFactory: (_) =>
      throw StateError('the agent runs in the background service'),
  sessions: const UnattachedSessions(),
  keepAwake: const _InertKeepAwake(),
  launchAtLogin: const _InertLaunchAtLogin(),
  notifier: notifier,
  urlOpener: SystemUrlOpener(),
  l10n: l10n,
  appVersion: appVersion,
  platform:
      platform ?? (windows ? DevicePlatform.windows : DevicePlatform.macos),
  deviceName: deviceName,
  terminalSharing: sharingSetup,
  stopRemoteRetries: stopRemoteRetries,
  shutdownRemote: shutdownRemote,
  quitApp: quitApp,
  deletePastedImages: deletePastedImages,
);

final class _InertKeepAwake implements KeepAwake {
  const _InertKeepAwake();
  @override
  Future<void> setEnabled(bool enabled) async {}
}

final class _InertLaunchAtLogin implements LaunchAtLogin {
  const _InertLaunchAtLogin();
  @override
  Future<bool> isEnabled() async => false;
  @override
  Future<void> setEnabled(bool enabled) async {}
}
