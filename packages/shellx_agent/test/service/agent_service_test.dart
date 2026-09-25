import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/drive.dart';
import '../support/fake_pty.dart';
import '../support/fake_relay.dart';
import '../support/test_mobile.dart';

const userId = 'user-1';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';
const spareId = 'b0000000-0000-4000-8000-000000000004';

late NoiseKeyPair agentKey;
late NoiseKeyPair phoneKey;
late NoiseKeyPair tabletKey;
late NoiseKeyPair spareKey;

/// A real AgentService on a FakeRelay with three scripted phones. Only the
/// phone is trusted initially.
final class AgentRig {
  AgentRig(this.async) {
    agentDevice = relay.addDevice(
      id: agentId,
      userId: userId,
      kind: DeviceKind.agent,
    );
    trusted = TrustedStore(InMemoryKeyValueStore());
    drive(
      async,
      trusted.add(
        TrustedDevice(
          mobileId: phoneId,
          publicKey: phoneKey.publicKey,
          name: 'Test Phone',
          pairedAt: DateTime.utc(2026),
        ),
      ),
    );
    pairing = PairingCodeManager(now: () => now);
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    service = AgentService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => agentDevice.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(11)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: agentKey,
      trusted: trusted,
      sessions: sessions,
      pairing: pairing,
      appVersion: '1.0.0',
    );
    service.events.listen(events.add);
    drive(async, service.start());
    phone = _mobile(phoneId, phoneKey);
    tablet = _mobile(tabletId, tabletKey);
    spare = _mobile(spareId, spareKey);
    settle(async);
  }

  final FakeAsync async;
  final relay = FakeRelay();
  final ptys = FakePtyFactory();
  final events = <AgentEvent>[];
  DateTime now = DateTime.utc(2026, 9, 25, 12);
  late final FakeDevice agentDevice;
  late final TrustedStore trusted;
  late final PairingCodeManager pairing;
  late final SessionManager sessions;
  late final AgentService service;
  late final TestMobile phone;
  late final TestMobile tablet;
  late final TestMobile spare;

  TestMobile _mobile(String id, NoiseKeyPair key) => TestMobile(
    relay: relay,
    device: relay.addDevice(id: id, userId: userId, kind: DeviceKind.mobile),
    identity: key,
  )..start();

  HandshakeResult handshake(
    TestMobile mobile, {
    NoisePattern pattern = NoisePattern.ik,
    Uint8List? psk,
    String name = 'Test Phone',
  }) => drive(
    async,
    mobile.handshake(
      agentId: agentId,
      agentKey: agentKey.publicKey,
      pattern: pattern,
      psk: psk,
      name: name,
    ),
  );

  void send(MobileChannel channel, List<AppMessage> messages) {
    drive(async, channel.send(messages));
    settle(async);
  }

  TrustedDevice? findTrusted(String id) => drive(async, trusted.find(id));
}

