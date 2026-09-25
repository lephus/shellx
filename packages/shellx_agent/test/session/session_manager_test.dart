import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

void main() {
  test(
    'open spawns the shell in the home directory with the session env',
    () async {
      final rig = SessionRig();
      await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

      final opened = rig.to(phone).single as SessionOpened;
      expect((opened.index, opened.shell), (1, 'zsh'));
      expect(rig.manager.sessions.single.id, opened.id);
      final pty = rig.pty(0);
      expect(pty.command.executable, '/bin/zsh');
      expect(pty.command.arguments, ['-l']);
      expect(pty.workingDirectory, '/Users/test');
      expect(pty.environment['PATH'], '/usr/bin');
      expect(pty.environment['TERM'], 'xterm-256color');
      expect(pty.environment['SHELLX'], '1');
      expect((pty.initialCols, pty.initialRows), (80, 24));
      expect(rig.manager.sessions.single.attachedMobileId, phone);
    },
  );

  test('open clamps zero and huge terminal sizes into [1, 1000]', () async {
    final rig = SessionRig();
    await rig.open(phone, cols: 0, rows: -3);
    await rig.open(phone, cols: 5000, rows: 100000);
    expect((rig.pty(0).initialCols, rig.pty(0).initialRows), (1, 1));
    expect((rig.pty(1).initialCols, rig.pty(1).initialRows), (1000, 1000));
  });

  test('output is sent in chunks of at most 16 KiB numbered by byte', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.clear();
    rig.pty(0).emitBytes(List.filled(40 * 1024, 0x61));
    await pumpEventQueue();

    final outputs = rig.to(phone).whereType<OutputMessage>().toList();
    expect(
      [for (final o in outputs) (o.id, o.seq, o.data.length)],
      [(id, 0, 16384), (id, 16384, 16384), (id, 32768, 8192)],
    );
  });

  test('the 11th session is refused with session_limit', () async {
    final rig = SessionRig();
    for (var i = 0; i < 10; i++) {
      await rig.open(phone);
    }
    rig.clear();
    await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

    final error = rig.to(phone).single as ErrorMessage;
    expect(error.code, AppErrorCode.sessionLimit);
    expect(error.id, isNull);
    expect(rig.manager.sessions, hasLength(10));
  });

  test('a spawn failure answers spawn_failed and creates no session', () async {
    final rig = SessionRig();
    rig.factory.failWith = StateError('no pty');
    await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

    final error = rig.to(phone).single as ErrorMessage;
    expect(error.code, AppErrorCode.spawnFailed);
    expect(error.message, contains('no pty'));
    expect(rig.manager.sessions, isEmpty);
  });

  test('closeAll racing a pending open kills the new pty instead of leaking a '
      'session behind it', () async {
    final rig = SessionRig();
    // The shell resolver's `resolve()` always suspends at least once
    // (`async` with no synchronous return), so nothing is registered yet
    // when this call returns control here.
    final openFuture = rig.manager.handle(
      phone,
      const SessionOpen(cols: 80, rows: 24),
    );
    rig.manager.closeAll();
    await openFuture;
    await pumpEventQueue();

    expect(rig.manager.sessions, isEmpty);
    expect(rig.factory.ptys.single.killed, isTrue);
    expect(rig.sent, isEmpty);
  });

  test('ids start at a random value in [1, 2^31) and increase by one; '
      'indexes reuse the lowest free number', () async {
    final rig = SessionRig();
    final first = await rig.open(phone);
    await rig.open(phone);
    rig.pty(0).exit(0);
    await pumpEventQueue();
    await rig.open(phone);

    expect(first, inInclusiveRange(1, (1 << 31) - 1));
    final opened = rig.to(phone).whereType<SessionOpened>().toList();
    expect(
      [for (final o in opened) (o.id, o.index)],
      [(first, 1), (first + 1, 2), (first + 2, 1)],
    );
  });

  test('each manager instance picks its own starting id', () async {
    final a = SessionRig(random: Random(1));
    final b = SessionRig(random: Random(2));
    expect(await a.open(phone), isNot(await b.open(phone)));

    // Without an injected Random the manager uses Random.secure().
    final manager = SessionManager(
      ptyFactory: FakePtyFactory(),
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    final sent = <OutboundMessage>[];
    manager.outbound.listen(sent.add);
    await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
    expect(
      (sent.single.message as SessionOpened).id,
      inInclusiveRange(1, (1 << 31) - 1),
    );
  });

  test(
    'session.list reports every session and whether it is attached',
    () async {
      final rig = SessionRig();
      final first = await rig.open(phone);
      final second = await rig.open(phone);
      rig.manager.mobileDisconnected(phone);
      await rig.manager.handle(
        tablet,
        SessionAttach(id: second, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.clear();
      await rig.manager.handle(tablet, const SessionList());

      final result = rig.to(tablet).single as SessionListResult;
      expect(
        [for (final s in result.sessions) (s.id, s.index, s.shell, s.attached)],
        [(first, 1, 'zsh', false), (second, 2, 'zsh', true)],
      );
      expect(result.sessions.first.createdAt, greaterThan(0));
    },
  );

  test(
    'input and resize only come from the attached phone; sizes are clamped',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      final data = Uint8List.fromList(utf8.encode('ls\r'));
      await rig.manager.handle(phone, InputMessage(id: id, data: data));
      await rig.manager.handle(tablet, InputMessage(id: id, data: data));
      await rig.manager.handle(
        phone,
        ResizeMessage(id: id, cols: 100, rows: 30),
      );
      await rig.manager.handle(
        phone,
        ResizeMessage(id: id, cols: 0, rows: 5000),
      );
      await rig.manager.handle(
        tablet,
        ResizeMessage(id: id, cols: 50, rows: 50),
      );

      expect(rig.pty(0).writtenText, 'ls\r');
      expect(rig.pty(0).resizes, [(100, 30), (1, 1000)]);
    },
  );

  test('shell exit sends session.exited and removes the session', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.pty(0).emit('bye\r\n');
    rig.pty(0).exit(7);
    await pumpEventQueue();

    final messages = rig.to(phone);
    expect(outputText(messages, id), 'bye\r\n');
    expect(messages.last, isA<SessionExited>());
    expect((messages.last as SessionExited).exitCode, 7);
    expect(rig.manager.sessions, isEmpty);
  });

  test('shell exit drains a send-window-blocked tail before session.exited '
      'instead of dropping it', () async {
    final rig = SessionRig(bufferCapacity: 1024 * 1024);
    final id = await rig.open(phone);
    rig.clear();
    rig.pty(0).emitBytes(List.filled(300 * 1024, 0x61));
    rig.pty(0).exit(0);
    await pumpEventQueue();

    // The shell has already exited, but 300 KiB - 256 KiB = 44 KiB is
    // still blocked by the default send window: session.exited must not
    // jump the queue and the tail must not be dropped.
    expect(outputBytes(rig.to(phone), id), 256 * 1024);
    expect(rig.to(phone).whereType<SessionExited>(), isEmpty);

    await rig.manager.handle(phone, AckMessage(id: id, seq: 256 * 1024));
    await pumpEventQueue();

    final messages = rig.to(phone);
    expect(outputBytes(messages, id), 300 * 1024);
    expect(messages.last, isA<SessionExited>());
    expect((messages.last as SessionExited).exitCode, 0);
    expect(rig.manager.sessions, isEmpty);
  });

  test('a draining session gives up after 30s and delivers session.exited '
      'even if the phone never finishes acking', () {
    fakeAsync((async) {
      final rig = SessionRig(bufferCapacity: 1024 * 1024);
      rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      final id = rig.to(phone).whereType<SessionOpened>().last.id;
      rig.clear();

      rig.pty(0).emitBytes(List.filled(300 * 1024, 0x61));
      rig.pty(0).exit(0);
      async.flushMicrotasks();
      expect(outputBytes(rig.to(phone), id), 256 * 1024);
      expect(rig.manager.sessions, isEmpty); // hidden from listing while
      // draining (spec item 4): it's still tracked internally, though.

      // No further ack ever arrives: nothing at 29 s, exited at 30 s.
      async.elapse(const Duration(seconds: 29));
      expect(rig.to(phone).whereType<SessionExited>(), isEmpty);
      async.elapse(const Duration(seconds: 1));

      final messages = rig.to(phone);
      expect(messages.last, isA<SessionExited>());
      expect((messages.last as SessionExited).exitCode, 0);
    });
  });

  test('a draining session finishes immediately if the phone disconnects, '
      'without waiting for the drain timeout', () {
    fakeAsync((async) {
      final rig = SessionRig(bufferCapacity: 1024 * 1024);
      rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      final id = rig.to(phone).whereType<SessionOpened>().last.id;
      rig.clear();

      rig.pty(0).emitBytes(List.filled(300 * 1024, 0x61));
      rig.pty(0).exit(0);
      async.flushMicrotasks();
      expect(outputBytes(rig.to(phone), id), 256 * 1024);

      rig.manager.mobileDisconnected(phone);
      expect(rig.manager.sessions, isEmpty);
      expect(async.pendingTimers, isEmpty); // The 30 s drain timer is gone.

      // Elapsing well past it sends nothing more (there is no attached
      // phone to send to).
      rig.clear();
      async.elapse(const Duration(seconds: 40));
      expect(rig.sent, isEmpty);
    });
  });

  test(
    'session.close kills the shell; an unknown id answers session_not_found',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      await rig.manager.handle(phone, SessionClose(id: id));
      await pumpEventQueue();
      await rig.manager.handle(phone, SessionClose(id: id + 1));

      expect(rig.pty(0).killed, isTrue);
      final messages = rig.to(phone);
      expect(messages[messages.length - 2], isA<SessionExited>());
      final error = messages.last as ErrorMessage;
      expect((error.code, error.id), (AppErrorCode.sessionNotFound, id + 1));
    },
  );

  test(
    'closeSession from the tray sends detached(closed_by_host) then exited',
    () async {
      final rig = SessionRig();
      final id = await rig.open(phone);
      rig.clear();
      rig.manager.closeSession(id);
      await pumpEventQueue();

      final messages = rig.to(phone);
      expect(messages, hasLength(2));
      final detached = messages[0] as SessionDetached;
      expect((detached.id, detached.reason), (id, DetachReason.closedByHost));
      final exited = messages[1] as SessionExited;
      expect((exited.id, exited.exitCode), (id, FakePty.killExitCode));
      expect(rig.manager.sessions, isEmpty);
    },
  );

  test('closeAll closes every session', () async {
    final rig = SessionRig();
    await rig.open(phone);
    await rig.open(tablet);
    rig.manager.closeAll();
    await pumpEventQueue();
    expect(rig.factory.ptys.every((p) => p.killed), isTrue);
    expect(rig.manager.sessions, isEmpty);
  });

  // Final review I1: once the shell has exited its pid may be reused, so
  // the manager never kills, writes to or resizes that pty again.
  test('a draining session (shell exited) is never killed, written to or '
      'resized; acks still drain it', () async {
    final rig = SessionRig(bufferCapacity: 1024 * 1024);
    final id = await rig.open(phone);
    rig.clear();
    rig.pty(0).emitBytes(List.filled(300 * 1024, 0x61));
    rig.pty(0).exit(0);
    await pumpEventQueue();
    expect(outputBytes(rig.to(phone), id), 256 * 1024); // Draining.

    await rig.manager.handle(
      phone,
      InputMessage(id: id, data: Uint8List.fromList(utf8.encode('ls\r'))),
    );
    await rig.manager.handle(phone, ResizeMessage(id: id, cols: 100, rows: 30));
    await rig.manager.handle(phone, SessionClose(id: id));
    rig.manager.closeSessionsAttachedTo(phone);
    expect(rig.pty(0).killed, isFalse);
    expect(rig.pty(0).writes, isEmpty);
    expect(rig.pty(0).resizes, isEmpty);

    await rig.manager.handle(phone, AckMessage(id: id, seq: 256 * 1024));
    await pumpEventQueue();
    final messages = rig.to(phone);
    expect(outputBytes(messages, id), 300 * 1024);
    expect((messages.last as SessionExited).exitCode, 0);
    expect(rig.manager.sessions, isEmpty);
  });

  test('while the output of an exited shell drains, a tray close, closeAll '
      'and an attach never kill or resize its pty', () async {
    final rig = SessionRig();
    final first = await rig.open(phone);
    final second = await rig.open(phone);
    rig.pty(0).exit(0, closeOutput: false);
    rig.pty(1).exit(5, closeOutput: false);
    await pumpEventQueue();
    rig.clear();

    // Exit codes known, output still open (the 2 s output grace).
    await rig.manager.handle(
      phone,
      SessionAttach(id: first, cols: 80, rows: 24, lastSeq: 0),
    );
    await rig.manager.handle(
      phone,
      InputMessage(id: first, data: Uint8List.fromList(utf8.encode('x'))),
    );
    rig.manager.closeSession(first);
    rig.manager.closeAll();
    expect(rig.pty(0).killed, isFalse);
    expect(rig.pty(1).killed, isFalse);
    expect(rig.pty(0).resizes, isEmpty);
    expect(rig.pty(0).writes, isEmpty);

    rig.pty(0).closeOutputStream();
    rig.pty(1).closeOutputStream();
    await pumpEventQueue();
    final exits = {
      for (final e in rig.to(phone).whereType<SessionExited>())
        e.id: e.exitCode,
    };
    expect(exits, {first: 0, second: 5});
    expect(rig.manager.sessions, isEmpty);
  });

  test('sessions keep running and buffering with no phone attached', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    rig.clear();
    rig.pty(0).emit('still here');
    await pumpEventQueue();

    expect(rig.sent, isEmpty);
    expect(rig.manager.sessions.single.id, id);
    expect(rig.manager.sessions.single.attachedMobileId, isNull);
  });

  test('changes and opened streams report activity', () async {
    final rig = SessionRig();
    var changes = 0;
    final opened = <SessionOpenedEvent>[];
    rig.manager.changes.listen((_) => changes++);
    rig.manager.opened.listen(opened.add);
    final id = await rig.open(phone);
    rig.pty(0).exit(0);
    await pumpEventQueue();

    expect([for (final e in opened) (e.mobileId, e.sessionId)], [(phone, id)]);
    expect(changes, 2);
  });
}
