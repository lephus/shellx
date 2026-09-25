import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'drive.dart';
import 'fake_relay.dart';

const userA = 'user-a';
const userB = 'user-b';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const strangerId = 'c0000000-0000-4000-8000-000000000009';

RelayConnection connect(FakeRelay relay, FakeDevice device) => RelayConnection(
  wsUri: relay.wsUri,
  token: () => device.token,
  connector: relay.connector,
  backoff: Backoff(random: Random(3)),
);

void main() {
  test('routes DATA inside one account, rewriting peer to the source', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final a = connect(relay, agent)..start();
      final p = connect(relay, phone)..start();
      final atAgent = <RelayFrame>[];
      a.frames.listen(atAgent.add);
      settle(async);

      final channel = ChannelId.random(Random(1));
      p.send(
        DataFrame(
          peer: agentId,
          channel: channel,
          payload: Uint8List.fromList([4, 1, 2]),
        ),
      );
      settle(async);

      final data = atAgent.whereType<DataFrame>().single;
      expect(data.peer, phoneId);
      expect(data.channel, channel);
      expect(data.payload, [4, 1, 2]);
    });
  });

  test('sends PRESENCE on connect and disconnect', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final a = connect(relay, agent)..start();
      final atAgent = <PresenceFrame>[];
      a.frames.listen((f) {
        if (f is PresenceFrame) atAgent.add(f);
      });
      settle(async);
      final p = connect(relay, phone)..start();
      final atPhone = <PresenceFrame>[];
      p.frames.listen((f) {
        if (f is PresenceFrame) atPhone.add(f);
      });
      settle(async);
      expect(
        [for (final f in atPhone) (f.deviceId, f.online)],
        [(agentId, true)],
      );
      expect(
        [for (final f in atAgent) (f.deviceId, f.online)],
        [(phoneId, true)],
      );

      relay.setReachable(phoneId, false);
      relay.dropConnection(phoneId);
      settle(async);
      expect(
        [for (final f in atAgent) (f.deviceId, f.online)],
        [(phoneId, true), (phoneId, false)],
      );
      expect(relay.isOnline(phoneId), isFalse);
    });
  });

  test('answers peer_offline for offline peers and other accounts', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final stranger = relay.addDevice(
        id: strangerId,
        userId: userB,
        kind: DeviceKind.agent,
      );
      final p = connect(relay, phone)..start();
      connect(relay, stranger).start();
      final errors = <ErrorFrame>[];
      p.frames.listen((f) {
        if (f is ErrorFrame) errors.add(f);
      });
      settle(async);

      final channel = ChannelId.random(Random(2));
      p.send(
        DataFrame(peer: strangerId, channel: channel, payload: Uint8List(1)),
      );
      p.send(DataFrame(peer: agentId, channel: channel, payload: Uint8List(1)));
      settle(async);

      expect(
        [for (final e in errors) (e.code, e.deviceId, e.channel)],
        [
          (RelayErrorCode.peerOffline, strangerId, channel),
          (RelayErrorCode.peerOffline, agentId, channel),
        ],
      );
      expect(relay.delivered, isEmpty);
    });
  });

  test('a second connection of the same device replaces the first (4001)', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final first = connect(relay, phone)..start();
      settle(async);
      final second = connect(relay, phone)..start();
      settle(async);
      expect(first.state, RelayConnectionState.replaced);
      expect(second.state, RelayConnectionState.connected);
    });
  });

  test('answers ping with pong so connections stay up', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final p = connect(relay, phone)..start();
      async.elapse(const Duration(minutes: 3));
      expect(p.state, RelayConnectionState.connected);
    });
  });

  test('serves devices, pairings and pairing removal over HTTP', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      relay.addDevice(id: strangerId, userId: userB, kind: DeviceKind.agent);
      final agentApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = agent.token;
      final phoneApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = phone.token;
      final a = connect(relay, agent)..start();
      final events = <EventFrame>[];
      a.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      final devices = drive(async, phoneApi.devices());
      expect({for (final d in devices) d.id}, {agentId, phoneId});
      expect(devices.firstWhere((d) => d.id == agentId).online, isTrue);

      drive(async, agentApi.createPairing(phoneId));
      expect(relay.pairings, {(agentId, phoneId)});
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      settle(async);
      expect(relay.pairings, isEmpty);
      expect(events.single.event, {
        'event': 'pairing_removed',
        'agent_id': agentId,
        'mobile_id': phoneId,
      });
      expect(relay.requests, [
        'GET /v1/devices',
        'POST /v1/pairings',
        'DELETE /v1/pairings/$agentId/$phoneId',
      ]);
    });
  });
}
