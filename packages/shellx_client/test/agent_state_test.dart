import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

/// Agent quick reply §3: a tab hears its agent's state from `agent.state`
/// and from `session.attached`.
void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  List<(String?, AgentWireState?)> agents(TabRecorder r) => [
    for (final e in r.events.whereType<TabAgent>()) (e.agent, e.state),
  ];

  test('agent.state reaches the attached tab as TabAgent', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      h.sessions.publishAgentState(tab.id, 'claude', 'needs_input');
      settle(async);
      h.sessions.publishAgentState(tab.id, '', '');
      settle(async);

      expect(agents(recorder), [
        ('claude', AgentWireState.needsInput),
        (null, null),
      ]);
    });
  });

  test('attaching brings the state session.attached carries', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.sessions.agentOf = (_) => (agent: 'codex', state: 'running');
      h.run(h.tabletMachine.listSessions());
      final tabletTab = h.run(
        h.tabletMachine.attach(phoneTab.id, cols: 80, rows: 24),
      );
      final recorder = TabRecorder(tabletTab);
      settle(async);

      expect(agents(recorder), [('codex', AgentWireState.running)]);
    });
  });
}
