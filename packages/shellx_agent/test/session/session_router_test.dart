import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/desktop_rig.dart' show windowInfo;
import '../support/fake_pty.dart';
import '../support/fake_term_link.dart';
import '../support/session_rig.dart' show phone, tablet;

final class _Rig {
  _Rig() {
    var next = 10;
    int ids() => next++;
    shells = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      nextId: ids,
    );
    desktop = DesktopSessionManager(nextId: ids);
    router = SessionRouter(
      shells: shells,
      desktop: desktop,
      desktopSharing: () => sharing,
    );
    router.outbound.listen(sent.add);
  }

  final ptys = FakePtyFactory();
  late final SessionManager shells;
  late final DesktopSessionManager desktop;
  late final SessionRouter router;
  bool sharing = true;
  final sent = <OutboundMessage>[];

  List<AppMessage> to(String m) => [
    for (final o in sent)
      if (o.mobileId == m) o.message,
  ];

  FakeTermLink window(int n) {
    final link = FakeTermLink(windowInfo(n));
    desktop.addLink(link);
    link.snapshot('');
    return link;
  }
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('ids never collide between shell and desktop sessions', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      rig.window(1);
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      rig.window(2);
      async.flushMicrotasks();
      final ids = [
        ...rig.shells.sessionInfos.map((s) => s.id),
        ...rig.desktop.sessionInfos.map((s) => s.id),
      ];
      expect(ids.toSet(), hasLength(4));
    });
  });

  test('an old phone sees today\'s list; desktop: true adds desktop '
      'sessions and desktop_sharing', () {
    fakeAsync((async) {
      final rig = _Rig()..window(1);
      async.flushMicrotasks();
      rig.router.handle(phone, const SessionList());
      final old = rig.to(phone).single as SessionListResult;
      expect(old.sessions, isEmpty);
      expect(old.desktopSharing, isNull);
      expect(old.toMap().containsKey('desktop_sharing'), isFalse);

      rig.sent.clear();
      rig.sharing = false;
      rig.router.handle(phone, const SessionList(desktop: true));
      final fresh = rig.to(phone).single as SessionListResult;
      expect(fresh.sessions.single.kind, SessionKind.desktop);
      expect(fresh.desktopSharing, isFalse);
    });
  });

  test('a phone that never listed with desktop: true cannot attach a '
      'desktop session; once listed it can, also after its channel drops', () {
    fakeAsync((async) {
      final rig = _Rig();
      final link = rig.window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      final attach = SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0);

      rig.router.handle(phone, attach);
      expect(
        (rig.to(phone).single as ErrorMessage).code,
        AppErrorCode.sessionNotFound,
      );
      expect(link.sent, isEmpty);

      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(phone, attach);
      expect(rig.to(phone).last, SessionAttached(id: id));

      rig.router.mobileDisconnected(phone);
      rig.sent.clear();
      rig.router.handle(phone, attach);
      expect(rig.to(phone).last, SessionAttached(id: id));
    });
  });

  test('revoking a phone drops its desktop flag', () {
    fakeAsync((async) {
      final rig = _Rig()..window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.closeSessionsAttachedTo(phone);
      rig.sent.clear();
      rig.router.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      expect(rig.to(phone).single, isA<ErrorMessage>());
    });
  });

  test('input, resize and ack reach the desktop session', () {
    fakeAsync((async) {
      final rig = _Rig();
      final link = rig.window(1);
      async.flushMicrotasks();
      final id = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(
        phone,
        SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.router.handle(phone, InputMessage(id: id, data: _b('ls\r')));
      rig.router.handle(phone, ResizeMessage(id: id, cols: 90, rows: 30));
      rig.router.handle(phone, AckMessage(id: id, seq: 0));
      expect(link.typed, 'ls\r');
      expect((link.sent.last as AgentResize).cols, 90);
    });
  });

  group('no path closes a desktop terminal (spec §7.2)', () {
    late _Rig rig;
    late FakeTermLink link;
    late int desktopId;
    late int shellId;

    void setUpWorld(FakeAsync async) {
      rig = _Rig();
      link = rig.window(1);
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      shellId = rig.shells.sessionInfos.single.id;
      desktopId = rig.desktop.sessionInfos.single.id;
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(
        phone,
        SessionAttach(id: desktopId, cols: 80, rows: 24, lastSeq: 0),
      );
      rig.sent.clear();
    }

    void expectTerminalAlive() {
      expect(link.closed, isFalse);
      expect(rig.desktop.owns(desktopId), isTrue);
    }

    test('session.close from the phone only detaches', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.handle(phone, SessionClose(id: desktopId));
        async.flushMicrotasks();
        expectTerminalAlive();
        expect(rig.desktop.sessions.single.attachedMobileId, isNull);
        expect(rig.to(phone), isEmpty);
      });
    });

    test('session.detach on a shell session is ignored', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.handle(phone, SessionDetach(id: shellId));
        expect(rig.ptys.ptys.single.killed, isFalse);
        expect(rig.to(phone), isEmpty);
      });
    });

    test('revoke kills shells, only disconnects desktop terminals', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeSessionsAttachedTo(phone);
        async.flushMicrotasks();
        expect(rig.ptys.ptys.single.killed, isTrue);
        expectTerminalAlive();
        expect(
          rig.to(phone),
          contains(
            SessionDetached(id: desktopId, reason: DetachReason.closedByHost),
          ),
        );
      });
    });

    test('closeSession on a desktop id disconnects the phone only', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeSession(desktopId);
        expectTerminalAlive();
        expect(rig.ptys.ptys.single.killed, isFalse);
        expect(
          rig.to(phone),
          contains(
            SessionDetached(id: desktopId, reason: DetachReason.closedByHost),
          ),
        );
        expect(rig.desktop.sessions.single.attachedMobileId, isNull);
      });
    });

    test('closeAll (quit, remote access off, logout) kills shells only', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.closeAll();
        async.flushMicrotasks();
        expect(rig.ptys.ptys.single.killed, isTrue);
        expectTerminalAlive();
        expect(
          rig.to(phone),
          contains(
            SessionDetached(id: desktopId, reason: DetachReason.closedByHost),
          ),
        );
        expect(rig.desktop.sessions.single.attachedMobileId, isNull);
      });
    });

    test('mobileDisconnected keeps the terminal', () {
      fakeAsync((async) {
        setUpWorld(async);
        rig.router.mobileDisconnected(phone);
        expectTerminalAlive();
        expect(rig.ptys.ptys.single.killed, isFalse);
      });
    });
  });

  test('changes fire for both kinds of session', () {
    fakeAsync((async) {
      final rig = _Rig();
      var count = 0;
      rig.router.changes.listen((_) => count++);
      rig.window(1);
      rig.router.handle(tablet, const SessionOpen(cols: 80, rows: 24));
      async.flushMicrotasks();
      expect(count, greaterThanOrEqualTo(2));
    });
  });

  test('only phones that listed with desktop: true get session.driver', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(tablet, const SessionList());
      rig.shells.open(cols: 100, rows: 30).ignore();
      async.flushMicrotasks();
      final opened = rig.shells.sessions.single.id;
      expect(rig.shells.receivesDriver(phone), isTrue);
      expect(rig.shells.receivesDriver(tablet), isFalse);
      rig.router.handle(
        phone,
        SessionAttach(id: opened, cols: 50, rows: 20, lastSeq: 0),
      );
      async.flushMicrotasks();
      expect(
        rig.to(phone),
        contains(SessionDriver(id: opened, by: DriverSide.phone)),
      );
    });
  });

  test('disconnectAllPhones reaches both managers silently and kills '
      'nothing', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      rig.router.handle(phone, const SessionOpen(cols: 80, rows: 24));
      rig.window(1);
      async.flushMicrotasks();
      final desktopId = rig.desktop.sessions.single.id;
      rig.router.handle(
        phone,
        SessionAttach(id: desktopId, cols: 50, rows: 20, lastSeq: 0),
      );
      async.flushMicrotasks();

      rig.sent.clear();
      rig.router.disconnectAllPhones();

      expect(rig.ptys.ptys.single.killed, isFalse);
      expect(rig.shells.sessions.single.attachedMobileId, isNull);
      expect(rig.desktop.sessions.single.attachedMobileId, isNull);
      // Silent (ruling I4): the phone sees the channel drop instead.
      expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
    });
  });

  test('dispose stops forwarding and unwires receivesDriver', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.router.handle(phone, const SessionList(desktop: true));
      async.flushMicrotasks();
      rig.sent.clear();
      rig.router.dispose();
      async.flushMicrotasks();
      expect(rig.shells.receivesDriver(phone), isFalse);
      rig.shells.handle(phone, const SessionList());
      async.flushMicrotasks();
      expect(rig.sent, isEmpty);
    });
  });

  test('session.list {desktop: true} carries cwd; desktop: false is the A1 '
      'list exactly (A2 C4)', () async {
    final rig = _Rig();
    await rig.shells.open(cols: 80, rows: 24);
    rig.ptys.ptys[0].emit('\x1b]7;file:///Users/test/w\x07');
    await pumpEventQueue();
    await rig.router.handle(phone, const SessionList());
    final old = rig.to(phone).whereType<SessionListResult>().last;
    expect(old.sessions.single.toMap().keys, [
      'id',
      'index',
      'shell',
      'created_at',
      'attached',
    ]);
    await rig.router.handle(tablet, const SessionList(desktop: true));
    final rich = rig.to(tablet).whereType<SessionListResult>().last;
    expect(rich.sessions.first.toMap()['cwd'], '/Users/test/w');
    expect(rich.sessions.first.toMap().containsKey('branch'), isFalse);
  });
}
