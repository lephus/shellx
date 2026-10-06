import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// Collects a view's live output as text.
final class _Collected {
  _Collected(LocalSessionView view) {
    view.output.listen(
      (data) => text.write(utf8.decode(data)),
      onDone: () => done = true,
    );
  }
  final text = StringBuffer();
  bool done = false;
}

void main() {
  test('a SessionManager is a LocalSessions', () {
    final rig = SessionRig();
    expect(rig.manager, isA<LocalSessions>());
  });

  test('view: backlog first, then live output, no ack needed', () async {
    final rig = SessionRig(sendWindow: 4);
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('hello ');
    await pumpEventQueue();

    final view = rig.manager.view(id);
    expect(utf8.decode(view.backlog), 'hello ');
    final live = _Collected(view);
    rig.pty(0).emit('world, more than the send window');
    await pumpEventQueue();

    expect(live.text.toString(), 'world, more than the send window');
  });

  test('output emitted between view() and listen is not lost', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    rig.pty(0).emit('early');
    await pumpEventQueue();
    final live = _Collected(view);
    await pumpEventQueue();
    expect(live.text.toString(), 'early');
  });

  test('the backlog is capped at the ring buffer size', () async {
    final rig = SessionRig(bufferCapacity: 16);
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('0123456789abcdefXYZ');
    await pumpEventQueue();
    expect(utf8.decode(rig.manager.view(id).backlog), '3456789abcdefXYZ');
  });

  test('view of an unknown session throws StateError', () {
    final rig = SessionRig();
    expect(() => rig.manager.view(42), throwsStateError);
  });

  test('write reaches the shell; resize resizes the PTY', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    view.write(_b('ls\r'));
    view.resize(120, 40);
    view.resize(120, 40); // same size: no second resize
    expect(rig.pty(0).writtenText, 'ls\r');
    expect(rig.pty(0).resizes, [(120, 40)]);
    expect(rig.manager.sessions.single.driver, DriverSide.desktop);
  });

  test('open() is limited like phone opens (D8)', () async {
    final rig = SessionRig(maxSessions: 2);
    await rig.manager.open(cols: 80, rows: 24);
    await rig.open(phone);
    await expectLater(
      rig.manager.open(cols: 80, rows: 24),
      throwsA(isA<SessionLimitException>().having((e) => e.max, 'max', 2)),
    );
  });

  group('a phone and the window on the same session (D5, D6)', () {
    late SessionRig rig;
    late int id;
    late LocalSessionView view;
    late List<DriverSide> drivers;
    late _Collected live;

    setUp(() async {
      rig = SessionRig();
      rig.manager.receivesDriver = {phone}.contains;
      id = await rig.manager.open(cols: 100, rows: 30);
      view = rig.manager.view(id);
      drivers = [];
      view.driver.listen(drivers.add);
      live = _Collected(view);
      await rig.manager.handle(
        phone,
        SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
      );
    });

    test('nobody is kicked out and both see the output', () async {
      rig.pty(0).emit('shared');
      await pumpEventQueue();
      expect(live.text.toString(), 'shared');
      expect(outputText(rig.to(phone), id), 'shared');
      expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
      expect(rig.manager.sessions.single.attachedMobileId, phone);
      expect(drivers, [DriverSide.phone]);
    });

    test('the window typing after the hold takes the driver back', () async {
      rig.now = rig.now.add(const Duration(seconds: 5));
      rig.clear();
      view.write(_b('x'));
      expect(drivers, [DriverSide.phone, DriverSide.desktop]);
      expect(rig.pty(0).resizes.last, (100, 30));
      expect(
        rig.to(phone),
        contains(SessionDriver(id: id, by: DriverSide.desktop)),
      );
      expect(rig.pty(0).writtenText, 'x');
    });

    test('interleaved typing from both sides reaches the shell in order '
        'without resizing on every key', () async {
      rig.now = rig.now.add(const Duration(seconds: 5));
      view.write(_b('a')); // desktop takes the driver (phone idle 5 s)
      final resizesAfterTakeover = rig.pty(0).resizes.length;
      for (final key in ['b', 'c', 'd', 'e', 'f', 'g']) {
        rig.now = rig.now.add(const Duration(milliseconds: 100));
        if (key.codeUnitAt(0).isEven) {
          await rig.manager.handle(phone, InputMessage(id: id, data: _b(key)));
        } else {
          view.write(_b(key));
        }
      }
      expect(rig.pty(0).writtenText, 'abcdefg');
      expect(rig.pty(0).resizes.length, resizesAfterTakeover);
      expect(rig.manager.sessions.single.driver, DriverSide.desktop);
      expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
    });

    test('terminal replies are dropped while the phone drives', () {
      view.reply(_b('\x1b[12;1R'));
      expect(rig.pty(0).writes, isEmpty);
    });

    test('the phone leaving gives the window its size back', () {
      rig.manager.mobileDisconnected(phone);
      expect(drivers.last, DriverSide.desktop);
      expect(rig.pty(0).resizes.last, (100, 30));
    });
  });

  test('terminal replies are written while the desktop drives', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.manager.view(id).reply(_b('\x1b[1;1R'));
    expect(rig.pty(0).writtenText, '\x1b[1;1R');
  });

  test('the first window size of a phone-driven session does not take the '
      'driver; a later resize does', () async {
    final rig = SessionRig();
    final id = await rig.open(phone, cols: 50, rows: 20);
    final view = rig.manager.view(id);

    view.resize(100, 30); // the tab was laid out for the first time
    expect(rig.manager.sessions.single.driver, DriverSide.phone);
    expect(rig.pty(0).resizes, isEmpty);

    view.resize(110, 32); // the user resized the window
    expect(rig.manager.sessions.single.driver, DriverSide.desktop);
    expect(rig.pty(0).resizes.last, (110, 32));
  });

  test('close kills the process, fires changes at once and reports '
      'closedOnRequest; an attached phone gets closed_by_host', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    await rig.manager.handle(
      phone,
      SessionAttach(id: id, cols: 50, rows: 20, lastSeq: 0),
    );
    final view = rig.manager.view(id);
    final live = _Collected(view);
    var exited = false;
    unawaited(view.exitCode.then((_) => exited = true));
    final changesSeenBeforeExit = <bool>[];
    rig.manager.changes.listen((_) => changesSeenBeforeExit.add(!exited));
    rig.clear();

    rig.manager.close(id);

    expect(rig.manager.sessions, isEmpty);
    // `changes` is an async broadcast stream, so "at once" means the first
    // event is delivered before the shell's exit is reported.
    await Future<void>.value();
    expect(changesSeenBeforeExit, isNotEmpty);
    expect(changesSeenBeforeExit.first, isTrue);
    expect(rig.pty(0).killed, isTrue);
    expect(await view.exitCode, FakePty.killExitCode);
    expect(view.closedOnRequest, isTrue);
    expect(
      rig.to(phone).first,
      SessionDetached(id: id, reason: DetachReason.closedByHost),
    );
    await pumpEventQueue();
    expect(live.done, isTrue);
  });

  test(
    'a shell that exits on its own reports its code, not on request',
    () async {
      final rig = SessionRig();
      final id = await rig.manager.open(cols: 80, rows: 24);
      final view = rig.manager.view(id);
      final live = _Collected(view);
      rig.pty(0).emit('bye');
      rig.pty(0).exit(3);
      expect(await view.exitCode, 3);
      expect(view.closedOnRequest, isFalse);
      await pumpEventQueue();
      expect(live.text.toString(), 'bye');
      expect(live.done, isTrue);
      expect(rig.manager.sessions, isEmpty);
    },
  );

  test('a phone closing the session it opened is a close on request', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    final view = rig.manager.view(id);
    await rig.manager.handle(phone, SessionClose(id: id));
    await view.exitCode;
    expect(view.closedOnRequest, isTrue);
  });

  test('dispose stops delivery to that view only', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final first = rig.manager.view(id);
    final second = rig.manager.view(id);
    final a = _Collected(first);
    final b = _Collected(second);
    first.dispose();
    rig.pty(0).emit('after');
    await pumpEventQueue();
    expect(a.text.toString(), isEmpty);
    expect(b.text.toString(), 'after');
  });

  test('a disposed view never writes, replies or resizes', () async {
    final rig = SessionRig();
    final id = await rig.manager.open(cols: 80, rows: 24);
    final view = rig.manager.view(id);
    view.dispose();
    view.reply(_b('\x1b[1;1R'));
    view.write(_b('x'));
    view.resize(120, 40);
    expect(rig.pty(0).writes, isEmpty);
    expect(rig.pty(0).resizes, isEmpty);
  });
}
