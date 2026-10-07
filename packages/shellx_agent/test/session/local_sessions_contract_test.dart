import 'package:shellx_agent/shellx_agent.dart';

import '../support/local_sessions_contract.dart';
import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

SessionRig _rig() => SessionRig(
  maxSessions: 2,
  remoteTools: fakeRemoteTools(),
  directoryExists: (p) async => p == '/w',
);

void main() {
  runLocalSessionsContract('in-process SessionManager', () async {
    final rig = _rig();
    return LocalSessionsHarness(rig.manager, rig, () async {});
  });

  runLocalSessionsContract('RemoteLocalSessions over MuxServer', () async {
    final rig = _rig();
    final listener = TestListener();
    final server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: const MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i'),
      onQuit: () async {},
    )..serve(listener);
    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    final peer = await clientHandshake(
      client,
      secret: secret,
      app: 't',
      role: 'ui',
    );
    final remote = RemoteLocalSessions(MuxClient(client, early: peer.early));
    await remote.ready;
    return LocalSessionsHarness(remote, rig, () async {
      await client.close();
      await server.close();
    });
  });
}
