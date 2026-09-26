import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/machines/presentation/controllers/machine_list_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);
  late FakeBackend backend;
  late MachineListController controller;

  setUp(() async {
    await S.load(const Locale('vi'));
    backend = FakeBackend(
      devices: [
        agentDevice(agentB, 'zeta-pc', online: false, lastSeenAt: now.subtract(const Duration(hours: 2))),
        agentDevice(agentA, 'MacBook-Pro'),
        const RemoteDevice(
          id: '99999999-9999-4999-8999-999999999999',
          kind: DeviceKind.mobile,
          name: 'iPhone 15',
          platform: DevicePlatform.ios,
          online: true,
          lastSeenAt: null,
          pairedWithMe: false,
        ),
      ],
      pinnedList: [pinned(agentA)],
    );
    controller = MachineListController(backend: backend, now: () => now);
  });

  tearDown(() => controller.dispose());

  List<String> names() => [for (final machine in controller.state.value.machines) machine.name];

  test('lists agents only, sorted by name, with the local pin as "paired"', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    expect(names(), ['MacBook-Pro', 'zeta-pc']);
    final machines = controller.state.value.machines;
    expect(machines.first.paired, isTrue);
    expect(machines.last.paired, isFalse);
    expect(machines.last.lastSeenAt, now.subtract(const Duration(hours: 2)));
  });

  test('uses PRESENCE while connected and the REST snapshot otherwise', () async {
    await controller.refresh();
    expect(controller.state.value.machines.first.online, isFalse); // hub says nothing is online

    backend.relayStateValue = RelayConnectionState.disconnected;
    await controller.refresh();
    expect(controller.state.value.machines.first.online, isTrue); // REST says online
  });

  test('PRESENCE offline greys the machine and stamps "last online" now', () async {
    backend.onlineIds.add(agentA);
    await controller.refresh();
    var updates = -1; // the effect runs once right away
    final stop = effect(() {
      controller.state.value;
      updates++;
    });
    addTearDown(stop);

    backend.emitPresence(agentA, online: false);

    final mac = controller.state.value.machines.firstWhere((m) => m.id == agentA);
    expect(mac.online, isFalse);
    expect(mac.lastSeenAt, now);
    expect(updates, 1);

    backend.emitPresence(agentA, online: true);
    expect(controller.state.value.machines.firstWhere((m) => m.id == agentA).online, isTrue);
  });

  test('PRESENCE from an unknown computer refreshes the list', () async {
    await controller.refresh();
    backend.deviceList = [...backend.deviceList, agentDevice('55555555-5555-4555-8555-555555555555', 'new-box')];
    backend.emitPresence('55555555-5555-4555-8555-555555555555', online: true);
    await pumpEventQueue();
    expect(names(), contains('new-box'));
  });

  test('refreshes when the relay reconnects', () async {
    await controller.refresh();
    backend.deviceList = [agentDevice(agentA, 'renamed')];
    backend.emitRelay(RelayConnectionState.connected);
    await pumpEventQueue();
    expect(names(), ['renamed']);
  });

  test('keeps the last list and holds the spec text when the refresh fails', () async {
    await controller.refresh();
    backend.devicesError = const ApiException(status: 429, code: 'rate_limited', message: 'slow');
    await controller.refresh();
    expect(controller.state.value.machines, hasLength(2));
    expect(controller.state.hasError, isTrue);
    expect(controller.state.error?.title, 'Thử lại sau ít phút.');
    expect(controller.state.error?.originalError, isA<ApiException>());
    expect(controller.state.isLoading, isFalse);
  });

  test(
    'relay loss synthesizes an offline PRESENCE for every online machine, but does not stamp '
    '"last online" with now: it keeps the last known time, unlike a real hub PRESENCE',
    () async {
      backend.onlineIds.add(agentB);
      await controller.refresh();
      final before = controller.state.value.machines.firstWhere((m) => m.id == agentB);
      expect(before.online, isTrue);
      expect(before.lastSeenAt, now.subtract(const Duration(hours: 2)));

      backend.emitRelayLoss();

      final after = controller.state.value.machines.firstWhere((m) => m.id == agentB);
      expect(after.online, isFalse);
      // Unchanged: this is the synthetic offline PRESENCE the client raises on relay loss, not a
      // real one from the hub, so it must not overwrite the last time actually reported.
      expect(after.lastSeenAt, now.subtract(const Duration(hours: 2)));
      expect(controller.waiting.value, isTrue);
    },
  );

  test("tabsOpen is reactive: a computed reading it follows the registry's tab count", () async {
    final backendSignal = signal<ShellxBackend?>(backend);
    final registry = WorkspaceRegistry(backendSignal);
    addTearDown(registry.dispose);
    backend.addMachine(agentA);
    final withRegistry = MachineListController(backend: backend, registry: registry, now: () => now);
    addTearDown(withRegistry.dispose);

    final seen = <int>[];
    final tabCount = computed<int>(() => withRegistry.tabsOpen(agentA));
    final stop = tabCount.subscribe(seen.add);
    addTearDown(stop);
    expect(seen.last, 0); // no workspace yet

    final workspace = registry.forMachine(agentA);
    await workspace.openNew((cols: 80, rows: 24));
    expect(seen.last, 1);

    await workspace.openNew((cols: 80, rows: 24));
    expect(seen.last, 2);
  });
}
