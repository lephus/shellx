import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/fakes.dart';

SessionInfo info(int id) => SessionInfo(id: id, index: id, shell: 'zsh', createdAt: 1790000000000, attached: false);

void main() {
  const grid = (cols: 80, rows: 24);

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

    test('output while the tab is not being looked at marks it; looking clears it', () {
      tab.setViewed(false);
      handle.emit(const TabOutput('building...'));
      expect(tab.unseen.peek(), isTrue);
      tab.setViewed(true);
      expect(tab.unseen.peek(), isFalse);
      handle.emit(const TabOutput('more'));
      expect(tab.unseen.peek(), isFalse, reason: 'being looked at');
    });

    test('a tab nobody has left alone starts as seen', () {
      expect(tab.unseen.peek(), isFalse);
    });

    test('output that arrives for a background tab counts at once, not when the slow tick writes it', () {
      tab
        ..setActive(false)
        ..setViewed(false);
      handle.emit(const TabOutput('x'));
      expect(tab.unseen.peek(), isTrue);
    });
  });

  group('a workspace', () {
    late FakeBackend backend;
    late FakeMachineSession machine;
    late WorkspaceRegistry registry;
    late TerminalWorkspace ws;

    setUp(() async {
      backend = FakeBackend(pinnedList: [pinned(agentA)]);
      machine = backend.addMachine(agentA);
      registry = WorkspaceRegistry(signal<ShellxBackend?>(backend));
      ws = registry.forMachine(agentA);
      await ws.attach(info(1), grid);
      await ws.attach(info(2), grid);
      ws.select(0);
    });

    tearDown(() => registry.dispose());

    void emit(int index, String text) {
      final id = ws.tabs.peek()[index].id;
      machine.handles.firstWhere((h) => h.id == id).emit(TabOutput(text));
    }

    test('viewed means active tab AND the page showing', () {
      ws.setViewing(true);
      emit(1, 'bg'); // not the active tab
      expect(ws.unseenCount, 1);
      ws.setViewing(false);
      emit(0, 'x'); // the active tab, but the page is not showing
      expect(ws.unseenCount, 2);
      ws.setViewing(true); // the active tab is looked at again
      expect(ws.unseenCount, 1);
      ws.selectFirstUnseen();
      expect(ws.activeIndex.peek(), 1);
      expect(ws.unseenCount, 0);
    });

    test('selectFirstUnseen does nothing when nothing is unseen', () {
      ws.setViewing(true);
      ws.selectFirstUnseen();
      expect(ws.activeIndex.peek(), 0);
    });

    test('a notification that chose an open tab keeps it when the page opens; the next visit starts fresh', () {
      emit(1, 'bg');
      ws.pendingSelect(ws.tabs.peek()[0].id);
      ws.selectFirstUnseen();
      expect(ws.activeIndex.peek(), 0, reason: 'the notification wins');
      ws.setViewing(true);
      ws.setViewing(false);
      ws.selectFirstUnseen();
      expect(ws.activeIndex.peek(), 1, reason: 'a later visit goes to the new output');
    });

    test('selecting a tab shows it: its count clears', () {
      ws.setViewing(true);
      emit(1, 'bg');
      expect(ws.unseenCount, 1);
      ws.select(1);
      expect(ws.unseenCount, 0);
    });

    test('closing a tab drops its count (recomputed from the tabs)', () async {
      ws.setViewing(true);
      emit(1, 'bg');
      expect(ws.unseenCount, 1);
      await ws.close(ws.tabs.peek()[1]);
      expect(ws.unseenCount, 0);
    });

    test('a tab opened while the page is not showing counts its output', () async {
      ws.setViewing(false);
      await ws.attach(info(3), grid);
      emit(2, 'hello');
      expect(ws.unseenCount, 1);
    });

    test('the registry counts per machine and follows the workspace', () {
      ws.setViewing(true);
      var seen = -1;
      final stop = effect(() => seen = registry.unseenCount(agentA));
      addTearDown(stop);
      expect(seen, 0);
      emit(1, 'bg');
      expect(seen, 1);
      expect(registry.unseenCount(agentB), 0);
      registry.remove(agentA);
      expect(seen, 0);
    });
  });
}
