import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../support/fakes.dart';

/// The shared fakes keep the port contract of `backend.dart` where later tasks rely on it.
void main() {
  Matcher throwsFailure(MachineConnectionFailure failure) =>
      throwsA(isA<MachineConnectionException>().having((e) => e.failure, 'failure', failure));

  Future<void> expectShutDown(FakeMachineSession machine, FakeTabHandle tab, {required bool Function() done}) async {
    await pumpEventQueue();
    expect(done(), isTrue, reason: 'the tab stream ends');
    expect(tab.isAttached, isFalse);
    expect(machine.tabs, isEmpty);
    await expectLater(machine.connect(), throwsFailure(MachineConnectionFailure.untrusted));
    expect(machine.state, isA<MachineFailed>());
    await expectLater(machine.listSessions(), throwsFailure(MachineConnectionFailure.untrusted));
    await expectLater(machine.openSession(cols: 80, rows: 24), throwsFailure(MachineConnectionFailure.untrusted));
    await expectLater(machine.attach(tab.id, cols: 80, rows: 24), throwsFailure(MachineConnectionFailure.untrusted));
  }

  for (final deleteFails in [false, true]) {
    test('unpair shuts the session down like ClientService.unpair (DELETE fails: $deleteFails)', () async {
      final backend = FakeBackend(pinnedList: [pinned(agentA)]);
      final machine = backend.addMachine(agentA);
      await machine.connect();
      final tab = await machine.openSession(cols: 80, rows: 24) as FakeTabHandle;
      var done = false;
      tab.events.listen((_) {}, onDone: () => done = true);
      final states = <MachineConnectionState>[];
      machine.states.listen(states.add);

      if (deleteFails) {
        backend.unpairError = const ApiException(status: 0, code: 'network', message: 'offline');
        await expectLater(backend.unpair(agentA), throwsA(isA<ApiException>()));
      } else {
        await backend.unpair(agentA);
      }

      expect(states.first, isA<MachineIdle>()); // the channel went with it
      expect(backend.unpaired, [agentA]);
      expect(await backend.pinnedMachines(), isEmpty);
      expect(() => backend.machine(agentA), throwsStateError);
      await expectShutDown(machine, tab, done: () => done);
    });
  }

  test('unpair after an untrusted handshake shuts that session down too', () async {
    final backend = FakeBackend(pinnedList: [pinned(agentA)]);
    final machine = backend.addMachine(agentA);
    final tab = await machine.openSession(cols: 80, rows: 24) as FakeTabHandle;
    final events = <TabEvent>[];
    var done = false;
    tab.events.listen(events.add, onDone: () => done = true);
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await expectLater(machine.connect(), throwsFailure(MachineConnectionFailure.untrusted));
    expect(events.single, isA<TabError>());
    expect(done, isFalse);

    await backend.unpair(agentA);

    await expectShutDown(machine, tab, done: () => done);
  });

  test('emitState scripts machine states', () {
    final machine = FakeMachineSession(agentA);
    final states = <MachineConnectionState>[];
    machine.states.listen(states.add);
    machine.emitState(const MachineConnecting());
    expect(machine.state, isA<MachineConnecting>());
    expect(states.single, isA<MachineConnecting>());
  });
}
