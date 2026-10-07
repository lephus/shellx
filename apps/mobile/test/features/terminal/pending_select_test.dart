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
    expect(workspace.hasPendingSelect, isFalse);
  });

  test('another tab appearing first does not consume the pending one', () async {
    workspace.pendingSelect(7);
    await open(1);
    expect(workspace.hasPendingSelect, isTrue);
    await open(7);
    expect(workspace.activeTab.peek()?.id, 7);
    expect(workspace.hasPendingSelect, isFalse);
    await open(2);
    expect(workspace.activeTab.peek()?.id, 2, reason: 'a tab opened afterwards is active as always');
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
