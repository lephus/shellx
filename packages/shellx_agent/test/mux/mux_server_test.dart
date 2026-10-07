import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_ui_api.dart';
import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

final class FakeBridge implements AgentBridge {
  final controller = StreamController<Map<String, Object?>>.broadcast();
  @override
  Map<String, Object?> current = {'signedIn': true};
  final calls = <(String, Map<String, Object?>)>[];
  @override
  Stream<Map<String, Object?>> get states => controller.stream;
  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    calls.add((method, args));
    if (method == 'boom') throw StateError('x');
    return {'echo': method};
  }
}

const self = MuxPeerInfo(
  protocol: kMuxProtocol,
  app: '1.6.0',
  instance: 'inst1',
  pid: 42,
  caps: ['cli'],
);

Future<MuxConnection> attach(
  TestListener l, {
  String role = 'ui',
  Uint8List? withSecret,
  String? token,
}) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  l.push(daemonSide);
  final peer = await clientHandshake(
    client,
    secret: withSecret ?? secret,
    app: '1.6.0',
    role: role,
    token: token,
  );
  inbox[client] = [...peer.early];
  client.messages.listen(inbox[client]!.add);
  return client;
}

/// Everything a client got since its handshake (a refusal arrives right
/// after `ready`, before a test could listen).
final inbox = Expando<List<MuxMessage>>();

Future<MuxMessage> firstError(MuxConnection c) async {
  await pumpEventQueue();
  return inbox[c]!.firstWhere((m) => m.type == MuxType.error);
}

