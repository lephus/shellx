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

/// A personal web tool on the computer: HTTP routes on a real loopback
/// server, a page at any other path, and a WebSocket echo at `/ws` (a
/// `close:<code>` text closes it with that code).
final class TestTool {
  TestTool._(this.server, this.routes) {
    // Only what a route sets: the phone's own headers would show.
    server.defaultResponseHeaders.clear();
    server.listen(_serve);
  }

  static Future<TestTool> start({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    InternetAddress? address,
    int port = 0,
  }) async => TestTool._(
    await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, port),
    {...routes},
  );

  final HttpServer server;
  final Map<String, Future<void> Function(HttpRequest request)> routes;
  final hits = <ToolHit>[];
  final wsClosed = <(int?, String?)>[];
  final _sockets = <WebSocket>[];

  int get port => server.port;

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
  }
}

/// [tools] as the window would serve them.
ToolCatalog catalogOf(
  List<Map<String, Object?>> tools, {
  Iterable<String> off = const [],
}) => ToolCatalog.fromServeBody(ToolCatalog.serveBody(tools, off: off))!;
