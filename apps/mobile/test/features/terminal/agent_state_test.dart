import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

/// Agent quick reply §3: the live agent state of a tab, the reply bar it shows, and the machine's dot.
void main() {
  const needsInput = TabAgent(agent: 'claude', state: AgentWireState.needsInput);
  const running = TabAgent(agent: 'claude', state: AgentWireState.running);

  group('a tab', () {
    late FakeMachineSession machine;
    late FakeTabHandle handle;
    late ExtraKeysController keys;
    late TerminalTabController tab;

    setUp(() async {
      machine = FakeMachineSession(agentA);
      handle = await machine.openSession(cols: 80, rows: 24) as FakeTabHandle;
      keys = ExtraKeysController();
      tab = TerminalTabController(machine: machine, handle: handle, modifiers: keys, cols: 80, rows: 24);
    });

    tearDown(() {
      tab.dispose();
      keys.dispose();
    });

    test('follows TabAgent; none clears it', () {
      expect(tab.agentState.peek(), isNull);
      handle.emit(running);
      expect(tab.agentState.peek(), AgentWireState.running);
      handle.emit(needsInput);
      expect(tab.agentState.peek(), AgentWireState.needsInput);
      handle.emit(const TabAgent());
      expect(tab.agentState.peek(), isNull);
    });

    test('the reply bar shows only while the agent waits', () {
      expect(tab.showReplyBar.peek(), isFalse);
      handle.emit(needsInput);
      expect(tab.showReplyBar.peek(), isTrue);
      handle.emit(running);
      expect(tab.showReplyBar.peek(), isFalse);
    });

    test('⌨ puts the extra keys back until the next needs_input', () {
      handle.emit(needsInput);
      tab.dismissReplyBar();
      expect(tab.showReplyBar.peek(), isFalse);
      handle.emit(needsInput); // the same question, told again (a re-attach)
      expect(tab.showReplyBar.peek(), isFalse);
      handle.emit(running);
      handle.emit(needsInput);
      expect(tab.showReplyBar.peek(), isTrue);
    });

    test('a tab that is no longer live shows no bar and forgets the agent', () {
      handle.emit(needsInput);
      handle.emit(const TabDetached(DetachReason.takenOver));
      expect(tab.showReplyBar.peek(), isFalse);
      expect(tab.agentState.peek(), isNull);
    });
  });

  group('a machine', () {
    late FakeBackend backend;
    late FakeMachineSession machine;
    late WorkspaceRegistry registry;
    late TerminalWorkspace ws;

    setUp(() async {
      backend = FakeBackend(pinnedList: [pinned(agentA)]);
      machine = backend.addMachine(agentA);
      registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
      ws = registry.forMachine(agentA);
      await ws.openNew((cols: 80, rows: 24));
      await ws.openNew((cols: 80, rows: 24));
    });

    tearDown(() => registry.dispose());

    test('shows the most urgent agent state of its tabs: needs_input, then running', () {
      AgentWireState? seen;
      final stop = effect(() => seen = registry.agentState(agentA));
      addTearDown(stop);
      expect(seen, isNull);
      machine.handles.first.emit(running);
      expect(seen, AgentWireState.running);
      machine.handles.last.emit(needsInput);
      expect(seen, AgentWireState.needsInput);
      machine.handles.last.emit(const TabAgent(agent: 'claude', state: AgentWireState.idle));
      expect(seen, AgentWireState.running);
      machine.handles.first.emit(const TabAgent(agent: 'claude', state: AgentWireState.done));
      expect(seen, isNull, reason: 'idle and done show no dot');
      expect(registry.agentState(agentB), isNull);
    });
  });
}
