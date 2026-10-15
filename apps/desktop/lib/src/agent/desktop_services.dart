import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';
import '../platform/keep_awake.dart';
import '../platform/launch_at_login.dart';
import '../platform/notifier.dart';
import '../platform/settings_store.dart';
import '../platform/url_opener.dart';
import '../terminal_sharing/terminal_sharing_setup.dart';
import 'agent_runtime.dart';
import 'update_check.dart' show kUpdateCheckInterval;

final RegExp _releaseVersion = RegExp(r'^\d+\.\d+\.\d+$');

/// Every platform dependency of the controller, swapped for fakes in tests.
///
/// Create exactly one per process, around the process's one [secureStore]:
/// it owns the process's only [TrustedStore] ([trusted]), which the
/// controller and every AgentService it starts share (the store's mutation
/// lock is per instance).
final class DesktopServices {
  DesktopServices({
    required this.secureStore,
    required this.settings,
    required this.api,
    required this.createApi,
    required this.runtimeFactory,
    required this.sessions,
    required this.keepAwake,
    required this.launchAtLogin,
    required this.notifier,
    required this.urlOpener,
    required this.l10n,
    required this.appVersion,
    required this.platform,
    required this.deviceName,
    this.updateInterval = kUpdateCheckInterval,
    this.quitApp,
    this.deletePastedImages,
    this.stopRemoteRetries,
    this.shutdownRemote,
    this.shutdownTimeout = const Duration(seconds: 10),
    this.awaitPtyKills,
    this.ptyKillTimeout = const Duration(seconds: 3),
    this.terminalSharing,
    this.now = DateTime.now,
  }) : assert(
         _releaseVersion.hasMatch(appVersion),
         'appVersion must be PackageInfo.version: x.y.z, no +build suffix',
       ),
       trusted = TrustedStore(secureStore);

  /// The one shared store (DeviceIdentity and TrustedStore require that).
  final KeyValueStore secureStore;

  /// The trust list, over [secureStore]. Never create another one.
  final TrustedStore trusted;
  final SettingsStore settings;
  final ShellxApi api;

  /// A fresh [ShellxApi] for the same relay, for a call that must not share
  /// [api]'s token: sign-out's logout, which may still be running when a
  /// new session has set [api.token]. The caller closes it.
  final ShellxApi Function() createApi;
  final AgentRuntimeFactory runtimeFactory;

  /// The process's one session manager (A1 D7), built in `main.dart` with
  /// [SessionCore]. It outlives every runtime: signing out or turning
  /// remote access off never ends a shell; only Quit does.
  ///
  /// A window that attaches to the background service (A5b) has a
  /// `RemoteLocalSessions` here and no agent: only [AgentController] needs
  /// the [SessionManager] behind it ([manager]), and it never runs there.
  final LocalSessions sessions;

  /// The in-process [SessionManager] ([AgentController]'s way into the
  /// shells). Throws [StateError] where the shells live in the background
  /// service.
  SessionManager get manager => switch (sessions) {
    final SessionManager m => m,
    _ => throw StateError('the shells live in the background service'),
  };
  final KeepAwake keepAwake;
  final LaunchAtLogin launchAtLogin;
  final SystemNotifier notifier;
  final UrlOpener urlOpener;
  final AppLocalizations l10n;

  /// `(await PackageInfo.fromPlatform()).version` (Task 11): the pubspec
  /// `version:` without the `+build` suffix. `evaluateUpdate` ignores
  /// anything that is not `x.y.z`, so a suffix would silently turn update
  /// checks off; debug builds assert the format. Also what every ShellxApi
  /// and relay link of the app reports as `X-ShellX-Version` (contract §1).
  final String appVersion;
  final DevicePlatform platform;
  final String deviceName;

  /// Between two automatic update checks (contract §5: 6 h).
  final Duration updateInterval;

  /// Runs after `AgentController.shutdown()`: removes the tray icon and
  /// releases the single-instance lock (each bounded, so quitting cannot
  /// hang), then exits the process, which closes the window.
  final Future<void> Function()? quitApp;

  /// A10 D15: deletes the pasted images. Run only where the shells really
  /// end (an in-process quit, "Quit completely"): while the background
  /// service keeps them, an image path may still be waiting in a prompt
  /// (the 24 h sweep removes old ones).
  final Future<void> Function()? deletePastedImages;

  /// A8 D20/D40: the first step of Quit, before the command-line host stops
  /// and before the sessions close: the reconnector and the wake detector
  /// stop, so no retry opens a session while the app shuts down.
  final void Function()? stopRemoteRetries;

  /// A8 D40: runs after `AgentController.shutdown()` and before [quitApp]
  /// (bounded by the caller): stops the remote port probes, kills the
  /// forwards, tells the ssh masters to exit.
  final Future<void> Function()? shutdownRemote;

  /// Quit waits at most this long for `AgentController.shutdown()` before
  /// it runs [quitApp] anyway, so Quit always ends the process.
  final Duration shutdownTimeout;

  /// Completes once every PTY process-tree kill started so far has settled.
  /// `main.dart` wires it to `FlutterPtyFactory.killsSettled()`
  /// (`Pty.kill()` itself gives nothing to wait for). Quit waits for it, at
  /// most [ptyKillTimeout], after closing every session, so the agent never
  /// exits halfway through a kill (a frozen survivor would stay stopped).
  /// Sign-out kills nothing (A1 D7) but waits the same way for kills
  /// already in flight.
  final Future<void> Function()? awaitPtyKills;
  final Duration ptyKillTimeout;

  /// Terminal sharing's installer (spec §10); null where the switch is not
  /// offered (Windows without `SHELLX_EXPERIMENTAL=terminal-sharing`).
  final TerminalSharingSetup? terminalSharing;

  /// Wall clock (the attach-notification limit, update reminders).
  final DateTime Function() now;
}

final desktopServicesProvider = Provider<DesktopServices>(
  (ref) => throw StateError('desktopServicesProvider must be overridden'),
);

/// Wall clock for countdowns; overridden in widget tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
