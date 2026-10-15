import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'agent_runtime.dart';
import 'notify_threshold.dart';
import 'update_check.dart';

enum AuthPhase { loading, signedOut, signedIn }

/// The terminal-sharing part of the tray (spec §7.6).
final class TerminalSharingView {
  const TerminalSharingView({
    this.available = false,
    this.enabled = false,
    this.busy = false,
    this.needsSetup = false,
    this.sessions = const <DesktopSessionSummary>[],
  });

  /// The switch is shown (macOS; Windows only with the experimental flag).
  final bool available;

  /// The switch (remembered across restarts).
  final bool enabled;

  /// Turning on or off is in progress.
  final bool busy;

  /// On, but a block or `shellx-term` is missing ("set up again").
  final bool needsSetup;

  /// Shared terminals; empty without a runtime.
  final List<DesktopSessionSummary> sessions;

  TerminalSharingView copyWith({
    bool? available,
    bool? enabled,
    bool? busy,
    bool? needsSetup,
    List<DesktopSessionSummary>? sessions,
  }) => TerminalSharingView(
    available: available ?? this.available,
    enabled: enabled ?? this.enabled,
    busy: busy ?? this.busy,
    needsSetup: needsSetup ?? this.needsSetup,
    sessions: sessions ?? this.sessions,
  );
}

const Object _unset = Object();

/// Everything the tray and the windows render. Immutable.
final class AgentViewState {
  const AgentViewState({
    this.phase = AuthPhase.loading,
    this.email,
    this.signedOutNotice = false,
    this.remoteAccess = true,
    this.keepAwake = true,
    this.launchAtStartup = true,
    this.onboardingDone = false,
    this.relay = RelayConnectionState.stopped,
    this.activeChannels = 0,
    this.sessions = const <SessionSummary>[],
    this.trusted = const <TrustedDevice>[],
    this.pairing,
    this.update,
    this.terminalSharing = const TerminalSharingView(),
    this.notifyThresholdSeconds = kDefaultNotifyThresholdSeconds,
    this.desktopNotifications = true,
    this.desktopNotificationsOnlyUnfocused = true,
    this.cliControlEnabled = true,
    this.cliAllowExternal = false,
    this.sshRemoteHook = true,
  });

  final AuthPhase phase;
  final String? email;

  /// True after a 4002 close signed us out; the login window explains why.
  final bool signedOutNotice;
  final bool remoteAccess;
  final bool keepAwake;
  final bool launchAtStartup;
  final bool onboardingDone;

  /// `stopped` whenever there is no runtime (signed out, remote access off,
  /// or [updateRequired]).
  final RelayConnectionState relay;
  final int activeChannels;
  final List<SessionSummary> sessions;
  final List<TrustedDevice> trusted;
  final PairingView? pairing;
  final UpdateNotice? update;
  final TerminalSharingView terminalSharing;

  /// "Thông báo khi lệnh chạy lâu xong" (push spec §7): one of
  /// [kNotifyThresholdChoices]; 0 = off.
  final int notifyThresholdSeconds;

  /// A4 D20: "Thông báo trên máy tính" and "Chỉ khi cửa sổ không ở phía
  /// trước" (tray). Both work signed out (N1).
  final bool desktopNotifications;
  final bool desktopNotificationsOnlyUnfocused;

  /// A5b D13 (Task 6 ruling): daemon-owned, toggled through the agent, read
  /// from here by the tray. A7 D26 "Cho phép điều khiển ShellX bằng dòng
  /// lệnh" (default on).
  final bool cliControlEnabled;

  /// A7 amendment "Cho phép terminal khác" (default off).
  final bool cliAllowExternal;

  /// A8 D11 "Cài hook ShellX trên máy chủ" (default on).
  final bool sshRemoteHook;

  bool get signedIn => phase == AuthPhase.signedIn;

  /// Force update (contract §5): this build is below `min_agent`. Remote
  /// access stays stopped, the windows show only "Update required" and the
  /// tray only the download and Quit, until a later check says otherwise.
  bool get updateRequired => update?.required ?? false;

  AgentViewState copyWith({
    AuthPhase? phase,
    Object? email = _unset,
    bool? signedOutNotice,
    bool? remoteAccess,
    bool? keepAwake,
    bool? launchAtStartup,
    bool? onboardingDone,
    RelayConnectionState? relay,
    int? activeChannels,
    List<SessionSummary>? sessions,
    List<TrustedDevice>? trusted,
    Object? pairing = _unset,
    Object? update = _unset,
    TerminalSharingView? terminalSharing,
    int? notifyThresholdSeconds,
    bool? desktopNotifications,
    bool? desktopNotificationsOnlyUnfocused,
    bool? cliControlEnabled,
    bool? cliAllowExternal,
    bool? sshRemoteHook,
  }) {
    return AgentViewState(
      phase: phase ?? this.phase,
      email: identical(email, _unset) ? this.email : email as String?,
      signedOutNotice: signedOutNotice ?? this.signedOutNotice,
      remoteAccess: remoteAccess ?? this.remoteAccess,
      keepAwake: keepAwake ?? this.keepAwake,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      relay: relay ?? this.relay,
      activeChannels: activeChannels ?? this.activeChannels,
      sessions: sessions ?? this.sessions,
      trusted: trusted ?? this.trusted,
      pairing: identical(pairing, _unset)
          ? this.pairing
          : pairing as PairingView?,
      update: identical(update, _unset) ? this.update : update as UpdateNotice?,
      terminalSharing: terminalSharing ?? this.terminalSharing,
      notifyThresholdSeconds:
          notifyThresholdSeconds ?? this.notifyThresholdSeconds,
      desktopNotifications: desktopNotifications ?? this.desktopNotifications,
      desktopNotificationsOnlyUnfocused:
          desktopNotificationsOnlyUnfocused ??
          this.desktopNotificationsOnlyUnfocused,
      cliControlEnabled: cliControlEnabled ?? this.cliControlEnabled,
      cliAllowExternal: cliAllowExternal ?? this.cliAllowExternal,
      sshRemoteHook: sshRemoteHook ?? this.sshRemoteHook,
    );
  }
}
