import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'agent_runtime.dart';
import 'update_check.dart';

enum AuthPhase { loading, signedOut, signedIn }

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
  });

  final AuthPhase phase;
  final String? email;

  /// True after a 4002 close signed us out; the login window explains why.
  final bool signedOutNotice;
  final bool remoteAccess;
  final bool keepAwake;
  final bool launchAtStartup;
  final bool onboardingDone;

  /// `stopped` whenever there is no runtime (signed out or remote access off).
  final RelayConnectionState relay;
  final int activeChannels;
  final List<SessionSummary> sessions;
  final List<TrustedDevice> trusted;
  final PairingView? pairing;
  final UpdateNotice? update;

  bool get signedIn => phase == AuthPhase.signedIn;

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
    );
  }
}
