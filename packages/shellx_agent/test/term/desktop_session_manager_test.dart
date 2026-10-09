import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/desktop_rig.dart';
import '../support/fake_term_link.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('listing', () {
    test('a connected window is a desktop session with its own index', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        rig.connect(1, app: 'iTerm2');
        rig.connect(2);
        async.flushMicrotasks();
        final infos = rig.manager.sessionInfos;
        expect(infos.map((s) => s.id), [100, 101]);
        expect(infos.map((s) => s.index), [1, 2]);
        expect(infos.first.kind, SessionKind.desktop);
        expect(infos.first.app, 'iTerm2');
        expect(infos.first.shell, 'zsh');
        expect(infos.first.createdAt, 1759276800001);
        expect(rig.manager.owns(100), isTrue);
        expect(rig.manager.owns(7), isFalse);
      });
    });

    test('a session shows its agent when the host knows one (A12 D22)', () {
      fakeAsync((async) {
        final rig = DesktopRig(
          agentOf: (id) =>
              id == 100 ? (agent: 'claude', state: 'running') : null,
        );
        rig.connect(1);
        rig.connect(2);
        async.flushMicrotasks();
        final infos = rig.manager.sessionInfos;
        expect((infos[0].agent, infos[0].agentState), ('claude', 'running'));
        expect(infos[1].toMap().containsKey('agent'), isFalse);
      });
    });

    test('the limit admits reconnecting windows, not new ones', () {
      fakeAsync((async) {
        final rig = DesktopRig(maxSessions: 2);
        rig.connect(1);
        rig.connect(2);
        expect(rig.manager.canAdmit(windowInfo(3)), isFalse);
        expect(rig.manager.canAdmit(windowInfo(1)), isTrue);
        final over = rig.connect(3);
        expect(over.closed, isTrue);
        expect(rig.manager.sessions, hasLength(2));
      });
    });
  });

  group('snapshot and output', () {
    test('a snapshot in parts reaches the phone only once complete', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1);
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.emit(TermSnapshot(data: _b('before '), last: false));
        async.flushMicrotasks();
        expect(rig.text(phone, 100), isEmpty);
        link.emit(TermSnapshot(data: _b('agent'), last: true));
        link.out(' live');
        async.flushMicrotasks();
        expect(rig.text(phone, 100), 'before agent live');
      });
    });

    test('a snapshot over the buffer size is a protocol error', () {
      fakeAsync((async) {
        final rig = DesktopRig(bufferCapacity: 8);
        final link = rig.connect(1);
        link.emit(TermSnapshot(data: _b('0123456789'), last: true));
        async.flushMicrotasks();
        expect(link.closed, isTrue);
        expect(rig.manager.owns(100), isTrue, reason: 'waits for reconnect');
      });
    });

    test('out before the snapshot is a protocol error', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..out('early');
        async.flushMicrotasks();
        expect(link.closed, isTrue);
      });
    });

    test('titles come from OSC in the snapshot and in output', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('\x1b]0;vim notes\x07');
        async.flushMicrotasks();
        expect(rig.manager.sessionInfos.single.title, 'vim notes');
        link.out('\x1b]2;npm run dev\x07');
        async.flushMicrotasks();
        expect(rig.manager.sessions.single.title, 'npm run dev');
      });
    });
  });

  group('driver and size (spec §5.5, §7.3)', () {
    test('attach makes the phone the driver: resize, driver, attached', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        expect(link.sent.single, isA<AgentResize>());
        expect((link.sent.single as AgentResize).cols, 50);
        final messages = rig.to(phone);
        expect(
          messages,
          containsAllInOrder([
            const SessionDriver(id: 100, by: DriverSide.phone),
            const SessionAttached(id: 100),
          ]),
        );
      });
    });

    test('local hands the size back to the desktop; the next phone key '
        'takes it again, resize before input', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.sent.clear();
        rig.clear();
        link.emit(const TermLocal());
        async.flushMicrotasks();
        expect(
          rig.to(phone).single,
          const SessionDriver(id: 100, by: DriverSide.desktop),
        );
        rig.manager.input(phone, 100, _b('ls\r'));
        expect(link.sent[0], isA<AgentResize>());
        expect(link.sent[1], isA<AgentIn>());
        expect(link.typed, 'ls\r');
        expect(
          rig.to(phone).last,
          const SessionDriver(id: 100, by: DriverSide.phone),
        );
      });
    });

    test('same-size input while the phone drives sends no resize', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        link.sent.clear();
        rig.manager.input(phone, 100, _b('a'));
        rig.manager.resize(phone, 100, 50, 20);
        expect(link.sent.whereType<AgentResize>(), isEmpty);
        rig.manager.resize(phone, 100, 60, 20);
        expect((link.sent.last as AgentResize).cols, 60);
      });
    });

    test('detach and a lost channel send local_size, nothing to the phone', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final a = rig.connect(1)..snapshot('');
        final b = rig.connect(2)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        rig.manager.attach(phone, 101, 50, 20, 0);
        rig.clear();
        rig.manager.detach(phone, 100);
        rig.manager.mobileDisconnected(phone);
        expect(a.sent.last, isA<AgentLocalSize>());
        expect(b.sent.last, isA<AgentLocalSize>());
        expect(rig.to(phone), isEmpty);
        expect(
          rig.manager.sessions.every((s) => s.attachedMobileId == null),
          isTrue,
        );
        expect(a.closed || b.closed, isFalse);
      });
    });
  });

  group('reconnect (spec §6.5, §7.8)', () {
    test('within 30 s: same id, reset then the new snapshot, resize resent; '
        'input while away is dropped', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final first = rig.connect(1)..snapshot('old');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 50, 20, 0);
        first.drop();
        async.flushMicrotasks();
        rig.manager.input(phone, 100, _b('lost'));
        async.elapse(const Duration(seconds: 29));
        expect(rig.manager.owns(100), isTrue);
        rig.clear();

        final second = rig.connect(1)..snapshot('new screen');
        async.flushMicrotasks();
        expect(rig.manager.sessionInfos.single.id, 100);
        expect(rig.to(phone).first, const SessionReset(id: 100));
        expect(rig.text(phone, 100), 'new screen');
        expect(second.sent.whereType<AgentResize>().single.cols, 50);
        expect(second.typed, isEmpty);
        async.elapse(const Duration(seconds: 5));
        expect(rig.to(phone).whereType<SessionDetached>(), isEmpty);
      });
    });

    test(
      'a second connection with the same term_id replaces a half-open one',
      () {
        fakeAsync((async) {
          final rig = DesktopRig();
          final old = rig.connect(1)..snapshot('a');
          async.flushMicrotasks();
          final fresh = rig.connect(1)..snapshot('b');
          async.flushMicrotasks();
          expect(old.closed, isTrue);
          expect(fresh.closed, isFalse);
          expect(rig.manager.sessions, hasLength(1));
          old.out('ignored');
          async.flushMicrotasks();
          rig.manager.attach(phone, 100, 80, 24, 0);
          expect(rig.text(phone, 100), 'b');
        });
      },
    );

    test(
      'after 30 s the session goes: terminal_gone to the attached phone',
      () {
        fakeAsync((async) {
          final rig = DesktopRig();
          final link = rig.connect(1)..snapshot('');
          async.flushMicrotasks();
          rig.manager.attach(phone, 100, 80, 24, 0);
          link.drop();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 30));
          expect(rig.manager.owns(100), isFalse);
          expect(
            rig.to(phone).last,
            const SessionDetached(id: 100, reason: DetachReason.terminalGone),
          );
        });
      },
    );
  });

  group('exit', () {
    test('exit drains to the phone, then session.exited; hidden at once', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        link
          ..out('bye')
          ..emit(const TermExit(code: 3));
        async.flushMicrotasks();
        expect(rig.text(phone, 100), 'bye');
        expect(rig.to(phone).last, const SessionExited(id: 100, exitCode: 3));
        expect(rig.manager.sessions, isEmpty);
      });
    });

    test('while draining after exit, phone input and resize are dropped', () {
      fakeAsync((async) {
        final manager = DesktopSessionManager(nextId: () => 100, sendWindow: 4);
        final sent = <OutboundMessage>[];
        manager.outbound.listen(sent.add);
        final link = FakeTermLink(windowInfo(1));
        manager.addLink(link);
        link.snapshot('');
        async.flushMicrotasks();
        manager.attach(phone, 100, 80, 24, 0);
        link
          ..out('abcdefgh')
          ..emit(const TermExit(code: 0));
        async.flushMicrotasks();
        expect(link.closed, isTrue);
        final sentToTerm = link.sent.length;
        manager.input(phone, 100, _b('x'));
        manager.resize(phone, 100, 60, 20);
        expect(link.sent, hasLength(sentToTerm));
        expect(sent.map((o) => o.message).whereType<SessionExited>(), isEmpty);
        manager.ack(phone, 100, 4);
        expect(
          sent.map((o) => o.message).last,
          const SessionExited(id: 100, exitCode: 0),
        );
      });
    });

    test('disconnectPhone while draining after exit is ignored; the drain '
        'still ends with session.exited', () {
      fakeAsync((async) {
        final manager = DesktopSessionManager(nextId: () => 100, sendWindow: 4);
        final sent = <OutboundMessage>[];
        manager.outbound.listen(sent.add);
        final link = FakeTermLink(windowInfo(1));
        manager.addLink(link);
        link.snapshot('');
        async.flushMicrotasks();
        manager.attach(phone, 100, 80, 24, 0);
        link
          ..out('abcdefgh')
          ..emit(const TermExit(code: 7));
        async.flushMicrotasks();
        final before = sent.length;
        manager.disconnectPhone(100);
        expect(sent, hasLength(before));
        manager.ack(phone, 100, 4);
        final messages = sent.map((o) => o.message).toList();
        expect(messages.whereType<SessionDetached>(), isEmpty);
        expect(messages.last, const SessionExited(id: 100, exitCode: 7));
      });
    });

    test('attach to an unknown or exited session is session_not_found', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        rig.manager.attach(phone, 999, 80, 24, 0);
        expect(
          (rig.to(phone).single as ErrorMessage).code,
          AppErrorCode.sessionNotFound,
        );
      });
    });
  });

  group('host side never closes the terminal (spec §7.2)', () {
    test('disconnectPhone: closed_by_host, local_size, terminal stays', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.clear();
        rig.manager.disconnectPhone(100);
        expect(
          rig.to(phone).single,
          const SessionDetached(id: 100, reason: DetachReason.closedByHost),
        );
        expect(link.sent.last, isA<AgentLocalSize>());
        expect(link.closed, isFalse);
        expect(rig.manager.owns(100), isTrue);
      });
    });

    test('releaseAllPhones and disconnectPhonesAttachedTo keep terminals', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final a = rig.connect(1)..snapshot('');
        final b = rig.connect(2)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.manager.attach(tablet, 101, 80, 24, 0);
        rig.manager.disconnectPhonesAttachedTo(phone);
        expect(
          rig.manager.sessions.firstWhere((s) => s.id == 101).attachedMobileId,
          tablet,
        );
        final detachedBefore = rig
            .to(tablet)
            .whereType<SessionDetached>()
            .length;
        rig.manager.releaseAllPhones();
        expect(rig.manager.sessions, hasLength(2));
        expect(a.closed || b.closed, isFalse);
        // The runtime stopping lets phones go silently (like a dropped
        // channel): they re-attach once they reconnect.
        expect(
          rig.to(tablet).whereType<SessionDetached>(),
          hasLength(detachedBefore),
        );
        expect(
          rig.manager.sessions.map((s) => s.attachedMobileId),
          everyElement(isNull),
        );
      });
    });

    test('clear (sharing switched off) drops sessions and links only', () {
      fakeAsync((async) {
        final rig = DesktopRig();
        final link = rig.connect(1)..snapshot('');
        async.flushMicrotasks();
        rig.manager.attach(phone, 100, 80, 24, 0);
        rig.manager.clear();
        expect(rig.manager.sessions, isEmpty);
        expect(
          link.closed,
          isTrue,
          reason: 'ends sharing; window keeps running',
        );
        expect(
          rig.to(phone).last,
          const SessionDetached(id: 100, reason: DetachReason.closedByHost),
        );
        async.elapse(const Duration(minutes: 1));
        expect(rig.to(phone).whereType<SessionDetached>(), hasLength(1));
      });
    });
  });

  test('phoneAttached fires once per new attach', () {
    fakeAsync((async) {
      final rig = DesktopRig();
      final events = <DesktopPhoneAttached>[];
      rig.manager.phoneAttached.listen(events.add);
      rig.connect(1).snapshot('');
      async.flushMicrotasks();
      rig.manager.attach(phone, 100, 80, 24, 0);
      rig.manager.attach(phone, 100, 80, 24, 0);
      async.flushMicrotasks();
      expect(events.map((e) => (e.mobileId, e.sessionId)), [(phone, 100)]);
    });
  });
}
