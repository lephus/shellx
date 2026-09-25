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

/// Pairing ids of the pre-seeded trust entries (September 2024: older than
/// anything the rig's agent clock generates).
const phonePairingId = '01920000-0001-7000-8000-000000000000';
const tabletPairingId = '01920000-0002-7000-8000-000000000000';

/// The agent's clock in the rig: fake time since this instant.
final agentEpoch = DateTime.utc(2026, 9, 25, 12);

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
          pairingId: phonePairingId,
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
      clock: () => agentEpoch.add(async.elapsed),
      registrationBackoff: Backoff(random: Random(13)),
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

  /// Mobile ids whose pairing the relay has not acknowledged yet.
  Set<String> get unregistered => {
    for (final d in drive(async, trusted.unregistered())) d.mobileId,
  };

  /// The pairing id of [mobileId]'s trust entry.
  String pairingIdOf(String mobileId) => findTrusted(mobileId)!.pairingId;

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

/// Wraps the fake relay's HTTP client so the agent's pairing requests can
/// be scripted: [outcome] decides each `POST /v1/pairings` by its pairing
/// id, [gate] holds POSTs and [deleteGate] holds DELETEs. Everything else
/// passes through.
final class PairingPostControl extends http.BaseClient {
  PairingPostControl(this._inner);

  /// [outcome] value: the relay records the POST, then the response is lost.
  static const int lostResponse = -1;

  final http.Client _inner;

  /// null: the relay answers. 0: network error, the relay never sees it.
  /// [lostResponse]: see there. Any other value: answered with that HTTP
  /// status, the relay never sees it.
  int? Function(String pairingId) outcome = _relayAnswers;

  static int? _relayAnswers(String _) => null;

  /// Scripts every POST alike (see [outcome]).
  set failWith(int? status) => outcome = (_) => status;

  Completer<void>? gate;
  Completer<void>? deleteGate;

  /// `POST /v1/pairings` attempts, including failed ones.
  int attempts = 0;

  /// How the next DELETEs fail, in order (0: network error, else that HTTP
  /// status; the relay never sees them). Once used up, DELETEs pass.
  final deleteFailures = <int>[];

  /// `DELETE` attempts, including failed ones.
  int deleteAttempts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path == '/v1/pairings') {
      attempts++;
      final body = jsonDecode((request as http.Request).body) as Map;
      final pairingId = body['pairing_id'] as String;
      final held = gate;
      if (held != null) await held.future;
      final status = outcome(pairingId);
      if (status == 0) throw http.ClientException('network is down');
      if (status == lostResponse) {
        await (await _inner.send(request)).stream.drain<void>();
        throw http.ClientException('connection reset');
      }
      if (status != null) return _error(status);
    }
    if (request.method == 'DELETE') {
      deleteAttempts++;
      final held = deleteGate;
      if (held != null) await held.future;
      if (deleteFailures.isNotEmpty) {
        final status = deleteFailures.removeAt(0);
        if (status == 0) throw http.ClientException('network is down');
        return _error(status);
      }
    }
    return _inner.send(request);
  }

  static http.StreamedResponse _error(int status) => http.StreamedResponse(
    Stream.value(utf8.encode('{"error":{"code":"test","message":"test"}}')),
    status,
    headers: {'content-type': 'application/json'},
  );
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
  pairingId: tabletPairingId,
);

