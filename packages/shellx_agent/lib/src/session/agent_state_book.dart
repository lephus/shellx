import 'package:shellx_core/shellx_core.dart';

/// The coding agent showing in a session, as closed-set wire names (A12
/// D22); null when none shows.
typedef AgentShown = ({String agent, String state});

/// Agent quick reply D1, §2: what each session's attached phone was last
/// told about its agent, so `agent.state` is sent once per change. Shared by
/// `SessionManager` and `DesktopSessionManager`; never holds the agent's
/// words.
final class AgentStateBook {
  final _told = <int, AgentShown>{};

  static const AgentShown _none = (agent: '', state: '');

  /// Records [agent]/[state] (both empty: none shows) for session [id].
  /// True when it differs from what was recorded last, i.e. when the phone
  /// should be told; "none" before anything was recorded is no change.
  bool change(int id, String agent, String state) {
    final next = (agent: agent, state: state);
    if ((_told[id] ?? _none) == next) return false;
    if (next == _none) {
      _told.remove(id);
    } else {
      _told[id] = next;
    }
    return true;
  }

  /// The `session.attached` answer for session [id] at stream [head], with
  /// the agent [current]ly showing (`agentOf`); what it carries counts as
  /// told, so the same state is not sent again right after.
  SessionAttached attached(int id, int head, AgentShown? current) {
    final shown = current == null || current.agent.isEmpty ? null : current;
    change(id, shown?.agent ?? '', shown?.state ?? '');
    return SessionAttached(
      id: id,
      seq: head,
      agent: shown?.agent,
      agentState: shown?.state,
    );
  }

  /// The session is gone.
  void forget(int id) => _told.remove(id);
}
