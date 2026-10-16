import '../trust/trusted_store.dart';

/// Notifications for the desktop UI.
sealed class AgentEvent {
  const AgentEvent();
}

/// A phone completed pairing (show "Paired with `name`", close the QR window).
final class MobilePaired extends AgentEvent {
  const MobilePaired(this.device);
  final TrustedDevice device;
}

/// A phone opened a new terminal session (system notification).
final class SessionOpenedByMobile extends AgentEvent {
  const SessionOpenedByMobile({
    required this.mobileName,
    required this.sessionId,
  });
  final String mobileName;
  final int sessionId;
}

/// The number of open encrypted channels changed (tray icon state).
final class ActiveChannelsChanged extends AgentEvent {
  const ActiveChannelsChanged(this.count);
  final int count;
}

/// The relay closed the agent's connection with 4002 (token revoked: account
/// deleted, or password changed on another machine). The relay connection
/// does not reconnect; the desktop app decides what to clear (spec §5.2).
final class AgentRevoked extends AgentEvent {
  const AgentRevoked();
}
