import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

SessionInfo info(int id) => SessionInfo(id: id, index: id, shell: 'zsh', createdAt: 1790000000000, attached: false);

void main() {
  const grid = (cols: 80, rows: 24);
  late FakeBackend backend;
  late WorkspaceRegistry registry;
  late TerminalWorkspace workspace;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    backend.addMachine(agentA);
    registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
    workspace = registry.forMachine(agentA);
  });

  tearDown(() => registry.dispose());

  Future<void> open(int id) => workspace.attach(info(id), grid);

  test('a tab that appears later is selected when it is the pending one', () async {
    await open(1);
    workspace.pendingSelect(7);
    expect(workspace.hasPendingSelect, isTrue);
    expect(workspace.activeTab.peek()?.id, 1);
    await open(7);
    expect(workspace.activeTab.peek()?.id, 7);
    expect(workspace.hasPendingSelect, isTrue);
  });

  test('another tab appearing first does not consume the pending one', () async {
    workspace.pendingSelect(7);
    await open(1);
    expect(workspace.hasPendingSelect, isTrue);
    await open(7);
    expect(workspace.activeTab.peek()?.id, 7);
    await open(2);
    expect(workspace.activeTab.peek()?.id, 7, reason: 'the notification\'s tab keeps the focus until the ttl');
  });

  test('the pending tab wins while the other tabs reconnect; a user pick then sticks', () async {
    workspace.pendingSelect(2);
    await open(1);
    await open(2);
    await open(3);
    expect(workspace.activeTab.peek()?.id, 2);
    expect(workspace.hasPendingSelect, isTrue);
    await open(2); // re-attaching an open tab is not a user pick
    expect(workspace.activeTab.peek()?.id, 2);
    workspace.select(2); // the user taps tab 3
    expect(workspace.activeTab.peek()?.id, 3);
    await open(4);
    expect(workspace.activeTab.peek()?.id, 4);
    expect(workspace.hasPendingSelect, isFalse);
  });

  test('the pending tab appearing is selected directly: no flicker through the last tab', () async {
    await open(1);
    await open(2);
    workspace.select(0);
    workspace.pendingSelect(7);
    final ids = <int?>[];
    final stop = effect(() => ids.add(workspace.activeTab.value?.id));
    addTearDown(stop);
    await open(7);
    await open(3); // another tab arriving while 7 is pending, so 7 is not the last
    expect(workspace.activeTab.peek()?.id, 7);
    expect(ids, [1, 7], reason: 'the effect runs once at once, then only for the pending tab');
  });

  test('a tab arriving while the pending one is already open keeps the focus on it', () async {
    workspace.pendingSelect(7);
    await open(7);
    final indexes = <int>[];
    final stop = effect(() => indexes.add(workspace.activeIndex.value));
    addTearDown(stop);
    await open(1);
    await open(2);
    expect(indexes, [0], reason: 'never moved to the new last index');
  });

  test('a user openNew drops the pending one', () async {
    workspace.pendingSelect(2);
    await open(2);
    await workspace.openNew(grid);
    expect(workspace.hasPendingSelect, isFalse);
    expect(workspace.activeTab.peek()?.id, isNot(2));
  });

  test('the user choosing a tab cancels the pending one', () async {
    await open(1);
    await open(2);
    workspace.pendingSelect(7);
    workspace.select(0);
    expect(workspace.hasPendingSelect, isFalse);
    await open(7);
    expect(workspace.activeTab.peek()?.id, 7, reason: 'a new tab becomes active as always');
    workspace.select(0);
    expect(workspace.activeTab.peek()?.id, 1);
  });

  test('a pending select expires after 30 seconds', () {
    fakeAsync((async) {
      workspace.pendingSelect(7);
      async.elapse(const Duration(seconds: 29));
      expect(workspace.hasPendingSelect, isTrue);
      async.elapse(const Duration(seconds: 2));
      expect(workspace.hasPendingSelect, isFalse);
    });
  });

  test('already open: selects at once and leaves nothing pending', () async {
    await open(1);
    await open(7);
    workspace.select(0);
    workspace.pendingSelect(7);
    expect(workspace.activeTab.peek()?.id, 7);
    expect(workspace.hasPendingSelect, isFalse);
  });

  test('disposing the workspace cancels the timer', () {
    fakeAsync((async) {
      workspace.pendingSelect(7);
      registry.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
