import 'dart:async';
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';

/// One request a [TestTool] got.
final class ToolHit {
  ToolHit(this.method, this.uri, this.headers);
  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
}

/// Where each [TestTool] listens, by the port the window lists for it.
final _listening = <int, (InternetAddress, int)>{};

/// A personal web tool on the computer: HTTP routes on a real loopback
/// server, a page at any other path, and a WebSocket echo at `/ws` (a
/// `close:<code>` text closes it with that code).
final class TestTool {
  TestTool._(this.server, this.routes, {required this.port})
    : _at = (server.address, server.port) {
    // Only what a route sets: the phone's own headers would show.
    server.defaultResponseHeaders.clear();
    server.listen(_serve);
    _listening[port] = _at;
  }

  /// Where [server] listens (still known once it is closed).
  final (InternetAddress, int) _at;

  /// A tool listening on [address] (127.0.0.1 unless given) and [port]: the
  /// window lists the port it listens on. The phone (this same machine)
  /// cannot hold that port then, on that address: alias mode (E3).
  static Future<TestTool> start({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    InternetAddress? address,
    int port = 0,
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    return TestTool._(server, {...routes}, port: server.port);
  }

  /// R21, same-port mode (E2) with one machine playing both sides: the
  /// window lists [port] (when 0, one free on 127.0.0.1 and [::1]), which
  /// the phone then holds on both addresses as it must; the tool itself
  /// listens on another port of 127.0.0.1, where [connectTestTool] (the
  /// desktop's connect in a test) takes [port]. The phone's binder runs
  /// unchanged.
  static Future<TestTool> samePort({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    int port = 0,
  }) async {
    // Held first, so the free port below is another one.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final listed = port == 0 ? await freeLoopbackPort() : port;
    return TestTool._(server, {...routes}, port: listed);
  }

  final HttpServer server;
  final Map<String, Future<void> Function(HttpRequest request)> routes;
  final hits = <ToolHit>[];
  final wsClosed = <(int?, String?)>[];
  final _sockets = <WebSocket>[];

  /// The port the window lists for this tool (its URL's port): where it
  /// listens ([start]), or the port the phone serves it on ([samePort]).
  final int port;

  Future<void> _serve(HttpRequest request) async {
    final headers = <String, List<String>>{};
    request.headers.forEach((name, values) => headers[name] = values);
    hits.add(ToolHit(request.method, request.uri, headers));
    final route = routes[request.uri.path];
    if (route != null) return route(request);
    if (request.uri.path == '/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (offered) => offered.first,
      );
      _sockets.add(ws);
      ws.listen((message) {
        if (message is String && message.startsWith('close:')) {
          unawaited(ws.close(int.parse(message.substring(6)), 'by tool'));
        } else {
          ws.add(message);
        }
      }, onDone: () => wsClosed.add((ws.closeCode, ws.closeReason)));
      return;
    }
    request.response
      ..headers.contentType = ContentType.html
      ..write('<h1>${request.uri.path}</h1>');
    await request.response.close();
  }

  /// The entry the window would serve for this tool.
  Map<String, Object?> entry({
    String id = 'k3f9za7q1m',
    String name = 'Bảng việc',
    String host = 'localhost',
    String path = '/',
    String group = 'ws:a',
  }) => {
    'id': id,
    'name': name,
    'ws': 'shop-web',
    'group': group,
    'url': 'http://$host:$port$path',
  };

  Future<void> close() async {
    for (final ws in _sockets) {
      await ws.close().catchError((Object _) => null);
    }
    await server.close(force: true);
    if (_listening[port] == _at) _listening.remove(port);
  }
}

/// The desktop's connect (`ToolProxy(connect: connectTestTool)`) where one
/// machine plays both sides: the port the window lists for a [TestTool]
/// reaches that tool where it listens. Any other port is refused: never the
/// phone's own server on that port.
Future<Socket> connectTestTool(int port) async {
  final at = _listening[port];
  if (at == null) {
    throw const SocketException('no test tool is listed on this port');
  }
  return Socket.connect(at.$1, at.$2);
}

/// A port free on 127.0.0.1 and on [::1] (held on both, then let go).
Future<int> freeLoopbackPort() async {
  for (var tries = 1; ; tries++) {
    final v4 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final v6 = await ServerSocket.bind(
        InternetAddress.loopbackIPv6,
        v4.port,
        v6Only: true,
      );
      await v6.close();
      return v4.port;
    } on SocketException {
      if (tries == 20) rethrow;
    } finally {
      await v4.close();
    }
  }
}

/// [tools] as the window would serve them.
ToolCatalog catalogOf(
  List<Map<String, Object?>> tools, {
  Iterable<String> off = const [],
}) => ToolCatalog.fromServeBody(ToolCatalog.serveBody(tools, off: off))!;
