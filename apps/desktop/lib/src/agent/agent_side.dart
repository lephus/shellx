import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';
import '../cli/cli_install.dart';
import '../mux/mux_paths.dart';
import '../mux/windows_pipe_transport.dart';
import '../platform/keep_awake.dart';
import '../platform/launch_at_login.dart';
import '../platform/notifier.dart';
import '../platform/pty/flutter_pty_factory.dart';
import '../platform/secure_key_value_store.dart';
import '../platform/settings_store.dart';
import '../platform/url_opener.dart';
import '../remote/remote_shutdown.dart';
import '../terminal_sharing/attach_throttle.dart';
import '../terminal_sharing/powershell.dart';
import '../terminal_sharing/sharing_paths.dart';
import '../terminal_sharing/terminal_sharing_setup.dart';
import 'agent_runtime.dart';
import 'desktop_services.dart';
import 'notify_threshold.dart';
import 'session_core.dart';

/// What the process that owns the shells and the agent builds (A5b D3): the
/// one [SessionCore] and the one [DesktopServices] around it.
typedef AgentSide = ({SessionCore core, DesktopServices services});

/// Builds [SessionCore] and [DesktopServices] from the platform pieces
/// [caller] made. [cliSocket] and [cliToken] are the running command-line
/// host's address and this launch's token: only then do they go into the
/// shells' environment (D8, D29); an address or token inherited from
/// another ShellX never does.
AgentSide buildAgentSide({
  required Map<String, String> environment,
  required String home,
  required String supportDirectory,
  required SettingsStore settings,
  required SystemNotifier notifier,
  required FlutterPtyFactory ptyFactory,
  required AppLocalizations l10n,
  required String appVersion,
  required Uri relayBase,
  required TerminalSharingSetup? sharingSetup,
  required String deviceName,
  required RemoteTools remoteTools,
  required Future<void> Function() quitApp,
  Future<void> Function()? deletePastedImages,
  CliPaths? cliPaths,
  String? cliSocket,
  String? cliToken,
  void Function()? stopRemoteRetries,
}) {
  // Push spec §7: the threshold is read from the settings whenever a command
  // ends, so the tray choice applies at once; titles start with the name the
  // relay knows this computer by.
  final pushNotifications = PushNotificationsSetup(
    threshold: () => notifyThreshold(settings),
    machineName: () => deviceName,
    locale: () => Platform.localeName,
    hooksDirectory: '$supportDirectory${Platform.pathSeparator}hooks',
  );
  // The app's one ShellxApi: the controller sets its token at sign-in.
  // Contract §1: every request reports this build's x.y.z.
  final api = ShellxApi(baseUri: relayBase, clientVersion: appVersion);
  // A1 D7: the process's one SessionManager. It outlives every runtime, so
  // signing out or losing the relay never ends a shell; Quit does.
  final core = SessionCore(
    ptyFactory: ptyFactory,
    shellResolver: PlatformShellResolver(
      operatingSystem: Platform.operatingSystem,
      environment: environment,
    ),
    homeDirectory: home,
    // Only the shells' environment gains the command line (not the shell
    // resolver's, nor the paths derived from `environment` above).
    baseEnvironment: cliPaths == null
        ? (Map.of(environment)
            ..remove('SHELLX_SOCKET')
            ..remove('SHELLX_CLI_TOKEN'))
        : cliSessionEnvironment(
            environment,
            cliDir: cliPaths.dir,
            socket: cliSocket,
            token: cliSocket == null ? null : cliToken,
            windows: Platform.isWindows,
          ),
    api: api,
    notifications: pushNotifications,
    gitHeads: GitHeadReader(),
    portProbe: Platform.isWindows ? WindowsPortProbe() : MacPortProbe(),
    remoteTools: remoteTools,
  );

  // The process's one SecureKeyValueStore; DesktopServices builds the one
  // TrustedStore over it.
  final services = DesktopServices(
    secureStore: SecureKeyValueStore(),
    settings: settings,
    api: api,
    createApi: () => ShellxApi(baseUri: relayBase, clientVersion: appVersion),
    runtimeFactory: (params) => CoreAgentRuntime(
      params,
      core: core,
      relayBaseUri: relayBase,
      appVersion: appVersion,
      termEndpointPath: sharingSetup == null
          ? null
          : termEndpointPath(
              environment: environment,
              windows: Platform.isWindows,
            ),
    ),
    sessions: core.sessions,
    keepAwake: Platform.isWindows ? WindowsKeepAwake() : CaffeinateKeepAwake(),
    launchAtLogin: PackageLaunchAtLogin(),
    notifier: notifier,
    urlOpener: SystemUrlOpener(),
    l10n: l10n,
    appVersion: appVersion,
    platform: Platform.isWindows
        ? DevicePlatform.windows
        : DevicePlatform.macos,
    deviceName: deviceName,
    // Sign-out and quit wait (at most 3 s) for PTY tree kills in flight.
    awaitPtyKills: ptyFactory.killsSettled,
    terminalSharing: sharingSetup,
    // A8 D40: after the clean flush, the CLI host stop and the sessions'
    // close (the tray's Quit), before quitApp.
    // D20: the first step of Quit: no retry may start from here on.
    stopRemoteRetries: stopRemoteRetries,
    shutdownRemote: () {
      return shutdownRemote(
        remoteTools,
        disposeWatcher: core.sessions.disposeRemotePorts,
      );
    },
    quitApp: quitApp,
    deletePastedImages: deletePastedImages,
  );
  return (core: core, services: services);
}

