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
const observerId = 'd0000000-0000-4000-8000-000000000004';

/// Pairing id number [n]: a lower-case UUIDv7 whose timestamp grows with
/// [n] (September 2024, so never ahead of the relay's clock).
String pid(int n) =>
    '01920000-${n.toRadixString(16).padLeft(4, '0')}-7000-8000-000000000000';

/// The pairing_removed event for (agentId, phoneId, [pairingId]).
Map<String, String> removed(String pairingId) => {
  'event': 'pairing_removed',
  'agent_id': agentId,
  'mobile_id': phoneId,
  'pairing_id': pairingId,
};

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

      drive(async, agentApi.createPairing(phoneId, pairingId: pid(1)));
      expect(relay.pairings, {(agentId, phoneId): pid(1)});
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      settle(async);
      expect(relay.pairings, isEmpty);
      expect(events.single.event, removed(pid(1)));
      expect(relay.requests, [
        'GET /v1/devices',
        'POST /v1/pairings',
        'DELETE /v1/pairings/$agentId/$phoneId',
      ]);
    });
  });

  test('a same-device reconnect announces only one online, never an offline, '
      'to others', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final observer = relay.addDevice(
        id: observerId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final o = connect(relay, observer)..start();
      settle(async);

      final first = connect(relay, phone)..start();
      settle(async);

      final atObserver = <PresenceFrame>[];
      o.frames.listen((f) {
        if (f is PresenceFrame) atObserver.add(f);
      });

      final second = connect(relay, phone)..start();
      settle(async);

      expect(first.state, RelayConnectionState.replaced);
      expect(second.state, RelayConnectionState.connected);
      expect(
        [for (final f in atObserver) (f.deviceId, f.online)],
        [(phoneId, true)],
      );
    });
  });

  test('an offline agent gets pairing_removed on every connect until the pair '
      'is re-created', () {
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
      final agentApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = agent.token;
      final phoneApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = phone.token;
      drive(async, agentApi.createPairing(phoneId, pairingId: pid(1)));

      // Unpair while the agent is offline.
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      expect(relay.pairings, isEmpty);

      final a = connect(relay, agent)..start();
      final events = <EventFrame>[];
      a.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      expect(events.map((e) => e.event).toList(), [removed(pid(1))]);

      // A tombstone: delivering it does not clear it.
      List<EventFrame> reconnect() {
        relay.dropConnection(agentId);
        settle(async);
        final received = <EventFrame>[];
        connect(relay, agent)
          ..frames.listen((f) {
            if (f is EventFrame) received.add(f);
          })
          ..start();
        settle(async);
        return received;
      }

      expect(reconnect().map((e) => e.event).toList(), [removed(pid(1))]);

      // Re-pairing (POST /v1/pairings with a newer id) clears it.
      drive(async, agentApi.createPairing(phoneId, pairingId: pid(2)));
      expect(reconnect(), isEmpty);

      // Unpair / re-pair / unpair cycles collapse into one tombstone that
      // carries the newest id.
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      drive(async, agentApi.createPairing(phoneId, pairingId: pid(3)));
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      expect(reconnect().map((e) => e.event).toList(), [removed(pid(3))]);
    });
  });

  test('an online agent gets pairing_removed live and again on every later '
      'connect', () {
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
      final agentApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = agent.token;
      final phoneApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = phone.token;
      drive(async, agentApi.createPairing(phoneId, pairingId: pid(1)));

      final a = connect(relay, agent)..start();
      final events = <EventFrame>[];
      a.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      drive(async, phoneApi.deletePairing(agentId, phoneId));
      settle(async);
      expect(events.map((e) => e.event).toList(), [removed(pid(1))]);

      // Recorded even though the agent was online: every later connect
      // replays it.
      relay.dropConnection(agentId);
      settle(async);
      final events2 = <EventFrame>[];
      final a2 = connect(relay, agent)..start();
      a2.frames.listen((f) {
        if (f is EventFrame) events2.add(f);
      });
      settle(async);
      expect(events2.map((e) => e.event).toList(), [removed(pid(1))]);

      relay.dropConnection(agentId);
      settle(async);
      final events3 = <EventFrame>[];
      final a3 = connect(relay, agent)..start();
      a3.frames.listen((f) {
        if (f is EventFrame) events3.add(f);
      });
      settle(async);
      expect(events3.map((e) => e.event).toList(), [removed(pid(1))]);
    });
  });

  test('sendError delivers an ERROR frame to a connected device', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final a = connect(relay, agent)..start();
      final errors = <ErrorFrame>[];
      a.frames.listen((f) {
        if (f is ErrorFrame) errors.add(f);
      });
      settle(async);

      final error = ErrorFrame(
        code: RelayErrorCode.peerOffline,
        deviceId: phoneId,
        channel: ChannelId(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      );
      relay.sendError(agentId, error);
      relay.sendError(strangerId, error); // Not connected: dropped.
      settle(async);
      expect(errors, [error]);
    });
  });

  test('the mobile side of a removed pairing is notified too', () {
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
      final agentApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = agent.token;
      drive(async, agentApi.createPairing(phoneId, pairingId: pid(1)));

      final p = connect(relay, phone)..start();
      final events = <EventFrame>[];
      p.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      drive(async, agentApi.deletePairing(agentId, phoneId));
      settle(async);

      expect(events.map((e) => e.event).toList(), [removed(pid(1))]);
    });
  });

  test('deleting a pairing that does not exist sends no event', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final agentApi = ShellxApi(
        baseUri: relay.baseUri,
        httpClient: relay.httpClient,
      )..token = agent.token;
      final a = connect(relay, agent)..start();
      final events = <EventFrame>[];
      a.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      drive(async, agentApi.deletePairing(agentId, phoneId)); // never paired
      settle(async);

      expect(events, isEmpty);
      expect(relay.pairings, isEmpty);
    });
  });

  test('a revoked token ends a reconnect attempt in revoked state', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      final p = connect(relay, phone)..start();
      settle(async);
      expect(p.state, RelayConnectionState.connected);

      relay.dropConnection(phoneId);
      settle(async);
      expect(p.state, RelayConnectionState.disconnected);

      relay.revokeToken(phoneId);
      p.reconnectNow();
      settle(async);

      expect(p.state, RelayConnectionState.revoked);
    });
  });

  test("frame_too_large carries the sender's intended peer and channel when "
      'the DATA header parses', () {
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
      connect(relay, agent).start();
      final p = connect(relay, phone)..start();
      final errors = <ErrorFrame>[];
      p.frames.listen((f) {
        if (f is ErrorFrame) errors.add(f);
      });
      settle(async);

      final channel = ChannelId.random(Random(4));
      p.send(
        DataFrame(
          peer: agentId,
          channel: channel,
          payload: Uint8List(kMaxFrameBytes),
        ),
      );
      settle(async);

      expect(errors.single.code, RelayErrorCode.frameTooLarge);
      expect(errors.single.deviceId, agentId);
      expect(errors.single.channel, channel);
      expect(relay.delivered, isEmpty);
    });
  });

  group('pairing ids', () {
    late FakeRelay relay;
    late FakeDevice agent;
    late ShellxApi agentApi;
    late ShellxApi phoneApi;

    // Plain objects only: nothing here chains futures outside fakeAsync.
    setUp(() {
      relay = FakeRelay();
      agent = relay.addDevice(
        id: agentId,
        userId: userA,
        kind: DeviceKind.agent,
      );
      final phone = relay.addDevice(
        id: phoneId,
        userId: userA,
        kind: DeviceKind.mobile,
      );
      agentApi = ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agent.token;
      phoneApi = ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = phone.token;
    });

    Matcher failsWith(int status, String code) => throwsA(
      isA<ApiException>()
          .having((e) => e.status, 'status', status)
          .having((e) => e.code, 'code', code),
    );

    List<EventFrame> connectAndCollect(FakeAsync async) {
      relay.dropConnection(agentId);
      settle(async);
      final received = <EventFrame>[];
      connect(relay, agent)
        ..frames.listen((f) {
          if (f is EventFrame) received.add(f);
        })
        ..start();
      settle(async);
      return received;
    }

    test('POST refuses (410) an id not newer than the tombstone, keeping '
        'it; a newer id clears it; the same id again is 201', () {
      fakeAsync((async) {
        drive(async, agentApi.createPairing(phoneId, pairingId: pid(2)));
        drive(async, agentApi.createPairing(phoneId, pairingId: pid(2)));
        expect(relay.pairings, {(agentId, phoneId): pid(2)});
        drive(async, phoneApi.deletePairing(agentId, phoneId));

        for (final stale in [pid(1), pid(2)]) {
          expect(
            () =>
                drive(async, agentApi.createPairing(phoneId, pairingId: stale)),
            failsWith(410, 'pairing_removed'),
          );
        }
        expect(relay.pairings, isEmpty);
        expect(connectAndCollect(async).map((e) => e.event).toList(), [
          removed(pid(2)),
        ]);

        drive(async, agentApi.createPairing(phoneId, pairingId: pid(3)));
        expect(relay.pairings, {(agentId, phoneId): pid(3)});
        expect(connectAndCollect(async), isEmpty);
      });
    });

    test('POST refuses (410) an id older than the existing row and keeps the '
        'row', () {
      fakeAsync((async) {
        drive(async, agentApi.createPairing(phoneId, pairingId: pid(5)));
        expect(
          () =>
              drive(async, agentApi.createPairing(phoneId, pairingId: pid(4))),
          failsWith(410, 'pairing_removed'),
        );
        expect(relay.pairings, {(agentId, phoneId): pid(5)});
      });
    });

    test('POST validates the id: upper case or not version 7 is 400; more '
        'than 24 h ahead of the relay clock is 410', () {
      fakeAsync((async) {
        for (final bad in [
          '0192abcd-0001-7000-8000-00000000000a'.toUpperCase(),
          '01920000-0001-4000-8000-000000000000', // Version 4.
          'not-a-uuid',
        ]) {
          expect(
            () => drive(async, agentApi.createPairing(phoneId, pairingId: bad)),
            failsWith(400, 'bad_request'),
          );
        }
        relay.now = () => DateTime.fromMillisecondsSinceEpoch(
          0x019200000001 - const Duration(hours: 25).inMilliseconds,
        );
        expect(
          () =>
              drive(async, agentApi.createPairing(phoneId, pairingId: pid(1))),
          failsWith(410, 'pairing_removed'),
        );
        expect(relay.pairings, isEmpty);
      });
    });

    test('DELETE with a pairing id removes only that pairing; the event and '
        'tombstone carry the id of the row deleted', () {
      fakeAsync((async) {
        final a = connect(relay, agent)..start();
        final events = <EventFrame>[];
        a.frames.listen((f) {
          if (f is EventFrame) events.add(f);
        });
        settle(async);
        drive(async, agentApi.createPairing(phoneId, pairingId: pid(2)));

        drive(
          async,
          agentApi.deletePairing(agentId, phoneId, pairingId: pid(1)),
        );
        settle(async);
        expect(relay.pairings, {(agentId, phoneId): pid(2)});
        expect(events, isEmpty);

        expect(
          () => drive(
            async,
            agentApi.deletePairing(agentId, phoneId, pairingId: 'NOPE'),
          ),
          failsWith(400, 'bad_request'),
        );

        drive(
          async,
          agentApi.deletePairing(agentId, phoneId, pairingId: pid(2)),
        );
        settle(async);
        expect(relay.pairings, isEmpty);
        expect(events.map((e) => e.event).toList(), [removed(pid(2))]);
        expect(relay.requests.last, 'DELETE /v1/pairings/$agentId/$phoneId');
      });
    });
  });
}
