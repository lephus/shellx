import 'term_messages.dart';

/// Unsent bytes an agent → `shellx-term` link may hold before it closes
/// itself (spec §7.8): a terminal that stops reading reconnects and resyncs
/// from its snapshot instead of growing the agent's memory.
const int kTermMaxQueuedBytes = 1024 * 1024;

/// One authenticated `shellx-term` connection (spec §6.4).
abstract interface class TermLink {
  TermInfo get info;

  /// `snapshot`, `out`, `size`, `local` and `exit`, in arrival order;
  /// unknown types are dropped. Single-subscription, buffered until
  /// listened to, done when the connection ends for any reason.
  Stream<TermToAgent> get messages;

  /// Never blocks. Ignored once closed.
  void send(AgentToTerm message);

  /// Ends sharing for this window. The terminal itself keeps running and
  /// reconnects on its own schedule (spec §6.5).
  void close();
}
