import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../l10n/app_localizations.dart';
import '../platform/keep_awake.dart';
import '../platform/launch_at_login.dart';
import '../platform/notifier.dart';
import '../platform/settings_store.dart';
import '../platform/url_opener.dart';
import 'agent_runtime.dart';

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
    required this.runtimeFactory,
    required this.keepAwake,
    required this.launchAtLogin,
    required this.notifier,
    required this.urlOpener,
    required this.l10n,
    required this.appVersion,
    required this.platform,
    required this.deviceName,
    this.updateInterval = const Duration(hours: 24),
    this.quitApp,
    this.awaitPtyKills,
    this.ptyKillTimeout = const Duration(seconds: 3),
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
  final AgentRuntimeFactory runtimeFactory;
  final KeepAwake keepAwake;
  final LaunchAtLogin launchAtLogin;
  final SystemNotifier notifier;
  final UrlOpener urlOpener;
  final AppLocalizations l10n;

  /// `(await PackageInfo.fromPlatform()).version` (Task 11): the pubspec
  /// `version:` without the `+build` suffix. `evaluateUpdate` ignores
  /// anything that is not `x.y.z`, so a suffix would silently turn update
  /// checks off; debug builds assert the format.
  final String appVersion;
  final DevicePlatform platform;
  final String deviceName;
  final Duration updateInterval;

  /// Destroys the tray icon and the window, then exits the process.
  final Future<void> Function()? quitApp;

  /// Completes once every PTY process-tree kill started so far has settled.
  /// `main.dart` wires it to `FlutterPtyFactory.killsSettled()`
  /// (`Pty.kill()` itself gives nothing to wait for). Sign-out and quit wait
  /// for it, at most [ptyKillTimeout], after the sessions are closed, so
  /// the agent never exits halfway through a kill (a frozen survivor would
  /// stay stopped).
  final Future<void> Function()? awaitPtyKills;
  final Duration ptyKillTimeout;
}

final desktopServicesProvider = Provider<DesktopServices>(
  (ref) => throw StateError('desktopServicesProvider must be overridden'),
);

/// Wall clock for countdowns; overridden in widget tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
