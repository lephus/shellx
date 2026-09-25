import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const _peer = '0f8fad5b-d9cb-469f-a165-70867728950e';

/// In-memory RelaySocket driven by the test.
final class FakeRelaySocket implements RelaySocket {
  final StreamController<Object> _incoming = StreamController<Object>();
  final List<String> sentText = [];
  final List<Uint8List> sentBytes = [];
  int? _closeCode;
  int? clientCloseCode;
  bool closedByClient = false;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  void sendText(String text) => sentText.add(text);

  @override
  void sendBytes(Uint8List bytes) => sentBytes.add(bytes);

  @override
  Future<void> close([int? code, String? reason]) async {
    closedByClient = true;
    clientCloseCode = code;
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }

  @override
  int? get closeCode => _closeCode;

  /// Delivers a frame from the server (ignored once the socket is closed).
  void receive(Object message) {
    if (!_incoming.isClosed) {
      _incoming.add(message);
    }
  }

  void serverClose(int? code) {
    _closeCode = code;
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }
}

/// Connector that hands out FakeRelaySockets and records each attempt.
final class FakeConnector {
  final List<Uri> uris = [];
  final List<Map<String, String>> headers = [];
  final List<FakeRelaySocket> sockets = [];

  /// When set, the next attempt completes with this instead of a socket.
  Future<RelaySocket> Function()? nextAttempt;

  Future<RelaySocket> call(Uri uri, Map<String, String> requestHeaders) {
    uris.add(uri);
    headers.add(requestHeaders);
    final override = nextAttempt;
    nextAttempt = null;
    if (override != null) {
      return override();
    }
    final socket = FakeRelaySocket();
    sockets.add(socket);
    return Future.value(socket);
  }

  int get attempts => uris.length;
  FakeRelaySocket get last => sockets.last;
}

/// Always picks the top of the jitter range, so delay == base.
final class _MaxRandom implements Random {
  @override
  int nextInt(int max) => max - 1;
  @override
  double nextDouble() => 0.999999;
  @override
  bool nextBool() => true;
}

final _wsUri = Uri.parse('wss://relay.shellx.pro/v1/ws');

({
  RelayConnection relay,
  FakeConnector connector,
  List<RelayConnectionState> states,
  List<RelayFrame> frames,
})
_setUp({String? Function()? token}) {
  final connector = FakeConnector();
  final relay = RelayConnection(
    wsUri: _wsUri,
    token: token ?? () => 'tok-123',
    connector: connector.call,
    backoff: Backoff(random: _MaxRandom()),
  );
  final states = <RelayConnectionState>[];
  final frames = <RelayFrame>[];
  relay.states.listen(states.add);
  relay.frames.listen(frames.add);
  return (relay: relay, connector: connector, states: states, frames: frames);
}

