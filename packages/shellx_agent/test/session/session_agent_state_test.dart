import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

/// Agent quick reply D1, §2: `agent.state` goes to the phone attached to the
/// session, once per change; `session.attached` carries the current state.
void main() {
  Future<int> attachedSession(SessionRig rig) async {
    final id = await rig.open(phone);
    rig.clear();
    return id;
  }

  test('a change goes to the attached phone as agent.state', () async {
    final rig = SessionRig();
    final id = await attachedSession(rig);

    rig.manager.publishAgentState(id, 'claude', 'needs_input');

    expect(rig.to(phone), [
      AgentStateMessage(id: id, agent: 'claude', state: 'needs_input'),
    ]);
  });

  test('the same state is not sent twice; a new one is', () async {
    final rig = SessionRig();
    final id = await attachedSession(rig);

    rig.manager
      ..publishAgentState(id, 'claude', 'running')
      ..publishAgentState(id, 'claude', 'running')
      ..publishAgentState(id, 'claude', 'needs_input')
      ..publishAgentState(id, '', '');

    expect(rig.to(phone), [
      AgentStateMessage(id: id, agent: 'claude', state: 'running'),
      AgentStateMessage(id: id, agent: 'claude', state: 'needs_input'),
      AgentStateMessage(id: id, agent: '', state: ''),
    ]);
  });

  test('"none" before anything was shown sends nothing', () async {
    final rig = SessionRig();
    final id = await attachedSession(rig);

    rig.manager.publishAgentState(id, '', '');

    expect(rig.to(phone), isEmpty);
  });

  test('only the phone attached to that session hears it', () async {
    final rig = SessionRig();
    final mine = await rig.open(phone);
    await rig.open(tablet);
    rig.clear();

    rig.manager.publishAgentState(mine, 'codex', 'running');

    expect(rig.to(phone), hasLength(1));
    expect(rig.to(tablet), isEmpty);
  });

  test('a session without a phone sends nothing; the attach brings the state '
      'and it is not repeated after', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    rig.clear();
    rig.manager.agentOf = (s) =>
        s == id ? (agent: 'claude', state: 'needs_input') : null;

    rig.manager.publishAgentState(id, 'claude', 'needs_input');
    expect(rig.sent, isEmpty);

    await rig.manager.handle(
      phone,
      SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
    );
    final attached = rig.to(phone).whereType<SessionAttached>().single;
    expect((attached.agent, attached.agentState), ('claude', 'needs_input'));

    rig.clear();
    rig.manager.publishAgentState(id, 'claude', 'needs_input');
    expect(rig.sent, isEmpty);
  });

  test('session.attached carries no agent fields when none shows', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    rig.clear();
    rig.manager.agentOf = (_) => null;

    await rig.manager.handle(
      phone,
      SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
    );

    final map = rig.to(phone).whereType<SessionAttached>().single.toMap();
    expect(map.containsKey('agent'), isFalse);
    expect(map.containsKey('agent_state'), isFalse);
  });

  test('an unknown session is ignored', () async {
    final rig = SessionRig();
    await attachedSession(rig);

    rig.manager.publishAgentState(424242, 'claude', 'running');

    expect(rig.sent, isEmpty);
  });
}