/// A7: what the command line needs before the first shell starts.
typedef CliSetup = ({MuxPaths mux, CliPaths paths, String token});

/// Null when the environment lacks what the paths need.
CliSetup? cliSetup(Map<String, String> environment) {
  try {
    final windows = Platform.isWindows;
    final paths = CliPaths.forPlatform(
      windows: windows,
      environment: environment,
      executable: Platform.resolvedExecutable,
    );
    if (paths == null) return null;
    final mux = muxPathsFor(environment);
    return (mux: mux, paths: paths, token: generateCliToken());
  } catch (error) {
    debugPrint('ShellX: no command line: ${error.runtimeType}');
    return null;
  }
}

/// Where the mux host's files and address are (A5b D5). Throws
/// [StateError] without `HOME` / `LOCALAPPDATA`.
MuxPaths muxPathsFor(Map<String, String> environment) {
  final windows = Platform.isWindows;
  return MuxPaths(
    muxDirectory: muxDirectoryPath(windows: windows, environment: environment),
    tmpDirectory: environment['TMPDIR'] ?? '/tmp',
    uid: windows ? 0 : _uid(),
    windows: windows,
    pipeName: windows ? pipeNameForUser(currentUserSid()) : null,
  );
}

/// macOS: the user id for the socket's TMPDIR fallback name.
int _uid() {
  final r = Process.runSync('/usr/bin/id', ['-u']);
  final uid = r.exitCode == 0 ? int.tryParse('${r.stdout}'.trim()) : null;
  if (uid == null) throw StateError('id -u failed');
  return uid;
}

/// Spec §7.6, §12: the switch is offered on macOS, and on Windows only with
/// `SHELLX_EXPERIMENTAL=terminal-sharing`. Null otherwise (or without the
/// environment variables the paths need).
TerminalSharingSetup? terminalSharingSetupFor(
  Map<String, String> environment, {
  required bool storedEnabled,
}) {
  final available = terminalSharingAvailable(
    macos: Platform.isMacOS,
    windows: Platform.isWindows,
    environment: environment,
    storedEnabled: storedEnabled,
  );
  if (!available) return null;
  return anyTerminalSharingSetup(environment);
}

/// Regardless of the experimental flag (the uninstaller must always clean
/// up).
TerminalSharingSetup? anyTerminalSharingSetup(Map<String, String> environment) {
  final paths = SharingPaths.forPlatform(
    windows: Platform.isWindows,
    environment: environment,
    executable: Platform.resolvedExecutable,
  );
  if (paths == null) return null;
  return TerminalSharingSetup(
    paths: paths,
    powerShell: Platform.isWindows
        ? PowerShellProbe(environment: environment)
        : null,
  );
}