Map<String, String> pairingRemoved(String mobileId, String pairingId) => {
  'event': 'pairing_removed',
  'agent_id': agentId,
  'mobile_id': mobileId,
  'pairing_id': pairingId,
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

  // Final review M3.
  test('a message that fails to be handled does not drop the rest of its '
      'batch', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      final id = channel.messagesOf<SessionOpened>().single.id;
      final pty = rig.ptys.ptys.single..failWrites = StateError('pty gone');

      rig.send(channel, [
        InputMessage(id: id, data: Uint8List.fromList([0x61])),
        const SessionList(),
      ]);
      expect(channel.messagesOf<SessionListResult>(), hasLength(1));

      pty.failWrites = null;
      rig.send(channel, [
        InputMessage(id: id, data: Uint8List.fromList([0x62])),
      ]);
      expect(pty.writtenText, 'b');
      expect(rig.service.activeChannelCount, 1);
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
      expect(rig.relay.pairings, {(agentId, tabletId): paired.pairingId});
      expect(rig.service.activeChannelCount, 0);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);
    });
  });

  // Final review M5.
  test('the pairing URI carries a copy of the agent key, not the identity’s '
      'own bytes', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      expect(uri.agentPublicKey, agentKey.publicKey);
      expect(uri.agentPublicKey, isNot(same(agentKey.publicKey)));
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
      rig.relay.pairings[(agentId, phoneId)] = phonePairingId;
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

  test(
    'EVENT pairing_removed for this agent and this pairing removes trust',
    () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.handshake(rig.phone);
        rig.relay.sendEvent(agentId, {
          'event': 'pairing_removed',
          'agent_id': 'a0000000-0000-4000-8000-00000000ffff',
          'mobile_id': phoneId,
          'pairing_id': phonePairingId,
        });
        // An older pairing of the same phone, or no id at all: not this one.
        rig.relay.sendEvent(
          agentId,
          pairingRemoved(phoneId, '01910000-0001-7000-8000-000000000000'),
        );
        rig.relay.sendEvent(agentId, {
          'event': 'pairing_removed',
          'agent_id': agentId,
          'mobile_id': phoneId,
        });
        settle(async);
        expect(rig.findTrusted(phoneId), isNotNull);
        expect(rig.service.activeChannelCount, 1);

        rig.relay.sendEvent(agentId, pairingRemoved(phoneId, phonePairingId));
        settle(async);
        expect(rig.findTrusted(phoneId), isNull);
        expect(rig.service.activeChannelCount, 0);
      });
    },
  );

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
      rig.relay.pairings[(agentId, phoneId)] = phonePairingId;
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

      rig.relay.sendEvent(agentId, pairingRemoved(phoneId, phonePairingId));
      rig.relay.sendEvent(agentId, pairingRemoved(phoneId, phonePairingId));
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

  // Fix round 1: pairings carry agent-generated UUIDv7 ids; trust entries,
  // events, 410s and revokes are matched by id.
  group('pairing ids', () {
    test('pair.confirm stores a fresh UUIDv7 pairing id and registers it', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        final id = rig.pairingIdOf(tabletId);
        expect(isPairingId(id), isTrue);
        expect(id.compareTo(phonePairingId), greaterThan(0));
        expect(
          rig.events.whereType<MobilePaired>().single.device.pairingId,
          id,
        );
        expect(rig.relay.pairings, {(agentId, tabletId): id});
        expect(rig.unregistered, isEmpty);

        rig.pair(rig.tablet); // Re-pairing makes a newer id.
        expect(rig.pairingIdOf(tabletId).compareTo(id), greaterThan(0));
      });
    });

    // Review I1: POST#1 commits but its response is lost, the phone unpairs,
    // and the retry must not bring the pairing back.
    test('an unpair after a POST whose response was lost removes trust; the '
        'retry does not re-create the pairing', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.posts.failWith = PairingPostControl.lostResponse;
        rig.pair(rig.tablet);
        final id = rig.pairingIdOf(tabletId);
        expect(rig.relay.pairings, {(agentId, tabletId): id}); // Committed.
        expect(rig.unregistered, {tabletId}); // The agent does not know.

        rig.posts.failWith = null;
        rig.unpairFromPhone(rig.tablet);
        expect(rig.findTrusted(tabletId), isNull); // The event has its id.
        async.elapse(const Duration(seconds: 60)); // Any retry has run.
        expect(rig.findTrusted(tabletId), isNull);
        expect(rig.relay.pairings, isEmpty);
        rig.reconnectAgent();
        expect(rig.findTrusted(tabletId), isNull);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.untrusted);
      });
    });

    test('an unpair missed while offline ends the pairing on reconnect: the '
        'tombstone and the retried POST (410) both carry its id', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.posts.failWith = PairingPostControl.lostResponse;
        rig.pair(rig.tablet);
        rig.posts.failWith = null;

        rig.relay.setReachable(agentId, false);
        rig.relay.dropConnection(agentId);
        rig.unpairFromPhone(rig.tablet);
        rig.relay.setReachable(agentId, true);
        async.elapse(const Duration(seconds: 30));
        expect(rig.relay.isOnline(agentId), isTrue);
        expect(rig.findTrusted(tabletId), isNull);
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, isEmpty);
      });
    });

    test('a stale tombstone with an older id is ignored after a re-pair (POST '
        'still failing); once registered, a real unpair removes trust', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        final oldId = rig.pairingIdOf(tabletId);
        rig.unpairFromPhone(rig.tablet); // Tombstone with oldId.
        expect(rig.findTrusted(tabletId), isNull);

        rig.posts.failWith = 0;
        rig.pair(rig.tablet);
        final newId = rig.pairingIdOf(tabletId);
        expect(rig.unregistered, {tabletId});

        rig.reconnectAgent(); // Replays the tombstone (oldId): ignored.
        rig.relay.sendEvent(agentId, pairingRemoved(tabletId, oldId));
        settle(async);
        expect(rig.pairingIdOf(tabletId), newId);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);

        rig.posts.failWith = null;
        async.elapse(const Duration(seconds: 60));
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, {(agentId, tabletId): newId});
        rig.reconnectAgent(); // The newer POST cleared the tombstone.
        // A late event of the old pairing, now that nothing is pending.
        rig.relay.sendEvent(agentId, pairingRemoved(tabletId, oldId));
        settle(async);
        expect(rig.pairingIdOf(tabletId), newId);

        rig.unpairFromPhone(rig.tablet);
        expect(rig.findTrusted(tabletId), isNull);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.untrusted);
      });
    });

    test('a 410 removes trust only while the entry still has that id', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        var trustChanges = 0;
        rig.trusted.changes.listen((_) => trustChanges++);

        // A 410 for a pairing that was replaced meanwhile: ignored.
        final gate = rig.posts.gate = Completer<void>();
        rig.pair(rig.tablet); // POST (first id) held.
        final firstId = rig.pairingIdOf(tabletId);
        rig.pair(rig.tablet);
        final secondId = rig.pairingIdOf(tabletId);
        rig.posts.outcome = (id) => id == firstId ? 410 : null;
        rig.posts.gate = null;
        gate.complete();
        settle(async);
        expect(rig.pairingIdOf(tabletId), secondId);
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, {(agentId, tabletId): secondId});

        // A 410 for the current pairing: trust goes, the tray hears of it.
        rig.posts.failWith = 410;
        final changes = trustChanges;
        rig.pair(rig.spare);
        expect(rig.findTrusted(spareId), isNull);
        expect(rig.unregistered, isEmpty);
        expect(trustChanges, changes + 2); // Added, then removed.
        expect(rig.handshake(rig.spare).status, HandshakeStatus.untrusted);
      });
    });

    test('a stale 2xx for an old id does not mark the new pairing', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        final first = rig.posts.gate = Completer<void>();
        rig.pair(rig.tablet); // POST (first id) held.
        rig.pair(rig.tablet); // Re-paired: a newer id.
        final newId = rig.pairingIdOf(tabletId);

        final second = rig.posts.gate = Completer<void>();
        first.complete(); // The old POST succeeds; the new one is held.
        settle(async);
        expect(rig.unregistered, {tabletId});
        expect(rig.pairingIdOf(tabletId), newId);

        rig.posts.gate = null;
        second.complete();
        settle(async);
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, {(agentId, tabletId): newId});
        expect(rig.pairingIdOf(tabletId), newId);
      });
    });

    test('revoke then a quick re-pair: the late DELETE (old id) does not '
        'delete the new pairing', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        final oldId = rig.pairingIdOf(tabletId);
        final gate = rig.posts.deleteGate = Completer<void>();
        final revoked = rig.service.revoke(tabletId);
        settle(async);
        expect(rig.findTrusted(tabletId), isNull);

        rig.pair(rig.tablet);
        final newId = rig.pairingIdOf(tabletId);
        expect(newId, isNot(oldId));
        expect(rig.relay.pairings, {(agentId, tabletId): newId});

        rig.posts.deleteGate = null;
        gate.complete();
        drive(async, revoked);
        settle(async);
        expect(rig.relay.pairings, {(agentId, tabletId): newId});
        expect(rig.pairingIdOf(tabletId), newId);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);
      });
    });

    test('an unregistered pairing survives an agent restart and its POST '
        'resumes', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        rig.pair(rig.tablet);
        rig.unpairFromPhone(rig.tablet);
        rig.posts.failWith = 503;
        rig.pair(rig.tablet);
        final id = rig.pairingIdOf(tabletId);
        expect(rig.unregistered, {tabletId});

        rig.restartAgent(); // The new connection replays the old tombstone.
        expect(rig.unregistered, {tabletId});
        expect(rig.pairingIdOf(tabletId), id);
        expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);

        final attempts = rig.posts.attempts;
        rig.posts.failWith = null;
        async.elapse(const Duration(seconds: 60));
        expect(rig.posts.attempts, greaterThan(attempts));
        expect(rig.unregistered, isEmpty);
        expect(rig.relay.pairings, {(agentId, tabletId): id});
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

    // Final review M2: the DELETE is retried like the phone's unpair.
    test('revoke retries the pairing DELETE after a 5xx or a network error '
        '(3 attempts in all), never after a 4xx', () {
      fakeAsync((async) {
        final rig = AgentRig(async);
        drive(async, rig.trusted.add(trustedTablet()));
        rig.relay.pairings[(agentId, phoneId)] = phonePairingId;
        rig.relay.pairings[(agentId, tabletId)] = tabletPairingId;

        rig.posts.deleteFailures.addAll([503, 0]);
        drive(async, rig.service.revoke(phoneId));
        expect(rig.posts.deleteAttempts, 3);
        expect(rig.relay.pairings.keys, [(agentId, tabletId)]);

        rig.posts.deleteFailures.addAll([500, 500, 500]);
        drive(async, rig.service.revoke(tabletId));
        expect(rig.posts.deleteAttempts, 6); // Gave up after three.
        expect(rig.relay.pairings, contains((agentId, tabletId)));

        drive(async, rig.trusted.add(trustedTablet()));
        rig.posts.deleteFailures.add(404);
        drive(async, rig.service.revoke(tabletId));
        async.elapse(const Duration(seconds: 5));
        expect(rig.posts.deleteAttempts, 7);
        expect(rig.posts.deleteFailures, isEmpty);
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

  // Review M3.
  test('an HS2 that cannot be sent installs no channel: the previous one '
      'keeps working', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.relay.onData = (from, to, frame) =>
          from == agentId && frame.payload.first == PayloadKind.hs2.wire
          ? throw StateError('socket write failed')
          : frame;

      expect(rig.handshake(rig.phone).status, isNull); // No HS2.
      expect(rig.service.activeChannelCount, 1);
      expect(rig.sessions.sessions.single.attachedMobileId, phoneId);
      rig.send(channel, [const SessionList()]);
      expect(channel.messagesOf<SessionListResult>(), hasLength(1));
    });
  });
}
