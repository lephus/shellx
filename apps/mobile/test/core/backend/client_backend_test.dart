import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    expect((await backend.pinnedMachines()).map((m) => m.agentId), [agentA]);
    expect(() => backend.machine('44444444-4444-4444-8444-444444444444'), throwsStateError);
    await pumpEventQueue();
    // ClientService.start() started the relay with the api's token.
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

  test('one session per pinned machine; with the relay down connect fails at once', () async {
    await pin(agentA, publicKey: (await NoiseKeyPair.generate()).publicKey);
    final backend = await start();
    addTearDown(backend.dispose);

    final machine = backend.machine(agentA);
    expect(backend.machine(agentA), same(machine));
    expect(machine.agentId, agentA);
    expect(machine.state, isA<MachineIdle>());
    expect(machine.tabs, isEmpty);

    // Never the MachineFailed state object: MachineConnectionException after moving to MachineFailed.
    await expectLater(
      machine.connect(),
      throwsA(isA<MachineConnectionException>().having((e) => e.failure, 'failure', MachineConnectionFailure.timeout)),
    );
    expect(machine.state, isA<MachineFailed>());
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
