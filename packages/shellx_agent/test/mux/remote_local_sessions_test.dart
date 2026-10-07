import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/local_sessions_contract.dart';
import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

/// Records what the client sends; everything else passes through.
final class _Spy implements MuxConnection {
  _Spy(this._inner);
  final MuxConnection _inner;
  final sent = <MuxMessage>[];
  @override
  Stream<MuxMessage> get messages => _inner.messages;
  @override
  void send(MuxMessage message) {
    sent.add(message);
    _inner.send(message);
  }

  @override
  int get pendingBytes => _inner.pendingBytes;
  @override
  Future<void> get drained => _inner.drained;
  @override
  void pauseInput() => _inner.pauseInput();
  @override
  void resumeInput() => _inner.resumeInput();
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
}

const _self = MuxPeerInfo(protocol: kMuxProtocol, app: 't', instance: 'i');

void main() {
  late SessionRig rig;
  late TestListener listener;
  late MuxServer server;

  Future<(MuxConnection, MuxPeerInfo)> connect() async {
    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    final peer = await clientHandshake(
      client,
      secret: secret,
      app: 't',
      role: 'ui',
    );
    return (client, peer);
  }

  MuxServer build({int stopAbove = 2097152, int resumeBelow = 524288}) =>
      server = MuxServer(
        sessions: rig.manager,
        secret: secret,
        self: _self,
        onQuit: () async {},
        stopAbove: stopAbove,
        resumeBelow: resumeBelow,
      )..serve(listener);

  setUp(() {
    rig = SessionRig();
    listener = TestListener();
  });
  tearDown(() async => server.close());

  test('pending requests fail with disconnected when the daemon goes; '
      'disconnected completes and connected turns false', () async {
    build();
    final (conn, peer) = await connect();
    final remote = RemoteLocalSessions(MuxClient(conn, early: peer.early));
    await remote.ready;
    expect(remote.connected, isTrue);
    final client = MuxClient(conn);
    final pending = client.request(MuxType.daemonQuit);
    final failed = expectLater(
      pending,
      throwsA(
        isA<MuxRemoteException>().having((e) => e.code, 'code', 'disconnected'),
      ),
    );
    await server.close();
    await failed;
    await remote.disconnected;
    expect(remote.connected, isFalse);
    await expectLater(
      remote.open(cols: 80, rows: 24),
      throwsA(isA<MuxRemoteException>()),
    );
  });

  test('request: result completes, error throws with code and message; '
      'send is fire-and-forget', () async {
    build();
    final (conn, peer) = await connect();
    final client = MuxClient(conn, early: peer.early);
    final r = await client.request(MuxType.daemonStatus);
    expect(r.get<int>('protocol'), kMuxProtocol);
    await expectLater(
      client.request('nonsense'),
      throwsA(
        isA<MuxRemoteException>().having(
          (e) => e.code,
          'code',
          MuxError.unknownType,
        ),
      ),
    );
    client.send(MuxType.sessionsWatchPorts, {'visible': true});
    await client.close();
  });

  test('onRequest answers a daemon → UI request on the same q, with '
      'result or error; without a handler it is unknown_type', () async {
    build();
    final (conn, peer) = await connect();
    final client = MuxClient(
      conn,
      early: peer.early,
      onRequest: (m) async {
        if (m.type == 'ui.ok') return {'got': m.get<int>('n')};
        throw const CliFailure('nope', 'because');
      },
    );
    client.send(MuxType.daemonStatus); // primes the link
    await pumpEventQueue();
    final up = server.uiApi;
    final ok = await up.handle(const MuxMessage('ui.ok', fields: {'n': 7}));
    expect(ok['got'], 7);
    await expectLater(
      up.handle(const MuxMessage('ui.fail')),
      throwsA(
        isA<CliFailure>()
            .having((e) => e.code, 'code', 'nope')
            .having((e) => e.message, 'message', 'because'),
      ),
    );
    await client.close();
  });

  test('early messages reach the first events listener', () async {
    build();
    final (conn, _) = await connect();
    final client = MuxClient(
      conn,
      early: const [
        MuxMessage(MuxType.sessionsChanged, fields: {'sessions': <Object?>[]}),
      ],
    );
    final first = await client.events.first;
    expect(first.type, MuxType.sessionsChanged);
    await client.close();
  });

  test('acks are sent after 64 KiB or 100 ms', () async {
    build();
    final (conn, peer) = await connect();
    final spy = _Spy(conn);
    final remote = RemoteLocalSessions(MuxClient(spy, early: peer.early));
    await remote.ready;
    final id = await remote.open(cols: 80, rows: 24);
    final view = remote.view(id);
    var got = 0;
    view.output.listen((d) => got += d.length);
    List<MuxMessage> acks() => [
      for (final m in spy.sent)
        if (m.type == MuxType.viewAck) m,
    ];
    rig.pty(0).emit('a' * 100);
    await eventually(() => got == 100);
    expect(acks(), isEmpty); // under the window: waits for the timer
    await eventually(() => acks().isNotEmpty);
    expect(acks().single.get<int>('bytes'), 100);
    expect(acks().single.get<int>('id'), id);
    for (var i = 0; i < 5; i++) {
      rig.pty(0).emit('b' * 16384);
    }
    await eventually(() => got == 100 + 5 * 16384);
    await eventually(
      () => acks().fold<int>(0, (n, m) => n + m.get<int>('bytes')!) >= 65636,
    );
    view.dispose();
  });

  test('ackEvery acks at once when the window is reached', () async {
    build();
    final (conn, peer) = await connect();
    final spy = _Spy(conn);
    final remote = RemoteLocalSessions(
      MuxClient(spy, early: peer.early),
      ackDelay: const Duration(hours: 1),
    );
    await remote.ready;
    final id = await remote.open(cols: 80, rows: 24);
    final view = remote.view(id);
    var got = 0;
    view.output.listen((d) => got += d.length);
    rig.pty(0).emit('x' * 65535);
    await eventually(() => got == 65535);
    expect(spy.sent.where((m) => m.type == MuxType.viewAck), isEmpty);
    rig.pty(0).emit('y');
    await eventually(() => spy.sent.any((m) => m.type == MuxType.viewAck));
    expect(
      spy.sent.firstWhere((m) => m.type == MuxType.viewAck).get<int>('bytes'),
      65536,
    );
    view.dispose();
  });

  test('view.reset writes clear-screen then the data; never a half '
      'escape sequence', () async {
    build(stopAbove: 1000, resumeBelow: 200);
    final (conn, peer) = await connect();
    final remote = RemoteLocalSessions(
      MuxClient(conn, early: peer.early),
      ackEvery: 1 << 30,
      ackDelay: const Duration(hours: 1),
    );
    await remote.ready;
    final id = await remote.open(cols: 80, rows: 24);
    final view = remote.view(id);
    final chunks = <Uint8List>[];
    view.output.listen(chunks.add);
    String text() => utf8.decode([for (final c in chunks) ...c]);
    for (final ch in ['a', 'b', 'c', 'd']) {
      rig.pty(0).emit(ch * 600);
      await pumpEventQueue();
    }
    // The daemon stops at 1,200 unacked bytes; the UI then catches up.
    await eventually(() => text().length >= 1200);
    final acked = text().length;
    final client = MuxClient(conn);
    client.send(MuxType.viewAck, {'id': id, 'bytes': acked});
    await eventually(() => text().contains('\r\n\x1b[H\x1b[2J'));
    final t = text();
    final at = t.indexOf('\r\n\x1b[H\x1b[2J');
    expect(
      t.substring(at + '\r\n\x1b[H\x1b[2J'.length),
      'a' * 600 + 'b' * 600 + 'c' * 600 + 'd' * 600,
    );
    view.dispose();
  });

  test('sessions mirrors sessions.changed; open waits until the new '
      'session is listed', () async {
    build();
    final (conn, peer) = await connect();
    final remote = RemoteLocalSessions(MuxClient(conn, early: peer.early));
    await remote.ready;
    expect(remote.sessions, isEmpty);
    final id = await remote.open(cols: 80, rows: 24);
    expect(remote.sessions.map((s) => s.id), [id]); // at once, no waiting
    final changed = remote.changes.first;
    await rig.manager.open(cols: 80, rows: 24);
    await changed;
    await eventually(() => remote.sessions.length == 2);
  });

  test('view.exit ends the view; the view does not end when the daemon '
      'goes (no exit line, D15)', () async {
    build();
    final (conn, peer) = await connect();
    final remote = RemoteLocalSessions(MuxClient(conn, early: peer.early));
    await remote.ready;
    final id = await remote.open(cols: 80, rows: 24);
    final view = remote.view(id);
    var ended = false;
    var exited = false;
    view.output.listen((_) {}, onDone: () => ended = true);
    unawaited(view.exitCode.then((_) => exited = true));
    await server.close();
    await remote.disconnected;
    await pumpEventQueue();
    expect(exited, isFalse);
    expect(ended, isFalse);
    view.write(Uint8List.fromList([1])); // dropped, not thrown
  });
}
