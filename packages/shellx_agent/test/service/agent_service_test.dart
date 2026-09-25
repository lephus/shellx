import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
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
/// phone is trusted initially. [store] backs the trust list (in-memory by
/// default); [shellResolver] defaults to [FixedShellResolver]. The agent's
/// REST calls go through [posts], so `POST /v1/pairings` can be failed or
/// held.
final class AgentRig {
  AgentRig(this.async, {KeyValueStore? store, ShellResolver? shellResolver})
    : store = store ?? InMemoryKeyValueStore() {
    agentDevice = relay.addDevice(
      id: agentId,
      userId: userId,
      kind: DeviceKind.agent,
    );
    posts = PairingPostControl(relay.httpClient);
    trusted = TrustedStore(this.store);
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
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: shellResolver ?? const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    _startService();
    phone = _mobile(phoneId, phoneKey);
    tablet = _mobile(tabletId, tabletKey);
    spare = _mobile(spareId, spareKey);
    settle(async);
  }

  final FakeAsync async;
  final KeyValueStore store;
  final relay = FakeRelay();
  final ptys = FakePtyFactory();
  final events = <AgentEvent>[];
  DateTime now = DateTime.utc(2026, 9, 25, 12);
  late final FakeDevice agentDevice;
  late final PairingPostControl posts;
  late TrustedStore trusted;
  late PairingCodeManager pairing;
  late final SessionManager sessions;
  late AgentService service;
  late final TestMobile phone;
  late final TestMobile tablet;
  late final TestMobile spare;

  void _startService() {
    pairing = PairingCodeManager(now: () => now);
    service = AgentService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => agentDevice.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(11)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: posts)
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
  }

  /// Quits and relaunches the agent: a new AgentService, TrustedStore and
  /// PairingCodeManager over the same persisted [store]. (The session
  /// manager is kept; restarts here are about trust.)
  void restartAgent() {
    service.stop();
    settle(async);
    trusted = TrustedStore(store);
    _startService();
    settle(async);
  }

  /// The phone-side unpair (Settings → unpair): `DELETE /v1/pairings`.
  void unpairFromPhone(TestMobile mobile) {
    final api = ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
      ..token = mobile.device.token;
    drive(async, api.deletePairing(agentId, mobile.device.id));
    settle(async);
  }

  /// Pairs [mobile] with a fresh code and pair.confirm.
  void pair(TestMobile mobile, {String name = 'iPad'}) {
    final uri = service.startPairing();
    final result = handshake(
      mobile,
      pattern: NoisePattern.ikPsk2,
      psk: uri.secret,
      name: name,
    );
    send(result.channel!, [const PairConfirm()]);
  }

  /// Drops the agent's relay connection and waits for the reconnect (which
  /// replays the relay's pairing_removed tombstones).
  void reconnectAgent() {
    relay.dropConnection(agentId);
    async.elapse(const Duration(seconds: 2));
    expect(relay.isOnline(agentId), isTrue);
    settle(async);
  }

  Set<String> get unregistered => drive(async, trusted.unregistered());

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

/// Wraps the fake relay's HTTP client so the agent's `POST /v1/pairings`
/// can be failed ([failWith]: an HTTP status, or 0 for a network error) or
/// held at [gate]. Everything else passes through.
final class PairingPostControl extends http.BaseClient {
  PairingPostControl(this._inner);

  final http.Client _inner;
  int? failWith;
  Completer<void>? gate;

  /// `POST /v1/pairings` attempts, including failed ones.
  int attempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path == '/v1/pairings') {
      attempts++;
      final held = gate;
      if (held != null) await held.future;
      final status = failWith;
      if (status == 0) throw http.ClientException('network is down');
      if (status != null) {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode('{"error":{"code":"test","message":"test"}}'),
          ),
          status,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    return _inner.send(request);
  }
}

/// In-memory [KeyValueStore] whose reads can be held at a [gate] or made to
/// fail (a locked keychain), to interleave work with trust-list reads.
final class ControllableStore implements KeyValueStore {
  final _inner = InMemoryKeyValueStore();

  /// While set, every read waits for it to complete.
  Completer<void>? gate;

  /// While true, every read throws.
  bool failReads = false;

  /// Reads currently waiting at [gate].
  int waitingReads = 0;

  /// Every read and write/delete so far.
  int reads = 0, writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    final pending = gate;
    if (pending != null) {
      waitingReads++;
      await pending.future;
      waitingReads--;
    }
    if (failReads) throw StateError('secure storage unavailable');
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writes++;
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    writes++;
    return _inner.delete(key);
  }
}

/// A [ShellResolver] that answers only once [gate] completes.
final class GatedShellResolver implements ShellResolver {
  final gate = Completer<void>();

