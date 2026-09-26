import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

void main() {
  const grid = (cols: 80, rows: 24);
  const running = SessionInfo(id: 7, index: 1, shell: 'zsh', createdAt: 1790000000000, attached: false);
  late FakeBackend backend;
  late FakeMachineSession machine;
  late Signal<ShellxBackend?> signedIn;
  late WorkspaceRegistry registry;
  late TerminalWorkspace workspace;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    signedIn = signal<ShellxBackend?>(backend);
    registry = WorkspaceRegistry(signedIn);
    workspace = registry.forMachine(agentA);
  });

  tearDown(() => registry.dispose());

  test('the registry returns one workspace per machine and refuses unpinned ones', () {
    expect(registry.forMachine(agentA), same(workspace));
    expect(() => registry.forMachine(agentB), throwsStateError);
  });

  test('prepare connects and lists sessions only on the first visit', () async {
    machine.sessions = [running];
    expect(await workspace.prepare(), [running]);
    expect(await workspace.prepare(), isNull);
    expect(machine.connectCalls, 1);
    expect(machine.listCalls, 1);
  });

  test('prepare throws the MachineFailed state for an untrusted machine', () async {
    machine.connectFailure = MachineConnectionFailure.untrusted;
    await expectLater(
      workspace.prepare(),
      throwsA(isA<MachineFailed>().having((s) => s.failure, 'failure', MachineConnectionFailure.untrusted)),
    );
  });

  test('openNew opens with the grid and activates the new tab', () async {
    final first = await workspace.openNew(grid);
    final second = await workspace.openNew((cols: 100, rows: 30));
    expect(machine.opened, [(cols: 80, rows: 24), (cols: 100, rows: 30)]);
    expect(workspace.tabs.value, [first, second]);
    expect(workspace.activeTab.value, same(second));
    workspace.select(0);
    expect(workspace.activeTab.value, same(first));
  });

  test('session_limit surfaces as AppErrorException and adds no tab', () async {
    machine.openError = const AppErrorException(AppErrorCode.sessionLimit, 'limit');
    await expectLater(workspace.openNew(grid), throwsA(isA<AppErrorException>()));
    expect(workspace.tabs.value, isEmpty);
  });

  test('spawn_failed (the agent answers the open with an id-less error) adds a failed tab with the reason', () async {
    machine.openError = const AppErrorException(AppErrorCode.spawnFailed, 'pwsh.exe not found');
    final tab = await workspace.openNew(grid);
    expect(workspace.tabs.value, [tab]);
    expect(workspace.activeTab.value, same(tab));
    expect(tab.isLive.value, isFalse);
    expect(tab.hasSession, isFalse);
    expect(tab.banner.value?.notice, TabNotice.failed);
    expect(tab.banner.value?.errorCode, AppErrorCode.spawnFailed);
    expect(tab.banner.value?.detail, 'pwsh.exe not found');

    // A second failure gets its own tab: the tabs never share an id.
    final again = await workspace.openNew(grid);
    expect(again.id, isNot(tab.id));

    // Nothing runs on the machine: closing it sends no session.close.
    await workspace.close(tab);
    await workspace.close(again);
    expect(workspace.tabs.value, isEmpty);
    expect(machine.closed, isEmpty);
  });

  test('a close after the workspace was disposed does nothing', () async {
    final tab = await workspace.openNew(grid);
    registry.remove(agentA);
    await workspace.close(tab);
    expect(machine.closed, isEmpty);
  });

  test('attach adds a live tab; attaching the same session again just selects it', () async {
    machine.sessions = [running];
    final tab = await workspace.attach(running, grid);
    await workspace.openNew(grid);
    expect(await workspace.attach(running, grid), same(tab));
    expect(workspace.activeTab.value, same(tab));
    expect(machine.attached, hasLength(1));
    expect(tab.isLive.value, isTrue);
  });

  test('Review Focus 3: attach → session_not_found gives a closable "ended" tab', () async {
    machine.attachErrors[running.id] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    final tab = await workspace.attach(running, grid);
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
    expect(workspace.tabs.value, [tab]);

    await workspace.close(tab);
    expect(workspace.tabs.value, isEmpty);
  });

  test('close sends session.close, keeps a valid selection, ignores machine errors', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    await workspace.close(b);
    expect(machine.closed, [b.id]);
    expect(workspace.activeTab.value, same(a));
    await workspace.close(a);
    expect(workspace.activeTab.value, isNull);
  });

  test('close: closing a tab before the active one keeps the same active tab', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    final c = await workspace.openNew(grid);
    final d = await workspace.openNew(grid);
    workspace.select(2); // c
    expect(workspace.activeTab.value, same(c));

    await workspace.close(a);
    expect(workspace.tabs.value, [b, c, d]);
    expect(workspace.activeTab.value, same(c));
  });

  test('close: closing a tab after the active one keeps it too', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    final c = await workspace.openNew(grid);
    final d = await workspace.openNew(grid);
    workspace.select(1); // b
    expect(workspace.activeTab.value, same(b));

    await workspace.close(d);
    expect(workspace.tabs.value, [a, b, c]);
    expect(workspace.activeTab.value, same(b));
  });

  test('close: closing the active tab in the middle selects the tab that takes its place', () async {
    final a = await workspace.openNew(grid);
    final b = await workspace.openNew(grid);
    final c = await workspace.openNew(grid);
    final d = await workspace.openNew(grid);
    workspace.select(1); // b
    expect(workspace.activeTab.value, same(b));

    await workspace.close(b);
    expect(workspace.tabs.value, [a, c, d]);
    expect(workspace.activeTab.value, same(c));
  });

  test('remove disposes the workspace of an unpaired machine', () async {
    await workspace.openNew(grid);
    registry.remove(agentA);
    backend.addMachine(agentA);
    expect(registry.forMachine(agentA), isNot(same(workspace)));
  });

  test('another sign-in drops the previous account\'s workspaces; signed out refuses', () async {
    await workspace.openNew(grid);
    final next = FakeBackend(pinnedList: [pinned(agentA)])..addMachine(agentA);
    signedIn.value = next;
    expect(registry.forMachine(agentA).machine, same(next.machines[agentA]));

    signedIn.value = null;
    expect(() => registry.forMachine(agentA), throwsStateError);
  });

  test('forMachine asks the backend every time: a new machine() after unpair + re-pair replaces the '
      'cached workspace', () async {
    // Simulate unpair (real client: the pin is dropped, the session is dead) then re-pair (Task 10:
    // ShellxBackend.machine returns a NEW MachineSession after an unpair + re-pair).
    await workspace.openNew(grid);
    final beforeVersion = registry.tabCount(agentA);
    expect(beforeVersion, 1);

    backend.machines.remove(agentA); // forget the old session, as `unpair` does
    final rePaired = backend.addMachine(agentA); // a fresh MachineSession after re-pairing
    final refreshed = registry.forMachine(agentA);

    expect(refreshed, isNot(same(workspace)));
    expect(refreshed.machine, same(rePaired));
    expect(refreshed.tabs.value, isEmpty); // the old workspace (and its tab) was disposed
    // The version bumped so the pill's `tabCount` recomputes.
    expect(registry.tabCount(agentA), 0);
  });

  test('forMachine sheds the cached workspace when machine() throws StateError', () async {
    await workspace.openNew(grid);
    backend.machines.remove(agentA); // not pinned any more, so machine() throws StateError

    expect(() => registry.forMachine(agentA), throwsStateError);

    // Re-pairing gives a brand-new workspace; the old one (and its tab) is gone.
    final rePaired = backend.addMachine(agentA);
    final fresh = registry.forMachine(agentA);
    expect(fresh, isNot(same(workspace)));
    expect(fresh.machine, same(rePaired));
    expect(fresh.tabs.value, isEmpty);
  });

  test('tabCount is reactive inside a computed created before forMachine', () async {
    final freshBackend = FakeBackend(pinnedList: [pinned(agentB)]);
    freshBackend.addMachine(agentB);
    final freshSignal = signal<ShellxBackend?>(freshBackend);
    final freshRegistry = WorkspaceRegistry(freshSignal);
    addTearDown(freshRegistry.dispose);

    final seen = <int>[];
    final count = computed<int>(() => freshRegistry.tabCount(agentB));
    final stop = count.subscribe(seen.add);
    addTearDown(stop);

    expect(seen.last, 0); // no workspace yet: the computed was built before forMachine

    final freshWorkspace = freshRegistry.forMachine(agentB);
    await freshWorkspace.openNew(grid);
    expect(seen.last, 1); // follows the newly created workspace's own tabs signal

    await freshWorkspace.openNew(grid);
    expect(seen.last, 2);

    freshRegistry.remove(agentB);
    expect(seen.last, 0); // removal (and disposal) bumps the version too

    // A workspace created after a remove is picked up again, with no stale dependency left over.
    final another = freshRegistry.forMachine(agentB);
    await another.openNew(grid);
    expect(seen.last, 1);
  });
}