void main() {
  test('connects with the Authorization header and reports states', () {
    fakeAsync((async) {
      final t = _setUp();
      expect(t.relay.state, RelayConnectionState.disconnected);
      t.relay.start();
      async.flushMicrotasks();
      expect(t.connector.uris, [_wsUri]);
      expect(t.connector.headers.single, {'Authorization': 'Bearer tok-123'});
      expect(t.relay.state, RelayConnectionState.connected);
      expect(t.states, [
        RelayConnectionState.connecting,
        RelayConnectionState.connected,
      ]);
      t.relay.start(); // no-op while connected
      async.flushMicrotasks();
      expect(t.connector.attempts, 1);
    });
  });

  test('reads the token again on every attempt', () {
    fakeAsync((async) {
      var token = 'first';
      final t = _setUp(token: () => token);
      t.relay.start();
      async.flushMicrotasks();
      token = 'second';
      t.connector.last.serverClose(1006);
      async.elapse(const Duration(seconds: 1));
      expect(t.connector.headers.map((h) => h['Authorization']), [
        'Bearer first',
        'Bearer second',
      ]);
    });
  });

  test('no token means revoked without connecting', () {
    fakeAsync((async) {
      final t = _setUp(token: () => null);
      t.relay.start();
      async.flushMicrotasks();
      expect(t.relay.state, RelayConnectionState.revoked);
      expect(t.connector.attempts, 0);
    });
  });

  test('pings on connect and every 30 s; pong keeps the connection', () {
    fakeAsync((async) {
      final t = _setUp();
      t.relay.start();
      async.flushMicrotasks();
      final socket = t.connector.last;
      expect(socket.sentText, ['ping']);
      socket.receive('pong');
      async.elapse(const Duration(seconds: 29));
      expect(socket.sentText, ['ping']);
      async.elapse(const Duration(seconds: 1));
      expect(socket.sentText, ['ping', 'ping']);
      async.elapse(const Duration(seconds: 5));
      socket.receive('pong');
      async.elapse(const Duration(seconds: 25));
      expect(socket.sentText, ['ping', 'ping', 'ping']);
      socket.receive('pong');
      for (var i = 0; i < 10; i++) {
        async.elapse(const Duration(seconds: 30));
        socket.receive('pong');
      }
      async.flushMicrotasks();
      expect(socket.sentText, hasLength(13));
      expect(t.relay.state, RelayConnectionState.connected);
      expect(t.connector.attempts, 1);
      expect(socket.closedByClient, isFalse);
    });
  });

  test('no pong within 10 s drops the socket and reconnects with backoff', () {
    fakeAsync((async) {
      final t = _setUp();
      t.relay.start();
      async.flushMicrotasks();
      final first = t.connector.last;
      first.receive('pong');
      async.elapse(const Duration(seconds: 30)); // second ping, never answered
      async.elapse(const Duration(milliseconds: 9999));
      expect(t.relay.state, RelayConnectionState.connected);
      async.elapse(const Duration(milliseconds: 1));
      expect(first.closedByClient, isTrue);
      expect(t.relay.state, RelayConnectionState.disconnected);
      expect(t.connector.attempts, 1);
      // Backoff was reset by the earlier pong, so the first retry is at 1 s.
      async.elapse(const Duration(milliseconds: 999));
      expect(t.connector.attempts, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(t.connector.attempts, 2);
      expect(t.relay.state, RelayConnectionState.connected);
    });
  });

  test(
    'repeated failures back off 1, 2, 4, 8, 16, 30, 30 s and pong resets it',
    () {
      fakeAsync((async) {
        final t = _setUp();
        t.connector.nextAttempt = () =>
            Future.error(const SocketException('down'));
        t.relay.start();
        async.flushMicrotasks();
        final delays = <int>[];
        for (var i = 0; i < 7; i++) {
          final before = t.connector.attempts;
          var waited = 0;
          while (t.connector.attempts == before) {
            t.connector.nextAttempt ??= () =>
                Future.error(const SocketException('down'));
            async.elapse(const Duration(milliseconds: 100));
            waited += 100;
          }
          delays.add(waited);
        }
        expect(delays, [1000, 2000, 4000, 8000, 16000, 30000, 30000]);

        // Let the next attempt succeed, answer the ping, then drop: back to 1 s.
        t.connector.nextAttempt = null;
        async.elapse(const Duration(seconds: 30));
        expect(t.relay.state, RelayConnectionState.connected);
        t.connector.last.receive('pong');
        async.flushMicrotasks();
        final attempts = t.connector.attempts;
        t.connector.last.serverClose(1006);
        async.elapse(const Duration(seconds: 1));
        expect(t.connector.attempts, attempts + 1);
      });
    },
  );

  test('a connection dropped before any pong keeps growing the backoff', () {
    fakeAsync((async) {
      final t = _setUp();
      t.relay.start();
      async.flushMicrotasks();
      t.connector.last.serverClose(1011); // attempt 1 fails -> wait 1 s
      async.elapse(const Duration(seconds: 1));
      expect(t.connector.attempts, 2);
      t.connector.last.serverClose(1011); // no pong yet -> wait 2 s
      async.elapse(const Duration(milliseconds: 1999));
      expect(t.connector.attempts, 2);
      async.elapse(const Duration(milliseconds: 1));
      expect(t.connector.attempts, 3);
    });
  });

  for (final (code, expected) in [
    (4002, RelayConnectionState.revoked),
    (4001, RelayConnectionState.replaced),
  ]) {
    test('close $code -> ${expected.name}, no reconnect', () {
      fakeAsync((async) {
        final t = _setUp();
        t.relay.start();
        async.flushMicrotasks();
        t.connector.last.serverClose(code);
        async.flushMicrotasks();
        expect(t.relay.state, expected);
        async.elapse(const Duration(minutes: 10));
        expect(t.connector.attempts, 1);
        expect(
          t.relay.send(const PresenceFrame(deviceId: _peer, online: true)),
          isFalse,
        );
        expect(t.connector.last.sentText, ['ping']); // no pings after close
      });
    });
  }

  for (final code in [1000, 1001, 1006, 1011, 4003, null]) {
    test('close $code -> disconnected, then reconnects', () {
      fakeAsync((async) {
        final t = _setUp();
        t.relay.start();
        async.flushMicrotasks();
        t.connector.last.serverClose(code);
        async.flushMicrotasks();
        expect(t.relay.state, RelayConnectionState.disconnected);
        async.elapse(const Duration(seconds: 1));
        expect(t.connector.attempts, 2);
        expect(t.relay.state, RelayConnectionState.connected);
      });
    });
  }

  test('an HTTP 401 upgrade rejection means revoked', () {
    fakeAsync((async) {
      final t = _setUp();
      t.connector.nextAttempt = () =>
          Future.error(const WebSocketException('not upgraded', 401));
      t.relay.start();
      async.elapse(const Duration(minutes: 1));
      expect(t.relay.state, RelayConnectionState.revoked);
      expect(t.connector.attempts, 1);
    });
  });

  test('a connect attempt that hangs is abandoned after 15 s', () {
    fakeAsync((async) {
      final t = _setUp();
      final hanging = Completer<RelaySocket>();
      t.connector.nextAttempt = () => hanging.future;
      t.relay.start();
      async.elapse(const Duration(seconds: 14));
      expect(t.relay.state, RelayConnectionState.connecting);
      async.elapse(const Duration(seconds: 1));
      expect(t.relay.state, RelayConnectionState.disconnected);
      async.elapse(const Duration(seconds: 1));
      expect(t.connector.attempts, 2);
      expect(t.relay.state, RelayConnectionState.connected);
      // The late socket is closed, never used.
      final late = FakeRelaySocket();
      hanging.complete(late);
      async.flushMicrotasks();
      expect(late.closedByClient, isTrue);
      expect(t.relay.state, RelayConnectionState.connected);
    });
  });

  test(
    'delivers valid binary frames and ignores malformed ones and stray text',
    () {
      fakeAsync((async) {
        final t = _setUp();
        t.relay.start();
        async.flushMicrotasks();
        final socket = t.connector.last;
        socket.receive(Uint8List.fromList([1])); // too short
        socket.receive(Uint8List.fromList([9, 2])); // bad version
        socket.receive(Uint8List.fromList([1, 0x7f])); // unknown type
        socket.receive('hello'); // unexpected text
        socket.receive(
          const PresenceFrame(deviceId: _peer, online: true).encode(),
        );
        async.flushMicrotasks();
        expect(t.frames, [const PresenceFrame(deviceId: _peer, online: true)]);
        expect(t.relay.state, RelayConnectionState.connected);
      });
    },
  );

  test('send returns false unless connected and writes the encoded frame', () {
    fakeAsync((async) {
      final t = _setUp();
      final frame = DataFrame(
        peer: _peer,
        channel: ChannelId.zero,
        payload: Uint8List.fromList([4, 1]),
      );
      expect(t.relay.send(frame), isFalse);
      t.relay.start();
      expect(t.relay.state, RelayConnectionState.connecting);
      expect(t.relay.send(frame), isFalse);
      async.flushMicrotasks();
      expect(t.relay.send(frame), isTrue);
      expect(t.connector.last.sentBytes.single, frame.encode());
    });
  });

  test('reconnectNow skips the pending backoff', () {
    fakeAsync((async) {
      final t = _setUp();
      t.connector.nextAttempt = () =>
          Future.error(const SocketException('down'));
      t.relay.start();
      async.flushMicrotasks();
      t.connector.nextAttempt = () =>
          Future.error(const SocketException('down'));
      async.elapse(
        const Duration(seconds: 1),
      ); // 2nd attempt fails, next wait is 2 s
      expect(t.connector.attempts, 2);
      t.relay.reconnectNow();
      async.flushMicrotasks();
      expect(t.connector.attempts, 3);
      expect(t.relay.state, RelayConnectionState.connected);
      t.relay.reconnectNow(); // no-op while connected
      async.flushMicrotasks();
      expect(t.connector.attempts, 3);
      async.elapse(
        const Duration(seconds: 5),
      ); // the cancelled timer never fires
      expect(t.connector.attempts, 3);
    });
  });

  test('stop closes the socket, emits stopped and never reconnects', () {
    fakeAsync((async) {
      final t = _setUp();
      t.relay.start();
      async.flushMicrotasks();
      final socket = t.connector.last;
      t.relay.stop();
      async.flushMicrotasks();
      expect(t.relay.state, RelayConnectionState.stopped);
      expect(t.states.last, RelayConnectionState.stopped);
      expect(socket.closedByClient, isTrue);
      expect(socket.clientCloseCode, 1000);
      async.elapse(const Duration(minutes: 10));
      expect(t.connector.attempts, 1);
      expect(socket.sentText, ['ping']);
      expect(
        t.relay.send(const PresenceFrame(deviceId: _peer, online: true)),
        isFalse,
      );
      t.relay.reconnectNow(); // ignored when stopped
      async.flushMicrotasks();
      expect(t.connector.attempts, 1);
    });
  });

  test(
    'stop during a pending backoff cancels it; start works again after stop',
    () {
      fakeAsync((async) {
        final t = _setUp();
        t.connector.nextAttempt = () =>
            Future.error(const SocketException('down'));
        t.relay.start();
        async.flushMicrotasks();
        t.relay.stop();
        async.elapse(const Duration(minutes: 1));
        expect(t.connector.attempts, 1);
        t.relay.start();
        async.flushMicrotasks();
        expect(t.connector.attempts, 2);
        expect(t.relay.state, RelayConnectionState.connected);
      });
    },
  );

  test(
    'events from an abandoned socket are ignored (late 4001 after pong timeout)',
    () {
      fakeAsync((async) {
        final t = _setUp();
        t.relay.start();
        async.flushMicrotasks();
        final old = t.connector.last;
        async.elapse(const Duration(seconds: 10)); // first ping never answered
        async.elapse(const Duration(seconds: 1)); // reconnect
        expect(t.connector.attempts, 2);
        expect(t.relay.state, RelayConnectionState.connected);
        old.receive(
          const PresenceFrame(deviceId: _peer, online: true).encode(),
        );
        old.serverClose(4001);
        async.flushMicrotasks();
        expect(t.relay.state, RelayConnectionState.connected);
        expect(t.frames, isEmpty);
      });
    },
  );
}