void main() {
  setUpAll(() async {
    agentKey = await NoiseKeyPair.generate();
    phoneKey = await NoiseKeyPair.generate();
    tabletKey = await NoiseKeyPair.generate();
    spareKey = await NoiseKeyPair.generate();
  });

  test('a trusted phone gets ok and exactly one channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final result = rig.handshake(rig.phone);
      expect(result.status, HandshakeStatus.ok);
      expect(rig.service.activeChannelCount, 1);
      expect(rig.events.whereType<ActiveChannelsChanged>().last.count, 1);
    });
  });

  test('an untrusted phone gets untrusted and no channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.untrusted);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('app messages reach the session manager and replies come back', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.ptys.ptys.single.emit('hello');
      settle(async);

      final opened = channel.messagesOf<SessionOpened>().single;
      expect(opened.index, 1);
      expect(
        String.fromCharCodes(channel.messagesOf<OutputMessage>().single.data),
        'hello',
      );
      final notice = rig.events.whereType<SessionOpenedByMobile>().single;
      expect((notice.mobileName, notice.sessionId), ('Test Phone', opened.id));
    });
  });

  test('output is batched per channel: 16 ms timer, immediate at 16 KiB', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      final pty = rig.ptys.ptys.single;
      final before = channel.batches.length;

      pty.emit('a');
      async.elapse(const Duration(milliseconds: 5));
      pty.emit('b');
      async.elapse(const Duration(milliseconds: 20));
      expect(channel.batches.length, before + 1);
      expect(channel.batches.last.whereType<OutputMessage>(), hasLength(2));

      pty.emitBytes(List.filled(20 * 1024, 0x7a));
      async.flushMicrotasks();
      expect(channel.batches.length, before + 2);
      expect(
        [
          for (final o in channel.batches.last.whereType<OutputMessage>())
            o.data.length,
        ],
        [16 * 1024, 4 * 1024],
      );
      async.elapse(const Duration(milliseconds: 16));
      expect(channel.batches.length, before + 2);
    });
  });

  test('a new HS1 from the same phone replaces its channel and detaches '
      'its sessions', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final first = rig.handshake(rig.phone).channel!;
      rig.send(first, [const SessionOpen(cols: 80, rows: 24)]);
      final second = rig.handshake(rig.phone).channel!;
      expect(rig.service.activeChannelCount, 1);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);

      final repliesOnFirst = first.received.length;
      rig.send(first, [const SessionList()]);
      expect(first.received.length, repliesOnFirst);
      rig.send(second, [const SessionList()]);
      expect(second.messagesOf<SessionListResult>(), hasLength(1));
    });
  });

  test('any decrypt error drops the channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      channel.sendRaw(Uint8List.fromList(List.filled(40, 7)));
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
    });
  });

  test('PRESENCE offline drops the channel but the session keeps running', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.relay.setReachable(phoneId, false);
      rig.relay.dropConnection(phoneId);
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
      expect(rig.ptys.ptys.single.killed, isFalse);
    });
  });

  test('losing the agent relay connection drops every channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.dropConnection(agentId);
      async.flushMicrotasks();
      expect(rig.service.activeChannelCount, 0);
      async.elapse(const Duration(seconds: 2));
      expect(rig.relay.isOnline(agentId), isTrue);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.ok);
    });
  });

  test('a 4002 close surfaces AgentRevoked; the relay stays down', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.dropConnection(agentId, code: RelayCloseCode.revoked);
      settle(async);
      expect(rig.events.whereType<AgentRevoked>(), hasLength(1));
      expect(rig.service.activeChannelCount, 0);
      async.elapse(const Duration(seconds: 5));
      expect(rig.relay.isOnline(agentId), isFalse);
    });
  });

  test('pairing: pair.confirm trusts the phone, burns the code and records '
      'the pairing', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      expect(uri.agentDeviceId, agentId);
      expect(uri.agentPublicKey, agentKey.publicKey);
      expect(uri.secret, hasLength(32));

      final result = rig.handshake(
        rig.tablet,
        pattern: NoisePattern.ikPsk2,
        psk: uri.secret,
        name: 'iPad',
      );
      expect(result.status, HandshakeStatus.ok);
      expect(rig.findTrusted(tabletId), isNull);
      rig.send(result.channel!, [const PairConfirm()]);

      final paired = rig.events.whereType<MobilePaired>().single.device;
      expect((paired.mobileId, paired.name), (tabletId, 'iPad'));
      expect(rig.findTrusted(tabletId)!.publicKey, tabletKey.publicKey);
      expect(rig.pairing.activeSecret, isNull);
      expect(rig.relay.pairings, {(agentId, tabletId)});
      expect(rig.service.activeChannelCount, 0);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);
    });
  });

  test('a pairing channel accepts nothing but pair.confirm', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      final channel = rig
          .handshake(rig.tablet, pattern: NoisePattern.ikPsk2, psk: uri.secret)
          .channel!;
      rig.send(channel, [const SessionList(), const PairConfirm()]);
      expect(channel.received, isEmpty);
      expect(rig.findTrusted(tabletId), isNull);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('a code works once: a second confirmation with it is rejected', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      final a = rig.handshake(
        rig.tablet,
        pattern: NoisePattern.ikPsk2,
        psk: uri.secret,
      );
      final b = rig.handshake(
        rig.spare,
        pattern: NoisePattern.ikPsk2,
        psk: uri.secret,
      );
      rig.send(a.channel!, [const PairConfirm()]);
      rig.send(b.channel!, [const PairConfirm()]);
      expect(rig.findTrusted(tabletId), isNotNull);
      expect(rig.findTrusted(spareId), isNull);
    });
  });

  test('an expired or cancelled code cannot pair (HS2 is undecryptable)', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final expired = rig.service.startPairing();
      rig.now = rig.now.add(const Duration(minutes: 6));
      final late = rig.handshake(
        rig.tablet,
        pattern: NoisePattern.ikPsk2,
        psk: expired.secret,
      );
      expect(late.decryptFailed, isTrue);

      final cancelled = rig.service.startPairing();
      rig.service.cancelPairing();
      final result = rig.handshake(
        rig.tablet,
        pattern: NoisePattern.ikPsk2,
        psk: cancelled.secret,
      );
      expect(result.decryptFailed, isTrue);
      expect(rig.findTrusted(tabletId), isNull);
    });
  });

  test('revoke removes trust, kills the phone’s sessions, drops its channel '
      'and deletes the pairing record', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.relay.pairings.add((agentId, phoneId));
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);

      drive(async, rig.service.revoke(phoneId));
      settle(async);

      expect(rig.findTrusted(phoneId), isNull);
      expect(rig.ptys.ptys.single.killed, isTrue);
      expect(rig.service.activeChannelCount, 0);
      expect(
        rig.relay.requests,
        contains('DELETE /v1/pairings/$agentId/$phoneId'),
      );
      expect(rig.relay.pairings, isEmpty);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.untrusted);
    });
  });

  test('EVENT pairing_removed for this agent removes trust', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.sendEvent(agentId, {
        'event': 'pairing_removed',
        'agent_id': 'a0000000-0000-4000-8000-00000000ffff',
        'mobile_id': phoneId,
      });
      settle(async);
      expect(rig.findTrusted(phoneId), isNotNull);

      rig.relay.sendEvent(agentId, {
        'event': 'pairing_removed',
        'agent_id': agentId,
        'mobile_id': phoneId,
      });
      settle(async);
      expect(rig.findTrusted(phoneId), isNull);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('stop drops channels and disconnects without closing sessions', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.service.stop();
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.relay.isOnline(agentId), isFalse);
      expect(rig.sessions.sessions, hasLength(1));
    });
  });
}
