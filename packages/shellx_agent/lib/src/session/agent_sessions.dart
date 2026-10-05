import 'package:shellx_core/shellx_core.dart';

/// An application message the agent must deliver to one phone.
final class OutboundMessage {
  const OutboundMessage(this.mobileId, this.message);
  final String mobileId;
  final AppMessage message;
}

/// Emitted when a phone opens a new session (desktop notification).
final class SessionOpenedEvent {
  const SessionOpenedEvent(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

/// What [AgentService] needs from the sessions: phone messages in,
/// messages to phones out, and the channel lifecycle. Implemented by
/// `SessionManager` (shell sessions only) and `SessionRouter` (shell and
/// desktop sessions).
abstract interface class AgentSessions {
  /// Messages to deliver, in order (a synchronous broadcast stream).
  Stream<OutboundMessage> get outbound;

  Stream<SessionOpenedEvent> get opened;

  Future<void> handle(String mobileId, AppMessage message);

  /// The channel to [mobileId] is gone.
  void mobileDisconnected(String mobileId);

  /// [mobileId] was revoked: its shell sessions are killed; desktop
  /// terminals only lose the phone (spec §7.2).
  void closeSessionsAttachedTo(String mobileId);
}
