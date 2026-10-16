import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' show effect;
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';

import '../../support/fakes.dart';

void main() {
  late FakeMachineSession machine;
  late FakeTabHandle handle;
  late ExtraKeysController keys;
  late TerminalTabController tab;

  String screen() => tab.terminal.value.buffer.getText().trim();

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

  test('closing a tab empties its draft at once (it may hold a password)', () async {
    final h = await machine.openSession(cols: 80, rows: 24) as FakeTabHandle;
    final t = TerminalTabController(machine: machine, handle: h, modifiers: keys, cols: 80, rows: 24);
    final holder = t.draft;
    holder.value = 'hunter2';
    t.dispose();
    expect(holder.value, '');
  });

  test('output is written to the terminal, keys become input messages', () {
    handle.emit(const TabOutput('xin chào'));
    expect(screen(), 'xin chào');

    tab.terminal.value.textInput('ls\n');
    expect(utf8.decode(machine.inputs.single.data), 'ls\r');
    expect(machine.inputs.single.id, handle.id);
  });

  test('title falls back to "<shell> <index>", OSC title wins', () {
    expect(tab.title.value, 'zsh 1');
    handle.emit(const TabOutput('\x1b]2;vim notes.md\x07'));
    expect(tab.title.value, 'vim notes.md');
  });

  test('session.reset swaps in a clean terminal of the same size', () {
    tab.terminal.value.resize(100, 30);
    handle.emit(const TabOutput('stale output'));
    final before = tab.terminal.value;
    var swaps = -1; // the effect runs once right away
    final stop = effect(() {
      tab.terminal.value;
      swaps++;
    });
    addTearDown(stop);

    handle.emit(const TabReset());

    expect(tab.terminal.value, isNot(same(before)));
    expect(screen(), isEmpty);
    expect(tab.terminal.value.viewWidth, 100);
    expect(tab.terminal.value.viewHeight, 30);
    expect(swaps, 1);
    handle.emit(const TabOutput('fresh'));
    expect(screen(), 'fresh');
  });

  test('resizes are debounced and deduplicated', () {
    fakeAsync((async) {
      tab.terminal.value.resize(90, 30);
      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(milliseconds: 149));
      expect(machine.resizes, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(machine.resizes, [(id: handle.id, cols: 100, rows: 40)]);

      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, hasLength(1));
    });
  });

  test('A10 D22: the keyboard sliding up and down five times in 400 ms sends one size, the last', () {
    fakeAsync((async) {
      for (var i = 0; i < 5; i++) {
        tab.terminal.value.resize(80, 24 - 6 * (i % 2)); // keyboard up, then down
        async.elapse(const Duration(milliseconds: 40));
      }
      tab.terminal.value.resize(80, 18); // ends up
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, [(id: handle.id, cols: 80, rows: 18)]);
    });
  });

  test('A10 D29: output of a tab in the background is held back at most a quarter of a second', () {
    fakeAsync((async) {
      // Built inside the fake zone: a stream delivers events in the zone it was listened in, and
      // the feed's timer must be the fake one (a tab built in `setUp` would use a real Timer).
      late FakeTabHandle h;
      machine.openSession(cols: 80, rows: 24).then((v) => h = v as FakeTabHandle);
      async.flushMicrotasks();
      final t = TerminalTabController(machine: machine, handle: h, modifiers: keys, cols: 80, rows: 24);
      String text() => t.terminal.value.buffer.getText().trim();
      t.setActive(false);
      h.emit(const TabOutput('background output'));
      expect(text(), isEmpty);
      async.elapse(const Duration(milliseconds: 249));
      expect(text(), isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(text(), 'background output');
      t.dispose();
    });
  });

  test('A10 D29: the echo of a key is written at once, in the front tab', () {
    fakeAsync((async) {
      tab.terminal.value.textInput('l');
      expect(machine.inputs, hasLength(1));
      handle.emit(const TabOutput('l'));
      expect(screen(), 'l', reason: 'no wait for a tick');
    });
  });

  test('A10 D29: the exit banner never comes before the last output', () {
    fakeAsync((async) {
      tab.setActive(false);
      handle.emit(const TabOutput('last words'));
      handle.emit(const TabExited(1));
      expect(screen(), 'last words');
      expect(tab.banner.value?.notice, TabNotice.exited);
    });
  });

  test('A10 D29: a screen reset forgets output that was still waiting', () {
    fakeAsync((async) {
      tab.setActive(false);
      handle.emit(const TabOutput('old screen'));
      handle.emit(const TabReset());
      async.elapse(const Duration(seconds: 1));
      expect(screen(), isEmpty);
      handle.emit(const TabOutput('new'));
      tab.setActive(true);
      expect(screen(), 'new');
    });
  });

  test('Review Focus 4: a zero-sized viewport is never sent', () {
    fakeAsync((async) {
      tab.terminal.value.onResize!(0, 0, 0, 0);
      tab.terminal.value.onResize!(120, 0, 0, 0);
      async.elapse(const Duration(seconds: 1));
      expect(machine.resizes, isEmpty);
    });
  });

  test('exit shows a banner and stops input and resize', () {
    fakeAsync((async) {
      handle.emit(const TabExited(0));
      expect(tab.banner.value?.notice, TabNotice.exited);
      expect(tab.banner.value?.exitCode, 0);
      expect(tab.isLive.value, isFalse);

      tab.terminal.value.textInput('x');
      tab.terminal.value.resize(100, 40);
      async.elapse(const Duration(seconds: 1));
      expect(machine.inputs, isEmpty);
      expect(machine.resizes, isEmpty);
    });
  });

  test('closed on the computer stays the banner when session.exited follows', () {
    handle.emit(const TabDetached(DetachReason.closedByHost));
    handle.emit(const TabExited(0));
    expect(tab.banner.value?.notice, TabNotice.closedByHost);
  });

  test('a TabError(spawn_failed) on a live tab keeps the reason for the banner', () {
    handle.emit(const TabError(AppErrorCode.spawnFailed, 'pwsh.exe not found'));
    expect(tab.banner.value?.notice, TabNotice.failed);
    expect(tab.banner.value?.errorCode, AppErrorCode.spawnFailed);
    expect(tab.banner.value?.detail, 'pwsh.exe not found');
  });

  test('a failed open is a tab without a session that shows the reason and sends nothing', () {
    final failed = TerminalTabController.failed(
      machine: machine,
      id: -1,
      error: const AppErrorException(AppErrorCode.spawnFailed, 'pwsh.exe not found'),
      modifiers: keys,
    );
    addTearDown(failed.dispose);
    expect(failed.hasSession, isFalse);
    expect(failed.isLive.value, isFalse);
    expect(failed.banner.value?.notice, TabNotice.failed);
    expect(failed.banner.value?.errorCode, AppErrorCode.spawnFailed);
    expect(failed.banner.value?.detail, 'pwsh.exe not found');
    failed.terminal.value.textInput('ls\n');
    expect(machine.inputs, isEmpty);
    expect(tab.hasSession, isTrue);
  });

  test('Review Focus 3: session_not_found while reattaching ends the tab', () {
    handle.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
    expect(tab.isLive.value, isFalse);
  });

  test('taken over → reattach attaches again with the current size and keeps the screen', () async {
    machine.sessions = [const SessionInfo(id: 101, index: 1, shell: 'zsh', createdAt: 0, attached: true)];
    tab.terminal.value.resize(100, 30);
    handle.emit(const TabOutput('before '));
    handle.emit(const TabDetached(DetachReason.takenOver));
    expect(tab.banner.value?.notice, TabNotice.takenOver);
    final before = tab.terminal.value;

    await tab.reattach();

    expect(machine.attached.single, (id: handle.id, cols: 100, rows: 30));
    expect(tab.banner.value, isNull);
    expect(tab.isLive.value, isTrue);
    expect(tab.terminal.value, same(before));
    machine.handle(handle.id).emit(const TabOutput('back'));
    expect(screen(), 'before back');
  });

  test('catch-up output sent while re-attaching is not lost', () async {
    handle.emit(const TabDetached(DetachReason.takenOver));
    // shellx_client returns the same tab and replays output before `attached`.
    machine.attachHook = (id) => handle.emit(const TabOutput('missed while away'));
    machine.reuseHandles = true;
    await tab.reattach();
    expect(screen(), 'missed while away');
  });

  test('reattach to a vanished session ends the tab', () async {
    handle.emit(const TabDetached(DetachReason.takenOver));
    machine.attachErrors[handle.id] = const AppErrorException(AppErrorCode.sessionNotFound, 'gone');
    await tab.reattach();
    expect(tab.banner.value?.notice, TabNotice.sessionEnded);
  });

  // Ruling (Task 12, binding over the brief): `MachineClient.attach()` throws
  // `MachineConnectionException` (e.g. `agentOffline`, `timeout`) at once when
  // there is no channel — this is not `AppErrorException(sessionNotFound)`, so
  // `reattach()` must leave the controller exactly as it was and rethrow, for
  // Task 14's "Gắn lại" button to show it through the usual `ErrorText`
  // mapping (the same one `error_text.dart` already gives
  // `MachineConnectionException`).
  test('reattach failing with MachineConnectionException rethrows, leaves the tab as it was, '
      'and a later reattach still works', () async {
    handle.emit(const TabOutput('before '));
    handle.emit(const TabDetached(DetachReason.takenOver));
    final bannerBefore = tab.banner.value?.notice;
    final screenBefore = screen();
    final terminalBefore = tab.terminal.value;

    machine.attachErrors[handle.id] = const MachineConnectionException(MachineConnectionFailure.agentOffline);

    await expectLater(tab.reattach(), throwsA(isA<MachineConnectionException>()));

    // Untouched: same banner, not live, same screen and terminal instance.
    expect(tab.banner.value?.notice, bannerBefore);
    expect(tab.isLive.value, isFalse);
    expect(screen(), screenBefore);
    expect(tab.terminal.value, same(terminalBefore));
    // The subscription is unchanged: the original handle still delivers events.
    handle.emit(const TabOutput('still listening'));
    expect(screen(), '$screenBefore still listening');

    // A later reattach (the failure lifted) still succeeds.
    machine.attachErrors.remove(handle.id);
    await tab.reattach();

    expect(tab.banner.value, isNull);
    expect(tab.isLive.value, isTrue);
  });

  // Ruling (Task 12): with the real client's behaviour (re-attaching an
  // existing tab returns the *same* `TabHandle`), the controller must not
  // subscribe a second time — that would write every later event twice — and
  // the catch-up output the attach replays before returning must be written
  // exactly once.
  test('reattach with the real reuseHandles behaviour does not subscribe twice; '
      'catch-up output is written once', () async {
    handle.emit(const TabOutput('before '));
    handle.emit(const TabDetached(DetachReason.takenOver));
    machine.reuseHandles = true;
    machine.attachHook = (id) => handle.emit(const TabOutput('missed'));

    await tab.reattach();

    expect(tab.isLive.value, isTrue);
    expect(screen(), 'before missed');

    // If the controller had listened twice, this would show up twice.
    handle.emit(const TabOutput(' more'));
    expect(screen(), 'before missed more');
  });

  test('an ended placeholder tab is not live and drops input', () {
    final ended = TerminalTabController.ended(
      machine: machine,
      session: const SessionInfo(id: 7, index: 3, shell: 'bash', createdAt: 0, attached: false),
      modifiers: keys,
    );
    addTearDown(ended.dispose);
    expect(ended.banner.value?.notice, TabNotice.sessionEnded);
    expect(ended.title.value, 'bash 3');
    ended.terminal.value.textInput('x');
    expect(machine.inputs, isEmpty);
  });

  group('desktop terminal (terminal sharing §9.2)', () {
    const window = SessionInfo(
      id: 40,
      index: 1,
      shell: 'zsh',
      createdAt: 0,
      attached: false,
      kind: SessionKind.desktop,
      app: 'Terminal',
      title: '~/projects/api',
    );
    late FakeTabHandle desktopHandle;
    late TerminalTabController desktop;

    setUp(() async {
      machine.sessions = [window];
      desktopHandle = await machine.attach(window.id, cols: 80, rows: 24) as FakeTabHandle;
      machine.attached.clear();
      desktop = TerminalTabController(machine: machine, handle: desktopHandle, modifiers: keys, cols: 80, rows: 24);
    });

    tearDown(() => desktop.dispose());

    test('is a desktop tab labelled with the window title, else the app, else "<shell> <index>"', () async {
      expect(desktop.isDesktop, isTrue);
      expect(tab.isDesktop, isFalse);
      expect(desktop.title.value, '~/projects/api');

      machine.sessions = [
        const SessionInfo(
          id: 41,
          index: 2,
          shell: 'zsh',
          createdAt: 0,
          attached: false,
          kind: SessionKind.desktop,
          app: 'iTerm2',
        ),
        const SessionInfo(id: 42, index: 3, shell: 'bash', createdAt: 0, attached: false, kind: SessionKind.desktop),
      ];
      final appOnly = TerminalTabController(
        machine: machine,
        handle: await machine.attach(41, cols: 80, rows: 24),
        modifiers: keys,
        cols: 80,
        rows: 24,
      );
      final bare = TerminalTabController(
        machine: machine,
        handle: await machine.attach(42, cols: 80, rows: 24),
        modifiers: keys,
        cols: 80,
        rows: 24,
      );
      addTearDown(appOnly.dispose);
      addTearDown(bare.dispose);
      expect(appOnly.title.value, 'iTerm2');
      expect(bare.title.value, 'bash 3');

      // A title the program sets later still wins, as on a ShellX tab.
      desktopHandle.emit(const TabOutput('\x1b]2;vim notes.md\x07'));
      expect(desktop.title.value, 'vim notes.md');
    });

    test('the phone drives after attaching; session.driver moves the banner both ways', () {
      // Ledger "Ghi cho P5": a phone that takes over at the same size gets no session.driver.
      expect(desktop.driver.value, DriverSide.phone);
      expect(desktop.showDriverBanner.value, isFalse);

      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      expect(desktop.showDriverBanner.value, isTrue);

      desktopHandle.emit(const TabDriver(DriverSide.phone));
      expect(desktop.showDriverBanner.value, isFalse);
    });

    test('a ShellX tab never shows the banner', () {
      handle.emit(const TabDriver(DriverSide.desktop));
      expect(tab.showDriverBanner.value, isFalse);
    });

    test('claimSize sends the phone size, even unchanged, only while the computer drives', () {
      desktop.claimSize();
      expect(machine.resizes, isEmpty);

      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      desktop.claimSize();
      expect(machine.resizes, [(id: 40, cols: 80, rows: 24)]);
      // The banner stays until the agent confirms.
      expect(desktop.showDriverBanner.value, isTrue);
    });

    test('typing while the computer drives sends the size once, then the keys', () {
      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      desktop.terminal.value.textInput('l');
      desktop.terminal.value.textInput('s');
      expect(machine.resizes, [(id: 40, cols: 80, rows: 24)]);
      expect(machine.inputs.map((i) => utf8.decode(i.data)), ['l', 's']);

      // The computer takes it back again: the next keystroke claims again.
      desktopHandle.emit(const TabDriver(DriverSide.phone));
      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      desktop.terminal.value.textInput('x');
      expect(machine.resizes, hasLength(2));
    });

    test('the banner appearing changes the grid but sends nothing and does not claim', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        // The driver banner takes a row of the chrome: the view loses a row. No size intent.
        desktop.terminal.value.resize(80, 23);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, isEmpty);
        expect(desktop.showDriverBanner.value, isTrue);
      });
    });

    test('the banner going away with the session (exit) sends nothing', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        desktopHandle.emit(const TabExited(0));
        desktop.terminal.value.resize(80, 25);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, isEmpty);
      });
    });

    test('a remount after session.reset while the computer drives sends nothing', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        desktopHandle.emit(const TabReset());
        desktop.terminal.value.resize(80, 23); // the new view lays out under the banner
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, isEmpty);
      });
    });

    test('a size intent (rotation, keyboard, font size) while the computer drives claims the size', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        desktop.terminal.value.resize(80, 23); // the banner's own row
        async.elapse(const Duration(seconds: 1));
        desktop.noteSizeIntent();
        desktop.terminal.value.resize(120, 18); // landscape
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, [(id: 40, cols: 120, rows: 18)]);
        // One intent, one send: a later grid change without intent is not sent.
        desktop.terminal.value.resize(120, 17);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, hasLength(1));
      });
    });

    test('a rotation still pending when the computer takes the size goes out', () {
      fakeAsync((async) {
        desktop.noteSizeIntent();
        desktop.terminal.value.resize(120, 18);
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, [(id: 40, cols: 120, rows: 18)]);
      });
    });

    test('while the phone drives, every grid change is sent as before', () {
      fakeAsync((async) {
        desktop.terminal.value.resize(90, 20);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, [(id: 40, cols: 90, rows: 20)]);
      });
    });

    test('a size the view took after the claim is sent when the phone gets the size back', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        async.elapse(const Duration(seconds: 1));
        desktop.claimSize();
        expect(machine.resizes, [(id: 40, cols: 80, rows: 24)]);
        desktop.terminal.value.resize(100, 30);
        // The agent confirms before the debounced resize goes out; no further layout follows.
        desktopHandle.emit(const TabDriver(DriverSide.phone));
        expect(machine.resizes, [(id: 40, cols: 80, rows: 24), (id: 40, cols: 100, rows: 30)]);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, hasLength(2));
      });
    });

    test('the banner going away gives the row back, and that size is sent', () {
      fakeAsync((async) {
        desktopHandle.emit(const TabDriver(DriverSide.desktop));
        desktop.terminal.value.resize(80, 23);
        async.elapse(const Duration(seconds: 1));
        desktop.claimSize();
        desktopHandle.emit(const TabDriver(DriverSide.phone));
        desktop.terminal.value.resize(80, 24);
        async.elapse(const Duration(seconds: 1));
        expect(machine.resizes, [(id: 40, cols: 80, rows: 23), (id: 40, cols: 80, rows: 24)]);
      });
    });

    test('typing while the phone drives sends no resize', () {
      desktop.terminal.value.textInput('ls');
      expect(machine.resizes, isEmpty);
    });

    test('session.exited: the window was closed; nothing to reattach', () {
      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      desktopHandle.emit(const TabExited(0));
      expect(desktop.banner.value?.notice, TabNotice.desktopClosed);
      expect(desktop.canReattach, isFalse);
      expect(desktop.showDriverBanner.value, isFalse);
    });

    test('terminal_gone: lost the terminal; nothing to reattach (not "closed by the host")', () {
      desktopHandle.emit(const TabDetached(DetachReason.terminalGone));
      expect(desktop.banner.value?.notice, TabNotice.terminalGone);
      expect(desktop.canReattach, isFalse);
    });

    test('session_not_found on a desktop tab is the lost-terminal card too', () {
      desktopHandle.emit(const TabError(AppErrorCode.sessionNotFound, 'gone'));
      expect(desktop.banner.value?.notice, TabNotice.terminalGone);
    });

    test('closed_by_host: the terminal keeps running; "Gắn lại" attaches again and the phone drives', () async {
      machine.reuseHandles = true;
      desktopHandle.emit(const TabDriver(DriverSide.desktop));
      desktopHandle.emit(const TabDetached(DetachReason.closedByHost));
      expect(desktop.banner.value?.notice, TabNotice.closedByHost);
      expect(desktop.canReattach, isTrue);

      await desktop.reattach();

      expect(machine.attached.single.id, 40);
      expect(desktop.banner.value, isNull);
      expect(desktop.driver.value, DriverSide.phone);
    });

    test('a ShellX tab closed by the host cannot be reattached', () async {
      handle.emit(const TabDetached(DetachReason.closedByHost));
      expect(tab.canReattach, isFalse);
      await tab.reattach();
      expect(machine.attached, isEmpty);
    });

    test('an ended placeholder of a vanished desktop terminal shows the lost-terminal card', () {
      final ended = TerminalTabController.ended(machine: machine, session: window, modifiers: keys);
      addTearDown(ended.dispose);
      expect(ended.isDesktop, isTrue);
      expect(ended.banner.value?.notice, TabNotice.terminalGone);
      expect(ended.title.value, '~/projects/api');
    });
  });
}
