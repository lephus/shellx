import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/domain/machine_entry.dart';
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_ai_lines.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

/// Agent ids 1…n (valid UUID strings).
String agent(int n) => '${n.toString().padLeft(8, '0')}-0000-4000-8000-000000000000';

MachineEntry entry(String id, {bool online = true, bool paired = true}) => MachineEntry(
  id: id,
  name: 'Mac $id',
  platform: DevicePlatform.macos,
  online: online,
  lastSeenAt: null,
  paired: paired,
);

AiListing listing({int sessions = 2, int waiting = 1, bool available = true}) => AiListing(
  available: available,
  sessions: [
    for (var i = 0; i < sessions; i++)
      AiSessionInfo(
        sid: 'e.-${i + 1}',
        agentId: 'claude',
        agentName: 'Claude',
        title: 'Phiên $i',
        state: i < waiting ? AiRemoteState.needsInput : AiRemoteState.idle,
      ),
  ],
);

/// V2-2b B21: the machine list holds the AI listing of what it shows, and only while it shows.
void main() {
  late FakeBackend backend;
  late FakeSessionHolder session;
  late WorkspaceRegistry registry;
  late FakePopupHandler popups;
  late MachineAiLines lines;

  /// A paired machine whose computer has AI for phones.
  FakeMachineSession add(String id, {bool? supported = true}) {
    backend.pinnedList = [...backend.pinnedList, pinned(id)];
    return backend.addMachine(id)..ai.supportedValue = supported;
  }

  setUp(() {
    backend = FakeBackend();
    session = FakeSessionHolder(backend);
    registry = WorkspaceRegistry(session.backend);
    popups = FakePopupHandler();
    getIt.registerSingleton<PopupHandler>(popups);
    lines = MachineAiLines(session, registry);
  });

  tearDown(() async {
    lines.dispose();
    registry.dispose();
    await getIt.reset();
  });

  test('a machine shown: one handshake, its listing held; the line counts sessions and the ones that wait', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    expect(mac.connectCalls, 1);
    expect(mac.ai.watching, isTrue);
    expect(lines.line(agentA), isNull, reason: 'nothing heard yet');
    mac.ai.emitListing(listing());
    expect(lines.line(agentA), (sessions: 2, waiting: 1));
    mac.ai.emitListing(listing(sessions: 3, waiting: 0));
    expect(lines.line(agentA), (sessions: 3, waiting: 0));
  });

  test('no line without sessions, or while no window serves AI', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    mac.ai.emitListing(listing(sessions: 0));
    expect(lines.line(agentA), isNull);
    mac.ai.emitListing(AiListing.unavailable);
    expect(lines.line(agentA), isNull);
  });

  test('a listing of a computer where no window serves AI shows no line, whatever sessions it carries', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    mac.ai.emitListing(listing(available: false));
    expect(lines.line(agentA), isNull);
  });

  test('at most six machines, the first ones of the list (the one used last first)', () async {
    final machines = [for (var n = 1; n <= 8; n++) add(agent(n))];
    lines
      ..setMachines([for (var n = 1; n <= 8; n++) entry(agent(n))])
      ..setVisible(true);
    await pumpEventQueue();
    expect([for (final m in machines) m.ai.watching], [true, true, true, true, true, true, false, false]);
    expect(machines.last.connectCalls, 0);
  });

  test('offline, not paired, or not shown: no handshake at all', () async {
    final offline = add(agentA);
    final unpaired = backend.addMachine(agentB);
    lines.setMachines([entry(agentA, online: false), entry(agentB, paired: false)]);
    await pumpEventQueue();
    lines.setVisible(true);
    await pumpEventQueue();
    expect(offline.connectCalls + unpaired.connectCalls, 0);
  });

  test('let go when a page covers the list, the app goes to the background, the relay drops or the machine goes '
      'offline; held again when it shows', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    mac.ai.emitListing(listing());

    lines.setVisible(false);
    expect((mac.ai.watching, lines.line(agentA)), (false, null));
    lines.setVisible(true);
    await pumpEventQueue();
    expect(mac.ai.watching, isTrue);

    lines.setForeground(false);
    expect(mac.ai.watching, isFalse);
    lines.setForeground(true);
    await pumpEventQueue();
    expect(mac.ai.watching, isTrue);

    backend.emitRelay(RelayConnectionState.disconnected);
    await pumpEventQueue();
    expect(mac.ai.watching, isFalse);
    backend.emitRelay(RelayConnectionState.connected);
    await pumpEventQueue();
    expect(mac.ai.watching, isTrue);

    lines.setMachines([entry(agentA, online: false)]);
    await pumpEventQueue();
    expect(mac.ai.watching, isFalse);
  });

  test('a machine that cannot be reached shows nothing and says nothing; pulling down tries it again', () async {
    final mac = add(agentA)..connectFailure = MachineConnectionFailure.agentOffline;
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    expect(lines.line(agentA), isNull);
    expect(popups.errors, isEmpty);
    // Not tried again by every change of the list.
    lines.setMachines([entry(agentA)]);
    await pumpEventQueue();
    expect(mac.connectCalls, 1);
    mac.connectFailure = null;
    await lines.refresh();
    expect(mac.connectCalls, 2);
    expect(mac.ai.watching, isTrue);
  });

  test('a computer whose AI support is not known yet is asked once on the machine; the terminal page still shows '
      'its picker on the first visit', () async {
    final mac = add(agentA, supported: null);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    expect(mac.listCalls, 1);
    expect(mac.ai.watching, isFalse, reason: 'an older computer: no AI for phones, no line');
    expect(await registry.forMachine(agentA).prepare(), isNotNull);
  });

  test('let go: nothing listens to the computer any more', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    expect(mac.ai.hasListingListener, isTrue);
    lines.setVisible(false);
    expect(mac.ai.hasListingListener, isFalse);
  });

  test('the list stops showing during the handshake: nothing is held once it is over', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true)
      ..setVisible(false);
    await pumpEventQueue();
    expect(mac.ai.watching, isFalse);
    expect(lines.line(agentA), isNull);
  });

  test('a listing the computer already sent shows its line at once', () async {
    final mac = add(agentA);
    mac.ai.emitListing(listing());
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    expect(lines.line(agentA), (sessions: 2, waiting: 1));
  });

  test('disposed: everything let go', () async {
    final mac = add(agentA);
    lines
      ..setMachines([entry(agentA)])
      ..setVisible(true);
    await pumpEventQueue();
    lines.dispose();
    expect(mac.ai.watching, isFalse);
  });
}
