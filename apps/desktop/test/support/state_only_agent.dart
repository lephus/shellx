import 'package:shellx_desktop/src/agent/agent_controller_base.dart';
import 'package:shellx_desktop/src/agent/agent_state.dart';

/// An agent that is only a state: for tests of code that reads
/// `AgentViewState` (the ssh hook switch, the CLI switches) and never
/// calls a command. A command is a test bug and fails loudly.
final class StateOnlyAgent extends AgentControllerBase {
  StateOnlyAgent([this.initial = const AgentViewState()]);

  final AgentViewState initial;

  @override
  AgentViewState build() => initial;

  /// What the daemon's `agent.state` would bring.
  void set(AgentViewState Function(AgentViewState) change) =>
      state = change(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'StateOnlyAgent.${invocation.memberName} is not a test double',
  );
}
