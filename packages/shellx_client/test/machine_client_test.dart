import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Matcher failsWith(MachineConnectionFailure failure) => throwsA(
  isA<MachineConnectionException>().having(
    (e) => e.failure,
    'failure',
    failure,
  ),
);

Matcher appError(AppErrorCode code) =>
    throwsA(isA<AppErrorException>().having((e) => e.code, 'code', code));

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('connect performs the IK handshake and becomes ready', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final states = <MachineConnectionState>[];
      h.phoneMachine.states.listen(states.add);
      h.run(h.phoneMachine.connect());
      settle(async);
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(states.map((s) => s.runtimeType), [
        MachineConnecting,
        MachineReady,
      ]);
      expect(h.agent.activeChannelCount, 1);
    });
  });

  test('untrusted: fails, forgets the pinned key', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.run(h.trusted.remove(phoneId));
      final machine = h.phoneMachine;
      expect(
        () => h.run(machine.connect()),
        failsWith(MachineConnectionFailure.untrusted),
      );
      expect(machine.state, isA<MachineFailed>());
      expect(h.run(h.phonePins.find(agentId)), isNull);
      expect(() => h.phone.machine(agentId), throwsStateError);
    });
  });

  test('agent offline: fails with agentOffline', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.agent.stop();
      settle(async);
      expect(
        () => h.run(h.phoneMachine.connect()),
        failsWith(MachineConnectionFailure.agentOffline),
      );
    });
  });

  test('no answer: fails with timeout after the handshake timeout', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      final started = async.elapsed;
      expect(
        () => h.run(h.phoneMachine.connect()),
        failsWith(MachineConnectionFailure.timeout),
      );
      expect(
        async.elapsed - started,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
    });
  });

  test('proto_unsupported from the agent maps to protocolUnsupported', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.agent.stop();
      settle(async);
      // A hand-written agent that answers every HS1 with proto_unsupported.
      final raw = RelayConnection(
        wsUri: h.relay.wsUri,
        token: () => h.agentDevice.token,
        connector: h.relay.connector,
      );
      raw.frames.listen((frame) async {
        if (frame is! DataFrame) return;
        final hello = ChannelPayload.decode(frame.payload);
        final responder = NoiseHandshake.responder(
          pattern: NoisePattern.ik,
          localStatic: keys.agent,
          prologue: buildPrologue(
            agentDeviceId: agentId,
            mobileDeviceId: frame.peer,
          ),
        );
        await responder.readMessage(hello.noiseMessage);
        final reply = await responder.writeMessage(
          Hs2Payload(
            proto: 2,
            app: '9.0.0',
            status: HandshakeStatus.protoUnsupported,
          ).encode(),
        );
        raw.send(
          DataFrame(
            peer: frame.peer,
            channel: frame.channel,
            payload: ChannelPayload(PayloadKind.hs2, reply).encode(),
          ),
        );
      });
      raw.start();
      settle(async);
      expect(
        () => h.run(h.phoneMachine.connect()),
        failsWith(MachineConnectionFailure.protocolUnsupported),
      );
    });
  });

  test('openSession, output and input', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      expect((tab.index, tab.shell, tab.isAttached), (1, 'zsh', true));

      h.pty.emit('hello');
      settle(async);
      h.phoneMachine.input(tab.id, Uint8List.fromList(utf8.encode('ls\r')));
      settle(async);

      expect(recorder.text, 'hello');
      expect(tab.received, 5);
      expect(h.pty.writtenText, 'ls\r');
      expect(h.phoneMachine.tabs.single, same(tab));
    });
  });

  test('input larger than 16 KiB is split into several messages', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final paste = Uint8List.fromList(
        List.generate(40 * 1024, (i) => 0x61 + i % 26),
      );
      h.phoneMachine.input(tab.id, paste);
      settle(async);
      expect([for (final w in h.pty.writes) w.length], [16384, 16384, 8192]);
      expect([for (final w in h.pty.writes) ...w], paste);
    });
  });

  test('resize is ignored below 1 and clamped to 1000 by the agent', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.phoneMachine.resize(tab.id, 0, 10);
      h.phoneMachine.resize(tab.id, 10, 0);
      h.phoneMachine.resize(tab.id, -5, -5);
      h.phoneMachine.resize(tab.id, 100, 40);
      h.phoneMachine.resize(tab.id, 5000, 5000);
      settle(async);
      expect(h.pty.resizes, [(100, 40), (1000, 1000)]);
    });
  });

  test(
    'the phone receives far more than the 256 KiB window thanks to acks',
    () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        for (var i = 0; i < 30; i++) {
          h.pty.emitBytes(List.filled(32 * 1024, 0x2e));
        }
        async.elapse(const Duration(seconds: 2));
        expect(tab.received, 30 * 32 * 1024);
      });
    },
  );

  test('UTF-8 characters split between two output batches arrive whole', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      final data = utf8.encode('Xin chào 😀');
      h.pty.emitBytes(data.sublist(0, 7)); // ends inside "à"
      async.elapse(const Duration(milliseconds: 20));
      h.pty.emitBytes(data.sublist(7, 12)); // ends inside the emoji
      async.elapse(const Duration(milliseconds: 20));
      h.pty.emitBytes(data.sublist(12));
      settle(async);
      expect(recorder.text, 'Xin chào 😀');
      expect(recorder.text, isNot(contains('�')));
    });
  });

  test('listSessions and attach from a second phone take the session over', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final phoneEvents = TabRecorder(phoneTab);
      h.pty.emit('shared ');
      settle(async);

      final listed = h.run(h.tabletMachine.listSessions());
      expect(
        [for (final s in listed) (s.id, s.index, s.shell, s.attached)],
        [(phoneTab.id, 1, 'zsh', true)],
      );
      final tabletTab = h.run(
        h.tabletMachine.attach(phoneTab.id, cols: 100, rows: 30),
      );
      final tabletEvents = TabRecorder(tabletTab);
      h.pty.emit('screen');
      settle(async);

      expect(phoneTab.isAttached, isFalse);
      expect(phoneEvents.events.last, isA<TabDetached>());
      expect(
        (phoneEvents.events.last as TabDetached).reason,
        DetachReason.takenOver,
      );
      expect(tabletTab.isAttached, isTrue);
      expect(tabletEvents.text, 'shared screen');
      expect(h.pty.resizes.last, (100, 30));
    });
  });

  test('session_limit and spawn_failed surface as AppErrorException', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      for (var i = 0; i < 10; i++) {
        h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      }
      expect(
        () => h.run(h.phoneMachine.openSession(cols: 80, rows: 24)),
        appError(AppErrorCode.sessionLimit),
      );
      h.sessions.closeAll();
      settle(async);
      h.ptys.failWith = StateError('no pty');
      expect(
        () => h.run(h.phoneMachine.openSession(cols: 80, rows: 24)),
        appError(AppErrorCode.spawnFailed),
      );
    });
  });

  test(
    'attach to a session that no longer exists fails with session_not_found',
    () {
      fakeAsync((async) {
        final h = Harness(async, keys);
        expect(
          () => h.run(h.tabletMachine.attach(77, cols: 80, rows: 24)),
          appError(AppErrorCode.sessionNotFound),
        );

        final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
        h.run(h.tabletMachine.listSessions());
        h.pty.exit(0);
        settle(async);
        expect(
          () => h.run(h.tabletMachine.attach(tab.id, cols: 80, rows: 24)),
          appError(AppErrorCode.sessionNotFound),
        );
        expect(h.tabletMachine.tabs, isEmpty);
      });
    },
  );

  test('shell exit, closed_by_host and closeTab', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final exiting = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final exitingEvents = TabRecorder(exiting);
      h.pty.exit(3);
      settle(async);
      expect(exiting.isAttached, isFalse);
      expect((exitingEvents.events.last as TabExited).exitCode, 3);

      final hosted = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final hostedEvents = TabRecorder(hosted);
      h.sessions.closeSession(hosted.id);
      settle(async);
      expect(hostedEvents.events.map((e) => e.runtimeType), [
        TabDetached,
        TabExited,
      ]);
      expect(
        (hostedEvents.events.first as TabDetached).reason,
        DetachReason.closedByHost,
      );

      final closing = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.phoneMachine.closeTab(closing.id));
      settle(async);
      expect(h.pty.killed, isTrue);
      expect(h.phoneMachine.tabs.map((t) => t.id), [exiting.id, hosted.id]);
      h.run(h.phoneMachine.closeTab(exiting.id));
      h.run(h.phoneMachine.closeTab(hosted.id));
      expect(h.phoneMachine.tabs, isEmpty);
    });
  });

  // Beyond the brief: request timeouts, channel loss, concurrent attaches.

  Matcher failure(MachineConnectionFailure failure) =>
      isA<MachineConnectionException>().having(
        (e) => e.failure,
        'failure',
        failure,
      );

  test('a request without an answer times out; the channel stays up', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.run(h.phoneMachine.connect());
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      final started = async.elapsed;
      expect(
        () => h.run(h.phoneMachine.listSessions()),
        failsWith(MachineConnectionFailure.timeout),
      );
      expect(
        async.elapsed - started,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test('losing the relay fails pending requests once with agentOffline and '
      'reports every device offline', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.run(h.phoneMachine.connect());
      final seen = <(String, bool)>[];
      h.phone.presence.listen((p) => seen.add((p.deviceId, p.online)));
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      final failures = <Object>[];
      h.phoneMachine.listSessions().then((_) {}, onError: failures.add);
      h.phoneMachine
          .openSession(cols: 80, rows: 24)
          .then((_) {}, onError: failures.add);
      settle(async);
      expect(failures, isEmpty);

      h.disconnectPhone();
      expect(failures, [
        failure(MachineConnectionFailure.agentOffline),
        failure(MachineConnectionFailure.agentOffline),
      ]);
      expect(h.phoneMachine.state, isA<MachineIdle>());
      expect(seen.toSet(), {(agentId, false), (tabletId, false)});
      expect(h.phone.isOnline(agentId), isFalse);
      async.elapse(const Duration(seconds: 15)); // Past the request timeout.
      expect(failures, hasLength(2));
    });
  });

  test('the relay dropping during the handshake fails connect at once', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      Object? error;
      h.phoneMachine.connect().catchError((Object e) {
        error = e;
      });
      settle(async);
      expect(h.phoneMachine.state, isA<MachineConnecting>());
      h.disconnectPhone();
      expect(error, failure(MachineConnectionFailure.timeout));
      expect(h.phoneMachine.state, isA<MachineFailed>());
    });
  });

  test('the agent going offline during the handshake fails connect at once '
      'with agentOffline', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      Object? error;
      h.phoneMachine.connect().catchError((Object e) {
        error = e;
      });
      settle(async);
      h.agent.stop();
      settle(async);
      expect(error, failure(MachineConnectionFailure.agentOffline));
    });
  });

  test('two attaches of the same session both complete with one tab', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.tabletMachine.listSessions());
      final first = h.tabletMachine.attach(phoneTab.id, cols: 80, rows: 24);
      final second = h.tabletMachine.attach(phoneTab.id, cols: 100, rows: 30);
      final tab = h.run(first);
      expect(h.run(second), same(tab));
      async.elapse(const Duration(seconds: 15)); // Past the request timeout.
      expect(tab.isAttached, isTrue);
      expect(h.tabletMachine.tabs.single, same(tab));
      expect(h.pty.resizes.last, (100, 30));
    });
  });

  test('an unusable pinned key fails with untrusted, sends nothing and is '
      'forgotten', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final pins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
      h.run(
        pins.add(
          PinnedMachine(
            agentId: agentId,
            publicKey: Uint8List(16),
            pairedAt: DateTime.utc(2026),
          ),
        ),
      );
      final service = ClientService(
        relay: RelayConnection(
          wsUri: h.relay.wsUri,
          token: () => h.phoneDevice.token,
          connector: h.relay.connector,
        ),
        api: ShellxApi(
          baseUri: h.relay.baseUri,
          httpClient: h.relay.httpClient,
        ),
        deviceId: phoneId,
        userId: userId,
        identity: keys.phone,
        pinned: pins,
        appVersion: '1.0.0',
        deviceName: 'Test Phone',
        platform: DevicePlatform.ios,
      );
      h.run(service.start());
      settle(async);
      final machine = service.machine(agentId);
      expect(
        () => h.run(machine.connect()),
        failsWith(MachineConnectionFailure.untrusted),
      );
      expect(machine.state, isA<MachineFailed>());
      expect(h.run(pins.find(agentId)), isNull);
      expect(() => service.machine(agentId), throwsStateError);
      expect(h.relay.delivered, isEmpty);
    });
  });
}
