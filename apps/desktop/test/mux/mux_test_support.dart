import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

final testSecret = Uint8List.fromList(List.generate(32, (i) => i + 1));

/// A [MuxListener] a test feeds with the daemon side of a memory pair.
final class TestListener implements MuxListener {
  final _c = StreamController<MuxConnection>.broadcast();
  @override
  Stream<MuxConnection> get connections => _c.stream;
  @override
  String get address => 'test';
  @override
  Future<void> close() async => closed = true;
  bool closed = false;
  void push(MuxConnection c) => _c.add(c);
}

/// A client that completed the handshake with a server on [listener].
Future<MuxClient> attachClient(
  TestListener listener, {
  String role = 'ui',
  Uint8List? secret,
}) async {
  final (client, server) = MemoryMuxTransport.pair();
  listener.push(server);
  final peer = await clientHandshake(
    client,
    secret: secret ?? testSecret,
    app: '1.6.0',
    role: role,
  );
  return MuxClient(client, early: peer.early);
}
