import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart' show AiFeature;
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/backend/client_backend.dart';
import 'package:shellx_mobile/core/platform/device_description.dart';

import '../../support/fakes.dart';

const String phoneId = '33333333-3333-4333-8333-333333333333';

void main() {
  late InMemoryKeyValueStore store;
  late List<http.Request> requests;
  late List<({Uri uri, Map<String, String> headers})> dials;
  late ShellxApi api;

  /// DELETE /v1/pairings answers with this status.
  var deleteStatus = 204;

  setUp(() {
    store = InMemoryKeyValueStore();
    requests = [];
    dials = [];
    deleteStatus = 204;
    api = ShellxApi(
      baseUri: Uri.parse('http://127.0.0.1:8787'),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE') {
          return deleteStatus == 204
              ? http.Response('', 204)
              : http.Response('{"error":{"code":"forbidden","message":"no"}}', deleteStatus);
        }
        if (request.method == 'PUT') return http.Response('', 204);
        return http.Response('[]', 200);
      }),
    )..token = 'token-1';
  });

  Future<ClientBackend> start() async => ClientBackend.start(
    relayBaseUri: Uri.parse('http://127.0.0.1:8787'),
    api: api,
    userId: 'user-1',
    deviceId: phoneId,
    identity: await NoiseKeyPair.generate(),
    store: store,
    appVersion: '1.0.0',
    device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
    // The socket connector fails, so no network is touched.
    connector: (uri, headers) async {
      dials.add((uri: uri, headers: headers));
      throw const SocketException('offline in tests');
    },
  );

  Future<void> pin(String agentId, {String userId = 'user-1', Uint8List? publicKey}) =>
      PinnedStore(store, userId: userId).add(
        PinnedMachine(agentId: agentId, publicKey: publicKey ?? Uint8List(32), pairedAt: DateTime(2026, 9, 25)),
      );

  test('wires the per-user PinnedStore; suspend/resume/dispose drive the relay', () async {
    await pin(agentA);
    await pin(agentB, userId: 'user-2');

    final backend = await start();
    addTearDown(backend.dispose);

    expect((await backend.pinnedMachines()).map((m) => m.agentId), [agentA]);
    expect(() => backend.machine('44444444-4444-4444-8444-444444444444'), throwsStateError);
    await pumpEventQueue();
    // ClientService.start() started the relay with the api's token. The failed dial is retried
    // after the first backoff (at least 500 ms), so the dial counts here are exact.
    expect(dials.single.uri, Uri.parse('ws://127.0.0.1:8787/v1/ws'));
    expect(dials.single.headers['Authorization'], 'Bearer token-1');
    expect(backend.relayState, isNot(RelayConnectionState.stopped));

    await backend.suspend();
    expect(backend.relayState, RelayConnectionState.stopped);
    await backend.resume();
    await pumpEventQueue();
    expect(dials, hasLength(2));
    expect(backend.relayState, isNot(RelayConnectionState.stopped));

    await backend.dispose();
    expect(backend.relayState, RelayConnectionState.stopped);
  });

  test('a disposed backend never dials again and refuses REST calls', () async {
    await pin(agentA);
    final backend = await start();
    await pumpEventQueue();
    await backend.dispose();
    // The next account signs in on the shared ShellxApi.
    api.token = 'token-2';

    await backend.resume();
    await backend.suspend();
    await backend.resume();
    await pumpEventQueue();

    expect(dials, hasLength(1));
    expect(backend.relayState, RelayConnectionState.stopped);
    expect(backend.devices, throwsStateError);
    expect(() => backend.unpair(agentA), throwsStateError);
    expect(requests, isEmpty);
  });

  test('registerPushToken PUTs the token and platform with the account token; refused after dispose', () async {
    final backend = await start();
    await backend.registerPushToken('fcm-token-1', PushPlatform.ios);
    final put = requests.single;
    expect(put.method, 'PUT');
    expect(put.url.path, '/v1/devices/me/push-token');
    expect(put.headers['authorization'], 'Bearer token-1');
    expect(put.body, '{"token":"fcm-token-1","platform":"ios"}');

    await backend.dispose();
    api.token = 'token-2';
    expect(() => backend.registerPushToken('fcm-token-1', PushPlatform.ios), throwsStateError);
    expect(requests, hasLength(1));
  });

  test('one session per pinned machine; with the relay down connect fails at once', () async {
    await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
    final backend = await start();
    addTearDown(backend.dispose);

    final machine = backend.machine(agentA);
    expect(backend.machine(agentA), same(machine));
    expect(machine.agentId, agentA);
    expect(machine.state, isA<MachineIdle>());
    expect(machine.tabs, isEmpty);
    // Never told by the agent yet: the picker treats it as an agent older than terminal sharing.
    expect(machine.desktopSharing, isNull);

    // Never the MachineFailed state object: MachineConnectionException after moving to MachineFailed.
    await expectLater(
      machine.connect(),
      throwsA(isA<MachineConnectionException>().having((e) => e.failure, 'failure', MachineConnectionFailure.timeout)),
    );
    expect(machine.state, isA<MachineFailed>());
  });

  test('AI sessions: one AiMachine per machine; a handle per link, a new one once the link closed', () async {
    await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
    final backend = await start();
    addTearDown(backend.dispose);

    final machine = backend.machine(agentA);
    final ai = machine.ai;
    expect(machine.ai, same(ai));
    // Nothing is known before the computer answered a list.
    expect(ai.supported, isNull);
    expect(ai.listing, isNull);

    final first = ai.attach('e.1');
    expect(ai.attach('e.1'), same(first));
    expect(ai.attach('e.2'), isNot(same(first)));
    expect(first.sid, 'e.1');
    expect(first.state, AiLinkState.attaching);
    expect(first.mirror.head, isNull);
    expect(first.closedReason, isNull);
    first.loadEarlier(); // nothing held, nothing to ask

    // The relay is down: the machine fails, and the link goes on waiting (the page shows the machine's state).
    await pumpEventQueue();
    expect(machine.state, isA<MachineFailed>());
    expect(first.state, AiLinkState.attaching);

    final events = <String>[];
    first.changes.listen((_) => events.add('change'), onDone: () => events.add('end'));
    first.detach();
    await pumpEventQueue();
    expect(first.state, AiLinkState.closed);
    expect(first.closedReason, 'detached');
    expect(events, ['change', 'end']);

    final again = ai.attach('e.1');
    expect(again, isNot(same(first)));
    expect(again.state, AiLinkState.attaching);
    expect(again.closedReason, isNull);
    expect(ai.attach('e.1'), same(again));
  });

  test('V2-2b: before the computer answered, nothing is known — no protocol, no feature, no session seen', () async {
    await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
    final backend = await start();
    addTearDown(backend.dispose);
    final ai = backend.machine(agentA).ai;
    expect(ai.protocol, isNull);
    expect(ai.can(AiFeature.config), isFalse);
    expect(ai.seen('e.1'), isNull);
  });

  test(
    'AI requests connect first and fail like the client\'s own; an oversized prompt never leaves the phone',
    () async {
      await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
      final backend = await start();
      addTearDown(backend.dispose);
      final ai = backend.machine(agentA).ai;

      Matcher offline() => throwsA(
        isA<MachineConnectionException>().having((e) => e.failure, 'failure', MachineConnectionFailure.timeout),
      );
      await expectLater(ai.prompt('e.1', 'hi'), offline());
      await expectLater(ai.answerPermission('e.1', 1, 'allow'), offline());
      await expectLater(ai.answerAsk('e.1', 2, const ElicitDecline()), offline());
      await expectLater(ai.cancel('e.1'), offline());
      await expectLater(ai.forceStop('e.1'), offline());
      await expectLater(ai.unqueue('e.1', 3), offline());
      await expectLater(ai.open('claude', 'k1'), offline());
      await expectLater(ai.watch(), offline());

      Matcher tooLarge() => throwsA(isA<AiRequestException>().having((e) => e.code, 'code', 'too_large'));
      await expectLater(ai.prompt('e.1', 'x' * (32 * 1024 + 1)), tooLarge());
      await expectLater(ai.answerAsk('e.1', 2, ElicitAccept({'text': 'x' * (48 * 1024)})), tooLarge());
    },
  );

  group('watching the AI list', () {
    /// What the machine does when the relay comes back, after the list was watched while the relay was
    /// down (and, with [unwatch], not watched any more): the handshakes it starts, and the frames it
    /// sends to the relay for them.
    Future<({int handshakes, int frames})> whenTheRelayReturns({required bool unwatch}) async {
      await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
      final relayUp = Completer<RelaySocket>();
      final backend = await ClientBackend.start(
        relayBaseUri: Uri.parse('http://127.0.0.1:8787'),
        api: api,
        userId: 'user-1',
        deviceId: phoneId,
        identity: await NoiseKeyPair.generate(),
        store: store,
        appVersion: '1.0.0',
        device: const DeviceDescription(name: 'iPhone 15', platform: DevicePlatform.ios),
        connector: (uri, headers) => relayUp.future,
      );
      addTearDown(backend.dispose);
      final machine = backend.machine(agentA);
      final handshakes = <MachineConnectionState>[];
      machine.states.listen((state) {
        if (state is MachineConnecting) handshakes.add(state);
      });

      // The relay is not up: watching can only fail, but the list is wanted from now on.
      await expectLater(machine.ai.watch(), throwsA(isA<MachineConnectionException>()));
      handshakes.clear();
      if (unwatch) machine.ai.unwatch();
      final relay = _QuietSocket();
      relayUp.complete(relay);
      await pumpEventQueue();
      return (handshakes: handshakes.length, frames: relay.sent.length);
    }

    test('a watched list brings the machine back when the relay returns', () async {
      final back = await whenTheRelayReturns(unwatch: false);
      expect(back.handshakes, 1);
      expect(back.frames, greaterThan(0), reason: 'the handshake goes out over the relay');
    });

    test('unwatch() goes through the adapter: nobody wants the channel for the list any more', () async {
      final back = await whenTheRelayReturns(unwatch: true);
      expect((back.handshakes, back.frames), (0, 0));
    });
  });

  test('an untrusted machine is forgotten: machine() throws, the pin is gone', () async {
    // A pin that cannot be used is treated as untrusted by shellx_client, like an HS2 `untrusted`.
    await pin(agentB, publicKey: Uint8List(31));
    final backend = await start();
    addTearDown(backend.dispose);

    await expectLater(
      backend.machine(agentB).connect(),
      throwsA(
        isA<MachineConnectionException>().having((e) => e.failure, 'failure', MachineConnectionFailure.untrusted),
      ),
    );

    expect(await backend.pinnedMachines(), isEmpty);
    expect(() => backend.machine(agentB), throwsStateError);
  });

  test('an unpair whose DELETE fails still forgets the machine; unpair again retries the DELETE', () async {
    await pin(agentA);
    final backend = await start();
    addTearDown(backend.dispose);
    backend.machine(agentA);

    deleteStatus = 403;
    await expectLater(backend.unpair(agentA), throwsA(isA<ApiException>()));
    expect(await backend.pinnedMachines(), isEmpty);
    expect(() => backend.machine(agentA), throwsStateError);

    deleteStatus = 204;
    await backend.unpair(agentA);
    final deletes = requests.where((r) => r.method == 'DELETE').toList();
    expect(deletes, hasLength(2));
    expect(deletes.last.url.path, '/v1/pairings/$agentA/$phoneId');
  });
}

/// A relay connection that says nothing and counts the frames the phone sends (the relay is "up").
final class _QuietSocket implements RelaySocket {
  final StreamController<Object> _messages = StreamController<Object>();
  final List<Uint8List> sent = [];

  @override
  Stream<Object> get messages => _messages.stream;

  @override
  void sendText(String text) {}

  @override
  void sendBytes(Uint8List bytes) => sent.add(bytes);

  @override
  Future<void> close([int? code, String? reason]) => _messages.close();

  @override
  int? get closeCode => null;
}
