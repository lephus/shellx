import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

const String esc = '\x1b';
const String bel = '\x07';

void main() {
  test('the default limit is 32 sessions (D8)', () async {
    final factory = FakePtyFactory();
    final manager = SessionManager(
      ptyFactory: factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    for (var i = 0; i < 32; i++) {
      await manager.open(cols: 80, rows: 24);
    }
    await expectLater(
      manager.open(cols: 80, rows: 24),
      throwsA(isA<SessionLimitException>().having((e) => e.max, 'max', 32)),
    );
    expect(manager.sessions, hasLength(32));
  });

  test(
    'a phone-opened session has origin phone and the phone drives',
    () async {
      final rig = SessionRig();
      await rig.open(phone);
      final summary = rig.manager.sessions.single;
      expect(summary.origin, SessionOrigin.phone);
      expect(summary.driver, DriverSide.phone);
      expect(summary.phoneAttached, isTrue);
      expect(summary.title, '');
      expect(summary.runningCommand, isFalse);
    },
  );

  test('open() starts a desktop session nobody is attached to', () async {
    final rig = SessionRig();
    var changes = 0;
    var opened = 0;
    rig.manager.changes.listen((_) => changes++);
    rig.manager.opened.listen((_) => opened++);

    final id = await rig.manager.open(cols: 120, rows: 40);
    await pumpEventQueue();

    final summary = rig.manager.sessions.single;
    expect(summary.id, id);
    expect(summary.index, 1);
    expect(summary.origin, SessionOrigin.desktop);
    expect(summary.driver, DriverSide.desktop);
    expect(summary.attachedMobileId, isNull);
    expect((rig.pty(0).initialCols, rig.pty(0).initialRows), (120, 40));
    expect(rig.pty(0).workingDirectory, '/Users/test');
    expect(changes, greaterThan(0));
    expect(opened, 0); // Only phones produce "<phone> opened a session".
    expect(rig.sent, isEmpty);
    // Listed to phones like any shellx session (D3).
    expect(rig.manager.sessionInfos.single.kind, SessionKind.shellx);
  });

  test('open() reports a spawn failure as SpawnFailedException', () async {
    final rig = SessionRig();
    rig.factory.failWith = StateError('no pty');
    await expectLater(
      rig.manager.open(cols: 80, rows: 24),
      throwsA(
        isA<SpawnFailedException>().having(
          (e) => e.message,
          'message',
          contains('no pty'),
        ),
      ),
    );
    expect(rig.manager.sessions, isEmpty);
  });

  test(
    'OSC 0 and OSC 2 titles are tracked for shellx sessions (D13)',
    () async {
      final rig = SessionRig();
      await rig.manager.open(cols: 80, rows: 24);
      var changes = 0;
      rig.manager.changes.listen((_) => changes++);

      rig.pty(0).emit('$esc]0;vim notes.md$bel');
      await pumpEventQueue();
      expect(rig.manager.sessions.single.title, 'vim notes.md');
      expect(changes, 1);

      rig.pty(0).emit('$esc]2;htop$esc\\');
      await pumpEventQueue();
      expect(rig.manager.sessions.single.title, 'htop');

      rig.pty(0).emit('plain output');
      await pumpEventQueue();
      expect(changes, 2); // No change event for output without a new title.
    },
  );

  test('runningCommand is true between OSC 133;C and 133;D (D15)', () async {
    final rig = SessionRig();
    await rig.manager.open(cols: 80, rows: 24);
    expect(rig.manager.sessions.single.runningCommand, isFalse);

    rig.pty(0).emit('$esc]133;C$bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.runningCommand, isTrue);

    rig.pty(0).emit('$esc]133;D;0$bel');
    await pumpEventQueue();
    expect(rig.manager.sessions.single.runningCommand, isFalse);
  });

  group('phones and desktop-origin sessions (D4)', () {
    test('session.close from the phone detaches, never kills', () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
      );
      rig.clear();

      await rig.manager.handle(phone, SessionClose(id: id));

      expect(rig.pty(0).killed, isFalse);
      expect(rig.to(phone), [
        SessionDetached(id: id, reason: DetachReason.closedByHost),
      ]);
      expect(rig.manager.sessions.single.attachedMobileId, isNull);
    });

    test(
      'session.close from a phone that is not attached does nothing',
      () async {
        final rig = SessionRig();
        final id = await rig.manager.open(cols: 80, rows: 24);
        await rig.manager.handle(tablet, SessionClose(id: id));
        expect(rig.pty(0).killed, isFalse);
        expect(rig.to(tablet), isEmpty);
      },
    );

    test(
      'session.close on a session the phone opened still kills it',
      () async {
        final rig = SessionRig();
        final id = await rig.open(phone);
        await rig.manager.handle(phone, SessionClose(id: id));
        expect(rig.pty(0).killed, isTrue);
      },
    );

    test('revoke kills what the phone opened, only detaches desktop-origin '
        'sessions', () async {
      final rig = SessionRig();
      final mine = await rig.manager.open(cols: 80, rows: 24);
      await rig.open(phone);
      await rig.manager.handle(
        phone,
        SessionAttach(id: mine, cols: 50, rows: 20, lastSeq: 0),
      );
      rig.clear();

      rig.manager.closeSessionsAttachedTo(phone);
      await pumpEventQueue();

      expect(rig.pty(0).killed, isFalse);
      expect(rig.pty(1).killed, isTrue);
      expect(
        rig.to(phone),
        contains(SessionDetached(id: mine, reason: DetachReason.closedByHost)),
      );
    });

    test('a revoke never voids a desktop open still spawning', () async {
      final rig = SessionRig();
      final opening = rig.manager.open(cols: 80, rows: 24);
      rig.manager.closeSessionsAttachedTo(phone);
      await opening;
      expect(rig.pty(0).killed, isFalse);
      expect(rig.manager.sessions, hasLength(1));
    });

    test('closeAll voids a desktop open still spawning', () async {
      final rig = SessionRig();
      final opening = rig.manager.open(cols: 80, rows: 24);
      rig.manager.closeAll();
      await expectLater(opening, throwsA(isA<SpawnFailedException>()));
      expect(rig.pty(0).killed, isTrue);
      expect(rig.manager.sessions, isEmpty);
    });
  });

  group('driver (D6)', () {
    test('attaching makes the phone the driver; session.driver goes only to '
        'phones that listed with desktop: true', () async {
      final rig = SessionRig();
      rig.manager.receivesDriver = {phone}.contains;
      final a = await rig.manager.open(cols: 100, rows: 30);
      final b = await rig.manager.open(cols: 100, rows: 30);

      await rig.manager.handle(
        phone,
        SessionAttach(id: a, cols: 50, rows: 20, lastSeq: 0),
      );
      await rig.manager.handle(
        tablet,
        SessionAttach(id: b, cols: 60, rows: 20, lastSeq: 0),
      );

      expect(
        rig.to(phone),
        contains(SessionDriver(id: a, by: DriverSide.phone)),
      );
      expect(rig.to(tablet).whereType<SessionDriver>(), isEmpty);
      expect(rig.manager.sessions.first.driver, DriverSide.phone);
      expect(rig.pty(0).resizes.last, (50, 20));
    });

    test(
      'when the phone leaves, the desktop drives at its own size again',
      () async {
        final rig = SessionRig();
        final id = await rig.manager.open(cols: 100, rows: 30);
        await rig.manager.handle(
          phone,
          SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
        );
        expect(rig.pty(0).resizes.last, (50, 20));

        rig.manager.mobileDisconnected(phone);

        expect(rig.manager.sessions.single.driver, DriverSide.desktop);
        expect(rig.pty(0).resizes.last, (100, 30));
      },
    );

    test('a phone-origin session nobody resized locally keeps its size when '
        'the phone leaves', () async {
      final rig = SessionRig();
      await rig.open(phone, cols: 50, rows: 20);
      rig.manager.mobileDisconnected(phone);
      expect(rig.manager.sessions.single.driver, DriverSide.desktop);
      expect(rig.pty(0).resizes, isEmpty);
    });
  });

  test(
    'disconnectAllPhones detaches every phone and kills nothing (D7)',
    () async {
      final rig = SessionRig();
      final mine = await rig.manager.open(cols: 80, rows: 24);
      final theirs = await rig.open(phone);
      await rig.manager.handle(
        tablet,
        SessionAttach(id: mine, cols: 50, rows: 20, lastSeq: 0),
      );
      rig.clear();

      rig.manager.disconnectAllPhones();

      expect(rig.pty(0).killed, isFalse);
      expect(rig.pty(1).killed, isFalse);
      expect(rig.to(phone), [
        SessionDetached(id: theirs, reason: DetachReason.closedByHost),
      ]);
      expect(rig.to(tablet), [
        SessionDetached(id: mine, reason: DetachReason.closedByHost),
      ]);
      expect(
        rig.manager.sessions.map((s) => s.attachedMobileId),
        everyElement(isNull),
      );
      // Output keeps buffering for whoever attaches next; nobody is sent it.
      rig.pty(0).emitBytes(utf8.encode('still here'));
      await pumpEventQueue();
      expect(rig.sent, hasLength(2));
    },
  );

  test('SessionSummary.phoneAttached follows attachedMobileId', () {
    final summary = SessionSummary(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: DateTime(2026),
      attachedMobileId: null,
    );
    expect(summary.phoneAttached, isFalse);
    expect(summary.origin, SessionOrigin.phone);
  });
}
