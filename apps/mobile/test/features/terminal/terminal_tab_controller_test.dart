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
}
