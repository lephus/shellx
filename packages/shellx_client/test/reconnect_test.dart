import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('after a relay drop the phone re-handshakes, re-attaches with '
      'last_seq and receives the output it missed', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      h.disconnectPhone();
      expect(h.sessions.sessions.single.attachedMobileId, isNull);
      h.pty.emit('during');
      settle(async);
      expect(recorder.text, 'before ');

      h.reconnectPhone();
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(tab.isAttached, isTrue);
      expect(recorder.text, 'before during');
      expect(recorder.events.whereType<TabReset>(), isEmpty);
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      expect(h.pty.resizes, [(80, 23), (80, 24)]);
    });
  });

  test('a tab taken over by another phone is not re-attached on reconnect', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.tabletMachine.listSessions());
      final tabletTab = h.run(
        h.tabletMachine.attach(phoneTab.id, cols: 80, rows: 24),
      );
      final tabletEvents = TabRecorder(tabletTab);
      settle(async);
      expect(phoneTab.isAttached, isFalse);

      h.disconnectPhone();
      h.reconnectPhone();

      expect(phoneTab.isAttached, isFalse);
      expect(h.sessions.sessions.single.attachedMobileId, tabletId);
      expect(tabletTab.isAttached, isTrue);
      expect(tabletEvents.events.whereType<TabDetached>(), isEmpty);
      expect(h.phoneMachine.state, isA<MachineIdle>());
    });
  });

  test('after an agent restart an unknown session id ends the tab with '
      'session_not_found', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      h.restartAgent();
      async.elapse(const Duration(seconds: 3));

      expect(tab.isAttached, isFalse);
      final error = recorder.events.whereType<TabError>().single;
      expect(error.code, AppErrorCode.sessionNotFound);
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test('after an agent restart a new session never takes over an old tab, '
      'even when last_seq is within its output', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('hello');
      settle(async);

      // While the phone is away the agent restarts and the tablet opens a new
      // session with more output than the phone's last_seq (5 bytes).
      h.disconnectPhone();
      h.restartAgent();
      final other = h.run(h.tabletMachine.openSession(cols: 80, rows: 24));
      expect(other.id, isNot(tab.id));
      h.pty.emit('output of another session');
      settle(async);

      h.reconnectPhone();
      expect(tab.isAttached, isFalse);
      expect(
        recorder.events.whereType<TabError>().single.code,
        AppErrorCode.sessionNotFound,
      );
      expect(recorder.text, 'hello');
      expect(h.sessions.sessions.single.attachedMobileId, tabletId);
    });
  });

  test('output that overflowed the buffer while away arrives as a reset and '
      'the newest 256 KiB', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('old');
      settle(async);

      h.disconnectPhone();
      h.pty.emitBytes(List.filled(300 * 1024, 0x2e));
      settle(async);
      h.reconnectPhone();

      expect(recorder.events.whereType<TabReset>(), hasLength(1));
      final afterReset = recorder.events
          .skipWhile((e) => e is! TabReset)
          .whereType<TabOutput>()
          .map((e) => e.text)
          .join();
      expect(afterReset.length, 256 * 1024);
      expect(tab.received, 3 + 300 * 1024);
      expect(tab.isAttached, isTrue);
    });
  });

  test('a frame that fails to decrypt makes the phone handshake again on a '
      'new channel and re-attach', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final channels = <ChannelId>{};
      var corruptNext = false;
      h.relay.onData = (from, to, frame) {
        if (from == phoneId) channels.add(frame.channel);
        if (corruptNext &&
            from == agentId &&
            frame.payload.first == PayloadKind.transport.wire) {
          corruptNext = false;
          return corrupted(frame);
        }
        return frame;
      };
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      corruptNext = true;
      h.pty.emit('abc');
      async.elapse(const Duration(seconds: 1));

      expect(recorder.text, 'abc');
      expect(tab.isAttached, isTrue);
      expect(channels, hasLength(2));
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  // Beyond the brief.

  test('a channel lost again while re-attaching makes the phone resume once '
      'more', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final channels = <ChannelId>{};
      var corruptNext = false;
      h.relay.onData = (from, to, frame) {
        if (from == phoneId) channels.add(frame.channel);
        if (corruptNext &&
            from == agentId &&
            frame.payload.first == PayloadKind.transport.wire) {
          corruptNext = false;
          return corrupted(frame); // The answer to the re-attach.
        }
        return frame;
      };
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      h.disconnectPhone();
      h.pty.emit('during');
      settle(async);
      corruptNext = true;
      h.reconnectPhone();

      expect(recorder.text, 'before during');
      expect(tab.isAttached, isTrue);
      expect(channels, hasLength(3));
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('a request the app makes as the agent comes back online does not '
      'stop the tab from being re-attached', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      // The app refreshes its session list whenever the machine comes back.
      final listed = <List<SessionInfo>>[];
      h.phone.presence.listen((presence) {
        if (presence.deviceId == agentId && presence.online) {
          h.phoneMachine.listSessions().then(listed.add);
        }
      });
      h.relay.dropConnection(agentId); // The agent reconnects by itself.
      settle(async);
      expect(h.phone.isOnline(agentId), isFalse);
      async.elapse(const Duration(seconds: 3));
      expect(h.phone.isOnline(agentId), isTrue);
      expect(listed, hasLength(1));

      h.pty.emit('after');
      settle(async);
      expect(recorder.text, 'before after');
      expect(tab.isAttached, isTrue);
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('an agent that reconnects without ever looking offline (its socket '
      'was replaced) gets a new channel and the tab back', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      // A second connection with the agent's token replaces the agent's
      // socket (4001, no PRESENCE offline): the agent drops every channel.
      final stranger = RelayConnection(
        wsUri: h.relay.wsUri,
        token: () => h.agentDevice.token,
        connector: h.relay.connector,
      )..start();
      settle(async);
      // The agent comes back and replaces that socket in turn, again without
      // an offline: the phone only ever sees PRESENCE online.
      h.agent.stop();
      h.run(h.agent.start());
      async.elapse(const Duration(seconds: 12));
      expect(h.phone.isOnline(agentId), isTrue);

      h.pty.emit('after');
      settle(async);
      expect(recorder.text, 'before after');
      expect(tab.isAttached, isTrue);
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      stranger.stop();
    });
  });

  test('while the agent stays offline a relay reconnect tries once, then '
      'waits for the agent to come back', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);
      final states = <MachineConnectionState>[];
      h.phoneMachine.states.listen(states.add);

      h.agent.stop(); // Sessions keep running.
      settle(async);
      h.disconnectPhone();
      h.reconnectPhone();
      async.elapse(const Duration(minutes: 2));
      expect(states.whereType<MachineConnecting>(), hasLength(1));
      expect(
        h.phoneMachine.state,
        isA<MachineFailed>().having(
          (s) => s.failure,
          'failure',
          MachineConnectionFailure.agentOffline,
        ),
      );
      expect(tab.isAttached, isTrue);

      h.pty.emit('meanwhile');
      h.run(h.agent.start());
      settle(async);
      expect(states.whereType<MachineConnecting>(), hasLength(2));
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(recorder.text, 'meanwhile');
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('a channel dropped the moment it becomes ready is replaced by a new '
      'one and the tab re-attaches', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final machine = h.phoneMachine;
      final tab = h.run(machine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      // The channel goes without anything asking for a resume yet; the app
      // connects, and the new channel is dropped as soon as it is ready.
      machine.relayLost();
      settle(async);
      var drops = 0;
      machine.states.listen((state) {
        if (state is MachineReady && drops++ == 0) machine.dropChannel();
      });
      h.run(machine.connect());
      settle(async);

      h.pty.emit('after');
      settle(async);
      expect(drops, 2); // The replacement channel stayed.
      expect(machine.state, isA<MachineReady>());
      expect(recorder.text, 'after');
      expect(tab.isAttached, isTrue);
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
    });
  });

  test('stop() and start() of the phone service re-attach the open tab', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      h.phone.stop();
      settle(async);
      expect(h.phoneMachine.state, isA<MachineIdle>());
      h.pty.emit('during');
      async.elapse(const Duration(seconds: 30));
      expect(h.phoneMachine.state, isA<MachineIdle>()); // No attempts.

      h.run(h.phone.start());
      settle(async);
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(recorder.text, 'before during');
      expect(tab.isAttached, isTrue);
    });
  });
}

/// [frame] with its last byte flipped: the Noise tag no longer matches.
DataFrame corrupted(DataFrame frame) {
  final bad = Uint8List.fromList(frame.payload);
  bad[bad.length - 1] ^= 0xff;
  return DataFrame(peer: frame.peer, channel: frame.channel, payload: bad);
}