  @override
  Future<ShellCommand> resolve() async {
    await gate.future;
    return const FixedShellResolver().resolve();
  }
}

TrustedDevice trustedTablet() => TrustedDevice(
  mobileId: tabletId,
  publicKey: tabletKey.publicKey,
  name: 'iPad',
  pairedAt: DateTime.utc(2026),
);

Map<String, String> pairingRemoved(String mobileId) => {
  'event': 'pairing_removed',
  'agent_id': agentId,
  'mobile_id': mobileId,
};

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

  test('ERROR peer_offline drops the channel it names, not a newer one', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final result = rig.handshake(rig.phone);
      rig.send(result.channel!, [const SessionOpen(cols: 80, rows: 24)]);

      rig.relay.sendError(
        agentId,
        ErrorFrame(
          code: RelayErrorCode.peerOffline,
          deviceId: phoneId,
          channel: ChannelId.random(Random(1)), // A stale channel.
        ),
      );
      settle(async);
      expect(rig.service.activeChannelCount, 1);

      rig.relay.sendError(
        agentId,
        ErrorFrame(
          code: RelayErrorCode.peerOffline,
          deviceId: phoneId,
          channel: result.channelId,
        ),
      );
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

  test('start after stop reconnects and answers handshakes again', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.service.stop();
      settle(async);
      expect(rig.relay.isOnline(agentId), isFalse);

      drive(async, rig.service.start());
      settle(async);
      expect(rig.relay.isOnline(agentId), isTrue);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionList()]);
      expect(channel.messagesOf<SessionListResult>(), hasLength(1));
      expect(rig.service.activeChannelCount, 1);
    });
  });

  test('a session opened across stop() is not left attached to the phone', () {
    fakeAsync((async) {
      final resolver = GatedShellResolver();
      final rig = AgentRig(async, shellResolver: resolver);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      expect(rig.ptys.ptys, isEmpty); // Still resolving the shell.

      rig.service.stop();
      resolver.gate.complete();
      settle(async);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
      expect(channel.messagesOf<SessionOpened>(), isEmpty);
    });
  });

  test('an HS1 answered across stop() and start() installs no channel', () {
    fakeAsync((async) {
      final store = ControllableStore();
      final rig = AgentRig(async, store: store);
      final gate = store.gate = Completer<void>();
      final hello = rig.phone.handshake(
        agentId: agentId,
        agentKey: agentKey.publicKey,
      );
      async.flushMicrotasks();
      expect(store.waitingReads, 1);

      rig.service.stop();
      drive(async, rig.service.start());
      settle(async);
      expect(rig.relay.isOnline(agentId), isTrue);
      store.gate = null;
      gate.complete();
      expect(drive(async, hello).status, isNull); // No HS2 was sent.
      expect(rig.service.activeChannelCount, 0);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.ok);
    });
  });

  test('a rejected HS1 leaves the phone’s existing channel alone', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      final rejected = drive(
        async,
        rig.phone.handshake(
          agentId: agentId,
          agentKey: agentKey.publicKey,
          proto: kAppProtocolVersion + 1,
        ),
      );
      expect(rejected.status, HandshakeStatus.protoUnsupported);
      expect(rig.service.activeChannelCount, 1);
      rig.send(channel, [const SessionList()]);
      expect(channel.messagesOf<SessionListResult>(), hasLength(1));
    });
  });

  test('an HTTP 401 on reconnect (token revoked) surfaces AgentRevoked', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.revokeToken(agentId);
      rig.relay.dropConnection(agentId);
      async.elapse(const Duration(seconds: 2));
      expect(rig.events.whereType<AgentRevoked>(), hasLength(1));
      expect(rig.service.activeChannelCount, 0);
      async.elapse(const Duration(seconds: 30));
      expect(rig.relay.isOnline(agentId), isFalse);
    });
  });

  // Ruling 2: AgentChannel.onFailure drops the channel like a decrypt error.
  test('a relay send failure on an established channel drops the channel; '
      'the phone re-attaches from last_seq', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      final opened = channel.messagesOf<SessionOpened>().single;
      // RelayConnection.send() returns false when the socket write throws.
      rig.relay.onData = (from, to, frame) =>
          from == agentId ? throw StateError('socket write failed') : frame;

      rig.ptys.ptys.single.emit('while broken');
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.events.whereType<ActiveChannelsChanged>().last.count, 0);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
      expect(rig.ptys.ptys.single.killed, isFalse);

      rig.relay.onData = null;
      final again = rig.handshake(rig.phone).channel!;
      rig.send(again, [
        SessionAttach(id: opened.id, cols: 80, rows: 24, lastSeq: 0),
      ]);
      expect(
        String.fromCharCodes(again.messagesOf<OutputMessage>().single.data),
        'while broken',
      );
      expect(again.messagesOf<SessionAttached>(), hasLength(1));
    });
  });

  // Ruling 3: only a decrypted pair.confirm proves the code, and only while
  // the handshake's code is still the active one.
  test('pair.confirm is rejected when the code was replaced or cancelled '
      'after the handshake', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final first = rig.service.startPairing();
      final replaced = rig.handshake(
        rig.tablet,
        pattern: NoisePattern.ikPsk2,
        psk: first.secret,
      );
      expect(replaced.status, HandshakeStatus.ok);
      final second = rig.service.startPairing();
      rig.send(replaced.channel!, [const PairConfirm()]);
      expect(rig.findTrusted(tabletId), isNull);
      expect(rig.pairing.activeSecret, second.secret);

      final cancelled = rig.handshake(
        rig.spare,
        pattern: NoisePattern.ikPsk2,
        psk: second.secret,
      );
      expect(cancelled.status, HandshakeStatus.ok);
      rig.service.cancelPairing();
      rig.send(cancelled.channel!, [const PairConfirm()]);
      expect(rig.findTrusted(spareId), isNull);

      expect(rig.events.whereType<MobilePaired>(), isEmpty);
      expect(rig.relay.pairings, isEmpty);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('a pairing channel is closed after its first payload, even an empty '
      'one', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      final channel = rig
          .handshake(rig.tablet, pattern: NoisePattern.ikPsk2, psk: uri.secret)
          .channel!;
      rig.send(channel, const []);
      expect(rig.service.activeChannelCount, 0);
      rig.send(channel, [const PairConfirm()]);
      expect(rig.findTrusted(tabletId), isNull);
      expect(rig.events.whereType<MobilePaired>(), isEmpty);
    });
  });

  test('a trust-store failure while answering an HS1 means no answer and '
      'does not block the next HS1', () {
    fakeAsync((async) {
      final store = ControllableStore();
      final rig = AgentRig(async, store: store);
      store.failReads = true;
      final failed = rig.handshake(rig.phone);
      expect(failed.status, isNull);
      expect(failed.decryptFailed, isFalse);
      expect(rig.service.activeChannelCount, 0);

      store.failReads = false;
      expect(rig.handshake(rig.phone).status, HandshakeStatus.ok);
      expect(rig.service.activeChannelCount, 1);
    });
  });

  // Ruling 4: revoke is serialized with frame handling.
  test(
    'revoke racing an in-flight HS1 leaves no usable channel or session',
    () {
      fakeAsync((async) {
        final store = ControllableStore();
        final rig = AgentRig(async, store: store);
        final gate = store.gate = Completer<void>();
        final hello = rig.phone.handshake(
          agentId: agentId,
          agentKey: agentKey.publicKey,
        );
        async.flushMicrotasks();
        expect(store.waitingReads, 1); // The HS1 is inside TrustedStore.find.

        final revoked = rig.service.revoke(phoneId);
        async.flushMicrotasks();
        store.gate = null;
        gate.complete();
        final result = drive(async, hello);
        drive(async, revoked);
        settle(async);

        // The HS1 was answered with the trust it read, but its channel died
        // with the revoke.
        expect(result.status, HandshakeStatus.ok);
        expect(rig.findTrusted(phoneId), isNull);
        expect(rig.service.activeChannelCount, 0);
        expect(rig.events.whereType<ActiveChannelsChanged>().last.count, 0);
        rig.send(result.channel!, [
          const SessionOpen(cols: 80, rows: 24),
          const SessionList(),
        ]);
        expect(result.channel!.received, isEmpty);
        expect(rig.ptys.ptys, isEmpty);
        expect(rig.handshake(rig.phone).status, HandshakeStatus.untrusted);
      });
    },
  );

  // Ruling 5: the relay replays pairing_removed tombstones on every connect.
  test('pairing_removed repeated for an already-untrusted phone (live or '
      'replayed on reconnect) is a harmless no-op', () {
    fakeAsync((async) {
      final store = ControllableStore();
      final rig = AgentRig(async, store: store);
      drive(async, rig.trusted.add(trustedTablet()));
      rig.relay.pairings.add((agentId, phoneId));
      rig.handshake(rig.phone);
      final tablet = rig.handshake(rig.tablet).channel!;

      // The relay echoes the revoke's pairing_removed live and keeps it
      // queued for the next connect.
      drive(async, rig.service.revoke(phoneId));
      settle(async);
      expect(rig.service.activeChannelCount, 1);
      final eventCount = rig.events.length;
      final reads = store.reads;
      final writes = store.writes;

      rig.relay.sendEvent(agentId, pairingRemoved(phoneId));
      rig.relay.sendEvent(agentId, pairingRemoved(phoneId));
      settle(async);
      expect(store.reads, greaterThan(reads)); // Both were processed...
      expect(store.writes, writes); // ...without a storage write...
      expect(rig.events.length, eventCount); // ...or any event.
      expect(rig.service.activeChannelCount, 1);
      rig.send(tablet, [const SessionList()]);
      expect(tablet.messagesOf<SessionListResult>(), hasLength(1));

      // The tombstone is replayed on every connect.
      rig.reconnectAgent();
      rig.reconnectAgent();
      expect(store.writes, writes);
      expect(rig.findTrusted(phoneId), isNull);
      expect(rig.findTrusted(tabletId), isNotNull);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.untrusted);
    });
  });

  // Controller ruling (pre-review): a fresh pairing is protected from a
  // replayed pairing_removed tombstone until the relay registers it.
  group('unregistered pairings', () {
    test('a re-pair whose POST keeps failing survives the tombstone replayed '
        'on reconnect; once registered, a real unpair removes trust', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        expect(rig.relay.pairings, contains((agentId, tabletId)));
        expect(rig.unregistered, isEmpty);
        rig.unpairFromPhone(rig.tablet); // Leaves a tombstone at the relay.
        expect(rig.findTrusted(tabletId), isNull);

        rig.posts.failWith = 0; // POST /v1/pairings: network error.
        final attempts = rig.posts.attempts;
        rig.pair(rig.tablet);
        expect(rig.findTrusted(tabletId), isNotNull);
        expect(rig.posts.attempts, greaterThan(attempts));
        expect(rig.unregistered, {tabletId});

        rig.reconnectAgent(); // Replays the tombstone: ignored.
        expect(rig.findTrusted(tabletId), isNotNull);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);

        rig.posts.failWith = null;
        async.elapse(const Duration(seconds: 60));
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, contains((agentId, tabletId)));

        rig.reconnectAgent(); // The POST cleared the tombstone.
        expect(rig.findTrusted(tabletId), isNotNull);

        rig.unpairFromPhone(rig.tablet);
        expect(rig.findTrusted(tabletId), isNull);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.untrusted);
      });
    });

    test('an unregistered pairing survives an agent restart and stays '
        'protected until the relay registers it', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        rig.unpairFromPhone(rig.tablet);
        rig.posts.failWith = 503;
        rig.pair(rig.tablet);
        expect(rig.unregistered, {tabletId});

        rig.restartAgent(); // The new connection replays the tombstone.
        expect(rig.unregistered, {tabletId});
        expect(rig.findTrusted(tabletId), isNotNull);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);

        final attempts = rig.posts.attempts;
        rig.posts.failWith = null;
        async.elapse(const Duration(seconds: 60));
        expect(rig.posts.attempts, greaterThan(attempts));
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, contains((agentId, tabletId)));
      });
    });

    test('a POST refused with another 4xx is dropped, trust is kept', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.posts.failWith = 404;
        rig.pair(rig.tablet);
        expect(rig.unregistered, isEmpty);
        expect(rig.findTrusted(tabletId), isNotNull);

        final attempts = rig.posts.attempts;
        async.elapse(const Duration(seconds: 60));
        rig.reconnectAgent();
        expect(rig.posts.attempts, attempts);
      });
    });

    test('a 401 waits for the next connect; 429 is retried with backoff', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.posts.failWith = 401;
        rig.pair(rig.tablet);
        expect(rig.unregistered, {tabletId});
        var attempts = rig.posts.attempts;
        async.elapse(const Duration(seconds: 60));
        expect(rig.posts.attempts, attempts); // No retry while connected.

        rig.posts.failWith = 429;
        rig.reconnectAgent();
        expect(
          rig.posts.attempts,
          greaterThan(attempts),
        ); // Retried on connect.
        attempts = rig.posts.attempts;
        async.elapse(const Duration(seconds: 30));
        expect(rig.posts.attempts, greaterThan(attempts + 1)); // Backoff.
        expect(rig.unregistered, {tabletId});

        rig.posts.failWith = null;
        async.elapse(const Duration(seconds: 60));
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, contains((agentId, tabletId)));
      });
    });

    test('revoke drops the unregistered mark; a POST that lands after the '
        'revoke is taken back', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        final gate = rig.posts.gate = Completer<void>();
        rig.pair(rig.tablet); // Its POST is held in flight.
        expect(rig.unregistered, {tabletId});

        drive(async, rig.service.revoke(tabletId));
        expect(rig.unregistered, isEmpty);
        rig.posts.gate = null;
        gate.complete();
        settle(async);
        expect(rig.relay.pairings, isEmpty);

        final attempts = rig.posts.attempts;
        rig.reconnectAgent();
        expect(rig.posts.attempts, attempts);
        expect(rig.findTrusted(tabletId), isNull);
      });
    });
  });
}
