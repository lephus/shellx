import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/mux_fixtures.dart';
import '../support/session_rig.dart';

const _self = MuxPeerInfo(
  protocol: kMuxProtocol,
  app: '2.0.0',
  instance: 'inst1',
  pid: 42,
  caps: ['agent', 'cli', 'tools'],
);
const _phone = 'b0000000-0000-4000-8000-000000000002';

Future<MuxConnection> _window(TestListener l) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  l.push(daemonSide);
  await clientHandshake(client, secret: secret, app: '2.0.0', role: 'ui');
  return client;
}

Uint8List _body(List<String> ids, {List<String> off = const []}) =>
    ToolCatalog.serveBody([
      for (final id in ids)
        {
          'id': id,
          'name': 'Tool $id',
          'ws': 'shop-web',
          'group': 'ws:a',
          'url': 'http://localhost:5173/',
        },
    ], off: off);

/// V2-4 E5: the window tells the background service which tools phones may
/// open; the service's proxy serves them, also after the window quits.
void main() {
  late SessionRig rig;
  late TestListener listener;
  MuxServer? server;
  late ToolProxy proxy;
  late List<ToolMessage> toPhone;

  setUp(() {
    rig = SessionRig();
    listener = TestListener();
    proxy = ToolProxy();
    toPhone = [];
    proxy.outbound.listen((o) => toPhone.add(o.message as ToolMessage));
  });

  tearDown(() async {
    proxy.close();
    await server?.close();
    server = null;
  });

  List<String> listed() {
    final result = toPhone.whereType<ToolListResult>().last;
    final json = jsonDecode(utf8.decode(result.body)) as Map<String, Object?>;
    return [for (final t in json['tools']! as List) (t as Map)['id'] as String];
  }

  test('tool.serve reaches the proxy; the list stays when the window goes; '
      'an unreadable list changes nothing', () async {
    server = MuxServer(
      sessions: rig.manager,
      secret: secret,
      self: _self,
      onQuit: () async {},
    )..tools = proxy;
    server!.serve(listener);
    proxy.handle(_phone, const ToolList());
    expect(toPhone.whereType<ToolListResult>().single.available, isFalse);

    final window = await _window(listener);
    window.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': _body(['aaaaaaaaa1']),
        },
      ),
    );
    await pumpEventQueue();
    expect(listed(), ['aaaaaaaaa1']);
    expect(toPhone.whereType<ToolListResult>().last.available, isTrue);

    window.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': Uint8List.fromList([1, 2]),
        },
      ),
    );
    window.send(const MuxMessage(MuxType.toolServe));
    await pumpEventQueue();
    expect(listed(), ['aaaaaaaaa1']);

    await window.close();
    await pumpEventQueue();
    expect(proxy.catalog?.tools.single.id, 'aaaaaaaaa1');
    final again = await _window(listener);
    again.send(
      MuxMessage(
        MuxType.toolServe,
        fields: {
          'b': _body(['bbbbbbbbb2']),
        },
      ),
    );
    await pumpEventQueue();
    expect(listed(), ['bbbbbbbbb2']);
  });

  test(
    'an older service (no proxy) ignores tool.serve and keeps answering',
    () async {
      server = MuxServer(
        sessions: rig.manager,
        secret: secret,
        self: _self,
        onQuit: () async {},
      )..serve(listener);
      final window = await _window(listener);
      window.send(
        MuxMessage(
          MuxType.toolServe,
          fields: {
            'b': _body(['aaaaaaaaa1']),
          },
        ),
      );
      final reply = window.messages.firstWhere((m) => m.q == 1);
      window.send(const MuxMessage(MuxType.sessionsList, q: 1));
      expect((await reply).type, MuxType.result);
    },
  );

  test('a list over one mux frame is cut to fit, in order', () {
    final body = ToolCatalog.serveBody([
      for (var i = 0; i < 100; i++)
        {
          'id': 'tool${i.toString().padLeft(6, '0')}',
          'name': 'x',
          'ws': 'w',
          'group': 'g',
          'url': 'http://localhost:5173/${'p' * 1500}',
        },
    ]);
    expect(body.length, lessThanOrEqualTo(kToolServeMaxBytes));
    final catalog = ToolCatalog.fromServeBody(body)!;
    expect(catalog.tools.first.id, 'tool000000');
    expect(catalog.tools.length, lessThan(100));
  });
}