Future<MuxMessage> request(MuxConnection c, MuxMessage m) {
  final reply = c.messages.firstWhere(
    (r) => r.q == m.q && (r.type == MuxType.result || r.type == MuxType.error),
  );
  c.send(m);
  return reply;
}

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late SessionRig rig;
  late TestListener listener;
  late MuxServer server;
  late FakeBridge bridge;
  late Completer<void> quitGate;
  var quitCalls = 0;
  final uiChanges = <bool>[];
  var q = 0;
  MuxMessage req(String type, [Map<String, Object?> f = const {}]) =>
      MuxMessage(type, q: ++q, fields: f);

  MuxServer build({int stopAbove = 2097152, int resumeBelow = 524288}) {
    server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: self,
      agent: bridge,
      onQuit: () async {
        quitCalls++;
        await quitGate.future;
      },
      onUiChanged: uiChanges.add,
      stopAbove: stopAbove,
      resumeBelow: resumeBelow,
    )..serve(listener);
    return server;
  }

  setUp(() {
    rig = SessionRig();
    listener = TestListener();
    bridge = FakeBridge();
    quitGate = Completer<void>()..complete();
    quitCalls = 0;
    uiChanges.clear();
    q = 0;
  });

  tearDown(() async => server.close());

  test('sessions.list returns the list; nothing arrives unsolicited; '
      'a later open fires sessions.changed', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    build();
    final c = await attach(listener);
    final seen = <MuxMessage>[];
    c.messages.listen(seen.add);
    await pumpEventQueue();
    expect(seen, isEmpty);
    final r = await request(c, req(MuxType.sessionsList));
    final list = r.get<List<Object?>>('sessions')!;
    expect(list, hasLength(1));
    expect(summaryFromWire(list.single! as Map<Object?, Object?>).id, id);
    final changed = c.messages.firstWhere(
      (m) => m.type == MuxType.sessionsChanged,
    );
    await rig.manager.open(cols: 80, rows: 24);
    expect((await changed).get<List<Object?>>('sessions'), hasLength(2));
  });

  test('sessions.open: result{id}; PTY started in home or the cwd; '
      'tabId and launch are carried', () async {
    build();
    final c = await attach(listener);
    final r = await request(
      c,
      req(MuxType.sessionsOpen, {'cols': 80, 'rows': 24}),
    );
    expect(r.type, MuxType.result);
    expect(r.get<int>('id'), isNotNull);
    expect(rig.pty(0).workingDirectory, '/Users/test');
    final r2 = await request(
      c,
      req(MuxType.sessionsOpen, {
        'cols': 80,
        'rows': 24,
        'tabId': r.get<int>('id'),
      }),
    );
    expect(r2.type, MuxType.result);
    expect(rig.pty(1).environment['SHELLX_TAB_ID'], '${r.get<int>('id')}');
    final bad = await request(
      c,
      req(MuxType.sessionsOpen, {
        'cols': 80,
        'rows': 24,
        'launch': {'kind': 'nope'},
      }),
    );
    expect(bad.get<String>('code'), MuxError.spawnFailed);
    expect(bad.get<String>('message'), 'bad_launch');
  });

  test('session limit and spawn failure become typed errors', () async {
    rig = SessionRig(maxSessions: 1);
    build();
    final c = await attach(listener);
    await request(c, req(MuxType.sessionsOpen, {'cols': 80, 'rows': 24}));
    final limit = await request(
      c,
      req(MuxType.sessionsOpen, {'cols': 80, 'rows': 24}),
    );
    expect(limit.get<String>('code'), MuxError.sessionLimit);
    expect(limit.get<int>('max'), 1);
    rig = SessionRig();
    await server.close();
    build();
    final c2 = await attach(listener);
    rig.factory.failWith = StateError('no pty');
    final spawn = await request(
      c2,
      req(MuxType.sessionsOpen, {'cols': 80, 'rows': 24}),
    );
    expect(spawn.get<String>('code'), MuxError.spawnFailed);
  });

  test('sessions.close, watchPorts, notify', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    build();
    final c = await attach(listener);
    final w = await request(
      c,
      req(MuxType.sessionsWatchPorts, {'visible': true}),
    );
    expect(w.type, MuxType.result);
    final n = await request(
      c,
      req(MuxType.sessionsNotify, {'id': id, 'title': 't', 'body': 'hi'}),
    );
    expect(n.get<bool>('ok'), isTrue);
    final n2 = await request(
      c,
      req(MuxType.sessionsNotify, {'id': 999, 'body': 'hi'}),
    );
    expect(n2.type, MuxType.result);
    expect(n2.get<bool>('ok'), isFalse);
    final cl = await request(c, req(MuxType.sessionsClose, {'id': id}));
    expect(cl.type, MuxType.result);
    expect(rig.pty(0).killed, isTrue);
  });

  test('view.open streams backlog then live output, then exit', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    rig.pty(0).emit('abc');
    await pumpEventQueue();
    build();
    final c = await attach(listener);
    final out = <String>[];
    final exit = Completer<MuxMessage>();
    c.messages.listen((m) {
      if (m.type == MuxType.viewOut) {
        out.add(utf8.decode(m.get<Uint8List>('data')!));
      }
      if (m.type == MuxType.viewExit) exit.complete(m);
    });
    await request(c, req(MuxType.viewOpen, {'id': id}));
    await pumpEventQueue();
    expect(out, ['abc']);
    rig.pty(0).emit('def');
    await pumpEventQueue();
    expect(out, ['abc', 'def']);
    rig.pty(0).exit(3);
    final e = await exit.future;
    expect(e.get<int>('code'), 3);
    expect(e.get<bool>('onRequest'), isFalse);
  });

  test('view of a missing session exits -1 onRequest', () async {
    build();
    final c = await attach(listener);
    final exit = c.messages.firstWhere((m) => m.type == MuxType.viewExit);
    await request(c, req(MuxType.viewOpen, {'id': 77}));
    final e = await exit;
    expect(e.get<int>('id'), 77);
    expect(e.get<int>('code'), -1);
    expect(e.get<bool>('onRequest'), isTrue);
  });

  test('view.write reaches the PTY and the desktop drives', () async {
    final id = await rig.open('m1'); // a phone session: the phone drives
    build();
    final c = await attach(listener);
    await request(c, req(MuxType.viewOpen, {'id': id}));
    final driver = c.messages.firstWhere(
      (m) => m.type == MuxType.viewDriver && m.get<String>('side') == 'desktop',
    );
    c.send(MuxMessage(MuxType.viewWrite, fields: {'id': id, 'data': b('ls')}));
    c.send(
      MuxMessage(
        MuxType.viewResize,
        fields: {'id': id, 'cols': 100, 'rows': 30},
      ),
    );
    await driver;
    expect(rig.pty(0).writtenText, 'ls');
  });

  test('ack window: stops above the limit, resets below (D11)', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    build(stopAbove: 1000, resumeBelow: 200);
    final c = await attach(listener);
    final got = <MuxMessage>[];
    c.messages.listen(got.add);
    await request(c, req(MuxType.viewOpen, {'id': id}));
    String chunk(String ch) => ch * 600;
    for (final ch in ['a', 'b', 'c']) {
      rig.pty(0).emit(chunk(ch));
      await pumpEventQueue();
    }
    final bytes = got
        .where((m) => m.type == MuxType.viewOut)
        .fold<int>(0, (n, m) => n + m.get<Uint8List>('data')!.length);
    expect(bytes, lessThanOrEqualTo(1600));
    rig.pty(0).emit(chunk('d'));
    await pumpEventQueue();
    expect(
      got
          .where((m) => m.type == MuxType.viewOut)
          .fold<int>(0, (n, m) => n + m.get<Uint8List>('data')!.length),
      bytes,
    );
    got.clear();
    c.send(MuxMessage(MuxType.viewAck, fields: {'id': id, 'bytes': 1500}));
    await pumpEventQueue();
    expect(got.first.type, MuxType.viewReset);
    final after = utf8.decode([
      for (final m in got.where((m) => m.type == MuxType.viewOut))
        ...m.get<Uint8List>('data')!,
    ]);
    expect(after, chunk('a') + chunk('b') + chunk('c') + chunk('d'));
    got.clear();
    rig.pty(0).emit('live');
    await pumpEventQueue();
    expect(utf8.decode(got.single.get<Uint8List>('data')!), 'live');
  });

  test('a second ui is refused busy; another role is unsupported', () async {
    build();
    final ui = await attach(listener);
    final second = await attach(listener);
    final busy = await firstError(second);
    expect(busy.get<String>('code'), MuxError.busy);
    await second.done;
    final odd = await attach(listener, role: 'browser');
    final unsupported = await firstError(odd);
    expect(unsupported.get<String>('code'), MuxError.unsupportedRole);
    await odd.done;
    expect(server.uiAttached, isTrue);
    await ui.close();
  });

  test('role cli is adopted by the CliHost', () async {
    final host = CliHost.adopted(
      ui: FakeUiApi(),
      enabled: () => true,
      token: 'tok',
      allowExternal: () => false,
      appVersion: '1.6.0',
      hostKind: () => 'daemon',
      uiAttached: () => server.uiAttached,
    );
    build();
    server.cli = host;
    final c = await attach(listener, role: 'cli', token: 'tok');
    final r = await request(c, req(CliType.apiVersion));
    expect(r.get<String>('host'), 'daemon');
    expect(r.get<bool>('ui'), isFalse);
    expect(host.clientCount, 1);
    expect(server.uiAttached, isFalse);
    // Without a CliHost the role is unsupported.
    server.cli = null;
    final c2 = await attach(listener, role: 'cli');
    final e = await firstError(c2);
    expect(e.get<String>('code'), MuxError.unsupportedRole);
    await host.stop();
  });

  test('ui.* from a cli client goes to the attached ui and back; '
      'no ui is not_found', () async {
    final host = CliHost.adopted(
      ui: (build()).uiApi,
      enabled: () => true,
      token: 'tok',
      allowExternal: () => false,
      appVersion: '1.6.0',
      hostKind: () => 'daemon',
      uiAttached: () => server.uiAttached,
    );
    server.cli = host;
    final cli = await attach(listener, role: 'cli', token: 'tok');
    final none = await request(cli, req(CliType.uiLs));
    expect(none.get<String>('code'), MuxError.notFound);

    final ui = await attach(listener);
    ui.messages.listen((m) {
      if (m.type == CliType.uiLs && m.q != null) {
        ui.send(
          MuxMessage(
            MuxType.result,
            q: m.q,
            fields: {'tabs': 2, 'seen': m.get<String>('x')},
          ),
        );
      }
    });
    await request(ui, req(MuxType.sessionsList));
    final ok = await request(cli, req(CliType.uiLs, {'x': 'y'}));
    expect(ok.type, MuxType.result);
    expect(ok.get<int>('tabs'), 2);
    expect(ok.get<String>('seen'), 'y');

    ui.messages.listen((m) {
      if (m.type == CliType.uiFocus && m.q != null) {
        ui.send(
          MuxMessage(
            MuxType.error,
            q: m.q,
            fields: {'code': 'ambiguous', 'message': 'two'},
          ),
        );
      }
    });
    final err = await request(cli, req(CliType.uiFocus));
    expect(err.get<String>('code'), 'ambiguous');
    await host.stop();
  });

  test('unknown request → unknown_type; unknown event ignored; garbage '
      'closes', () async {
    build();
    final c = await attach(listener);
    final r = await request(c, req('x.y'));
    expect(r.get<String>('code'), MuxError.unknownType);
    final seen = <MuxMessage>[];
    c.messages.listen(seen.add);
    c.send(const MuxMessage('x.z'));
    await pumpEventQueue();
    expect(seen, isEmpty);
    final bad = await request(c, req(MuxType.sessionsOpen, {'cols': 'x'}));
    expect(bad.get<String>('code'), MuxError.badRequest);

    final toServer = StreamController<Uint8List>();
    final toClient = StreamController<Uint8List>();
    final serverSide = StreamMuxConnection(
      toServer.stream,
      toClient.add,
      () async {},
    );
    listener.push(serverSide);
    final client = StreamMuxConnection(
      toClient.stream,
      toServer.add,
      () async {},
    );
    await clientHandshake(client, secret: secret, app: '1.6.0', role: 'cli');
    toServer.add(Uint8List.fromList([0, 0, 0, 1, 0xff]));
    await serverSide.done.timeout(const Duration(seconds: 2));
  });

  test('daemon.status answers; daemon.quit runs onQuit then answers', () async {
    await rig.manager.open(cols: 80, rows: 24);
    quitGate = Completer<void>();
    build();
    final c = await attach(listener);
    final st = await request(c, req(MuxType.daemonStatus));
    expect(st.get<int>('sessions'), 1);
    expect(st.get<String>('instance'), 'inst1');
    expect(st.get<String>('app'), '1.6.0');
    expect(st.get<int>('protocol'), kMuxProtocol);
    expect(st.get<int>('pid'), 42);
    expect(st.get<List<Object?>>('caps'), ['cli']);
    var answered = false;
    final quit = request(c, req(MuxType.daemonQuit)).then((m) {
      answered = true;
      return m;
    });
    await pumpEventQueue();
    expect(quitCalls, 1);
    expect(answered, isFalse);
    quitGate.complete();
    expect((await quit).type, MuxType.result);
  });

  test('agent.get / agent.state / agent.call', () async {
    build();
    final c = await attach(listener);
    final g = await request(c, req(MuxType.agentGet));
    expect(g.get<Map<Object?, Object?>>('state'), {'signedIn': true});
    final st = c.messages.firstWhere((m) => m.type == MuxType.agentState);
    bridge.controller.add({'signedIn': false});
    expect((await st).get<Map<Object?, Object?>>('state'), {'signedIn': false});
    final call = await request(
      c,
      req(MuxType.agentCall, {
        'm': 'x',
        'a': {'k': 1},
      }),
    );
    expect(call.get<Map<Object?, Object?>>('value'), {'echo': 'x'});
    expect(bridge.calls.single.$1, 'x');
    expect(bridge.calls.single.$2, {'k': 1});
    final boom = await request(c, req(MuxType.agentCall, {'m': 'boom'}));
    expect(boom.get<String>('code'), MuxError.internal);
    expect(boom.get<String>('message'), 'StateError');
  });

  test('a closed ui disposes its views; the session keeps running', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    build();
    final c = await attach(listener);
    await request(c, req(MuxType.viewOpen, {'id': id}));
    expect(uiChanges, [true]);
    await c.close();
    await pumpEventQueue();
    expect(rig.manager.sessions, hasLength(1));
    expect(server.uiAttached, isFalse);
    expect(uiChanges, [true, false]);
    final again = await attach(listener);
    expect(
      (await request(
        again,
        req(MuxType.sessionsList),
      )).get<List<Object?>>('sessions'),
      hasLength(1),
    );
  });

  test('a wrong secret never reaches the session layer', () async {
    build();
    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    final seen = <MuxMessage>[];
    client.messages.listen(seen.add);
    await expectLater(
      clientHandshake(client, secret: Uint8List(32), app: '1.6.0', role: 'ui'),
      throwsA(isA<MuxHandshakeException>()),
    );
    await rig.manager.open(cols: 80, rows: 24);
    await pumpEventQueue();
    expect(seen.where((m) => m.type == MuxType.sessionsChanged), isEmpty);
    expect(server.uiAttached, isFalse);
  });

  test('ui.event from the ui reaches uiApi.events', () async {
    build();
    final ui = await attach(listener);
    final event = server.uiApi.events().first;
    ui.send(const MuxMessage(MuxType.uiEvent, fields: {'kind': 'tab'}));
    expect((await event)['kind'], 'tab');
  });

  test(
    'daemon.quit runs onQuit once for repeated and concurrent calls',
    () async {
      quitGate = Completer<void>();
      build();
      final c = await attach(listener);
      final a = request(c, req(MuxType.daemonQuit));
      final b = request(c, req(MuxType.daemonQuit));
      await pumpEventQueue();
      quitGate.complete();
      expect((await a).type, MuxType.result);
      expect((await b).type, MuxType.result);
      expect((await request(c, req(MuxType.daemonQuit))).type, MuxType.result);
      expect(quitCalls, 1);
    },
  );

  test('the reset backlog does not count as unacked (no re-pause)', () async {
    final id = await rig.manager.open(cols: 80, rows: 24);
    build(stopAbove: 1000, resumeBelow: 200);
    final c = await attach(listener);
    final got = <MuxMessage>[];
    c.messages.listen(got.add);
    await request(c, req(MuxType.viewOpen, {'id': id}));
    for (final ch in ['a', 'b', 'c']) {
      rig.pty(0).emit(ch * 600);
      await pumpEventQueue();
    }
    c.send(MuxMessage(MuxType.viewAck, fields: {'id': id, 'bytes': 1500}));
    await pumpEventQueue();
    got.clear();
    rig.pty(0).emit('live1');
    await pumpEventQueue();
    rig.pty(0).emit('live2');
    await pumpEventQueue();
    expect(
      [for (final m in got) utf8.decode(m.get<Uint8List>('data')!)],
      ['live1', 'live2'],
    );
  });

  group('adopted cli connections keep the A7 rules', () {
    var external = false;
    late CliHost host;
    setUp(() {
      external = false;
      host = CliHost.adopted(
        ui: FakeUiApi(),
        enabled: () => true,
        token: 'tok',
        allowExternal: () => external,
        appVersion: '1.6.0',
        hostKind: () => 'daemon',
        uiAttached: () => server.uiAttached,
        maxLimited: 1,
      );
      build();
      server.cli = host;
    });
    tearDown(() => host.stop());

    test(
      'a token-less client is limited: version and pane-less notify only',
      () async {
        final c = await attach(listener, role: 'cli');
        expect(
          (await request(c, req(CliType.apiVersion))).type,
          MuxType.result,
        );
        expect(
          (await request(c, req(CliType.cliNotify, {'body': 'x'}))).type,
          MuxType.result,
        );
        final r = await request(c, req(CliType.uiLs));
        expect(r.get<String>('code'), CliError.forbidden);
        await c.done;
      },
    );

    test('allowExternal off then recheck() closes a token-less client that '
        'used the full API', () async {
      external = true;
      final c = await attach(listener, role: 'cli');
      expect((await request(c, req(CliType.uiLs))).type, MuxType.result);
      final closed = c.done;
      external = false;
      host.recheck();
      await closed.timeout(const Duration(seconds: 2));
    });

    test('the limited cap applies to adopted connections', () async {
      final first = await attach(listener, role: 'cli');
      await request(first, req(CliType.apiVersion));
      final second = await attach(listener, role: 'cli');
      expect((await firstError(second)).get<String>('code'), MuxError.busy);
      final withToken = await attach(listener, role: 'cli', token: 'tok');
      expect(
        (await request(withToken, req(CliType.apiVersion))).type,
        MuxType.result,
      );
    });
  });
}
