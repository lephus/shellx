import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../terminal/agent_status.dart';
import '../terminal/agent_status_notifier.dart';
import 'cli_fields.dart';

/// A12 D4: `ui.agent.event`, from the hooks of an agent running in a pane.
///
/// The sender is a process the user does not control: every field is
/// checked again here. A pane this window does not have (it ended on the
/// way) is not an error, and nothing of the request is echoed or logged.
final class AgentCommands {
  AgentCommands(this._ref);

  final Ref _ref;

  Future<Map<String, Object?>> event(MuxMessage r) async {
    final now = _ref.read(agentStatusClockProvider)();
    final e = decodeAgentEvent(r.fields, now: now);
    if (e == null) throw badRequest('not an agent event');
    _ref.read(agentStatusProvider.notifier).ingest(e);
    return const {};
  }
}
