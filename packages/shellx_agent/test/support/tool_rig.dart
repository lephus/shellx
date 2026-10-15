import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';

/// Polls [condition] every 10 ms until it holds (fails after [timeout]).
Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// One request a [TestTool] got.
final class ToolHit {
  ToolHit(this.method, this.uri, this.headers);
  final String method;
  final Uri uri;
  final Map<String, List<String>> headers;
}

/// A personal web tool on this computer: HTTP routes on a real loopback
/// server, and a WebSocket echo at `/ws` (a `close:<code>` text closes with
/// that code).
final class TestTool {
  TestTool._(this.server, this.routes) {
    server.listen(_serve);
  }

  static Future<TestTool> start({
    Map<String, Future<void> Function(HttpRequest request)> routes = const {},
    InternetAddress? address,
  }) async => TestTool._(
    await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, 0),
    {...routes},
  );

  final HttpServer server;
  final Map<String, Future<void> Function(HttpRequest request)> routes;
  final hits = <ToolHit>[];

  /// The close code and reason of each WebSocket that closed.
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

  /// The JSON entry the window would serve for this tool.
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

/// A phone in front of a [ToolProxy]: every message goes through the wire's
/// encoding both ways; the bodies it gets are acknowledged at once unless
/// [autoAck] is off.
final class ToolPhone {
  ToolPhone(this.proxy, {this.mobileId = phone}) {
    // In a microtask, like the channel: a listener of the proxy's stream
    // must not call back into it (its acks would).
    proxy.outbound
        .where((o) => o.mobileId == mobileId)
        .listen(
          (o) => scheduleMicrotask(
            () => _receive(_wire(o.message) as ToolMessage),
          ),
        );
  }

  final ToolProxy proxy;
  final String mobileId;
  bool autoAck = true;
  final messages = <ToolMessage>[];
  final _bodies = <int, BytesBuilder>{};
  final _received = <int, int>{};
  final _acked = <int, int>{};
  final _ends = <int, Completer<void>>{};
  final _responses = <int, Completer<ToolResponse>>{};
  final _listings = StreamController<ToolListResult>.broadcast();

  /// The most this phone had received and not acknowledged, per stream.
  final maxUnacked = <int, int>{};

  /// When each `tool.data` and `tool.ws.msg` with bytes arrived.
  final dataTimes = <Duration>[];
  final clock = Stopwatch()..start();
  int nextId = 1;

  static AppMessage _wire(AppMessage m) => decodeBatch(encodeBatch([m])).single;

  void send(ToolMessage message) =>
      proxy.handle(mobileId, _wire(message) as ToolMessage);

  Stream<ToolListResult> get listings => _listings.stream;

  void _receive(ToolMessage message) {
    messages.add(message);
    switch (message) {
      case ToolListResult():
        _listings.add(message);
      case ToolResponse(:final id, :final end):
        (_responses[id] ??= Completer()).complete(message);
        if (end) (_ends[id] ??= Completer()).complete();
      case ToolData(:final id, :final data, :final end):
        if (data.isNotEmpty) dataTimes.add(clock.elapsed);
        (_bodies[id] ??= BytesBuilder(copy: false)).add(data);
        _count(id, data.length);
        if (end) (_ends[id] ??= Completer()).complete();
      case ToolWsMessage(:final id, :final data):
        if (data.isNotEmpty) dataTimes.add(clock.elapsed);
        _count(id, toolWsPieceCost(data.length));
      case ToolEnd(:final id):
        final done = _ends[id] ??= Completer();
        if (!done.isCompleted) done.complete();
        final res = _responses[id];
        if (res != null && !res.isCompleted) {
          res.completeError(StateError('ended before a response'));
        }
      default:
        break;
    }
  }

  void _count(int id, int bytes) {
    final received = _received[id] = (_received[id] ?? 0) + bytes;
    final unacked = received - (_acked[id] ?? 0);
    if (unacked > (maxUnacked[id] ?? 0)) maxUnacked[id] = unacked;
    if (autoAck) ackAll();
  }

  /// Acknowledges everything received so far.
  void ackAll() {
    final acks = <int>[
      for (final MapEntry(:key, :value) in _received.entries)
        if ((_acked[key] ?? 0) < value) ...[key, value],
    ];
    if (acks.isEmpty) return;
    for (var i = 0; i < acks.length; i += 2) {
      _acked[acks[i]] = acks[i + 1];
    }
    send(ToolAck(acks));
  }

  /// Sends a request; its id.
  int request(
    String tool, {
    String method = 'GET',
    String target = '/',
    List<String> head = const [],
    int? alias,
    bool ws = false,
    bool end = true,
  }) {
    final id = nextId++;
    send(
      ToolRequest(
        id: id,
        tool: tool,
        method: method,
        target: target,
        head: head,
        alias: alias,
        ws: ws,
        end: end,
      ),
    );
    return id;
  }

  Future<ToolResponse> response(int id) => (_responses[id] ??= Completer())
      .future
      .timeout(const Duration(seconds: 10));

  /// Waits for the stream to end (its last piece, or `tool.end`).
  Future<void> ended(int id) =>
      (_ends[id] ??= Completer()).future.timeout(const Duration(seconds: 60));

  Uint8List body(int id) => _bodies[id]?.toBytes() ?? Uint8List(0);

  ToolEnd? endOf(int id) =>
      messages.whereType<ToolEnd>().where((m) => m.id == id).firstOrNull;

  List<ToolWsMessage> wsPieces(int id) =>
      messages.whereType<ToolWsMessage>().where((m) => m.id == id).toList();
}
