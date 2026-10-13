import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';

/// Agent quick reply §2: what phones are told of each pane's agent.
void main() {
  final t0 = DateTime.utc(2026, 10, 13, 9);
  AgentPane pane(AgentState state, {AgentKind agent = AgentKind.claude}) =>
      AgentPane(agent: agent, state: state, since: t0, lastEventAt: t0);

  test('agentWireOf gives wire names, null when nothing shows', () {
    expect(agentWireOf(null), isNull);
    expect(agentWireOf(pane(AgentState.unknown)), isNull);
    expect(agentWireOf(pane(AgentState.needsInput)), (
      agent: 'claude',
      state: 'needs_input',
    ));
    expect(agentWireOf(pane(AgentState.running, agent: AgentKind.opencode)), (
      agent: 'opencode',
      state: 'running',
    ));
  });

  test('agentWireChanges reports each pane whose shown agent changed', () {
    final calls = <(int, String, String)>[];
    agentWireChanges(
      {
        1: pane(AgentState.running),
        2: pane(AgentState.idle),
        3: pane(AgentState.done),
        4: pane(AgentState.unknown),
      },
      {
        1: pane(AgentState.needsInput),
        2: pane(AgentState.idle),
        4: pane(AgentState.unknown),
        5: pane(AgentState.running, agent: AgentKind.codex),
        6: pane(AgentState.unknown),
      },
      (id, agent, state) => calls.add((id, agent, state)),
    );
    expect(
      calls,
      unorderedEquals([
        (1, 'claude', 'needs_input'),
        (3, '', ''),
        (5, 'codex', 'running'),
      ]),
    );
  });

  test('a new agent in the same state is a change', () {
    final calls = <(int, String, String)>[];
    agentWireChanges(
      {1: pane(AgentState.running)},
      {1: pane(AgentState.running, agent: AgentKind.gemini)},
      (id, agent, state) => calls.add((id, agent, state)),
    );
    expect(calls, [(1, 'gemini', 'running')]);
  });
}
