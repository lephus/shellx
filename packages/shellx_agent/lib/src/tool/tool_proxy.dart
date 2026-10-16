import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';
import 'tool_catalog.dart';
import 'tool_endpoint.dart';
import 'tool_forwarding.dart';

/// V2-4 E10: stream opens (`tool.open`, `tool.req`) a phone may make at once,
/// then [kToolOpensPerSecond] a second; more are answered `busy`.
const int kToolOpenBurst = 120;
const int kToolOpensPerSecond = 60;

/// V2-4 E5, E9: the desktop's side of the `tool.*` tunnel, in the process
/// that holds the relay. It lists the tools the window lets phones open
/// ([serve]), checks each open against that list, and carries HTTP requests
/// and WebSockets to the tool's port on this computer only
/// ([toolHttpClient]). Bodies and messages flow within windows (E7), paced
/// for the whole computer by [pacer]; a full window stops reading the tool
/// (never drops a byte).
///
/// [handle] returns at once: every network step runs in the background.
/// Nothing it carries is ever logged.
final class ToolProxy implements ToolEndpoint {
  ToolProxy({
    ToolPacer? pacer,
    ToolConnect? connect,
    this.headTimeout = kToolHeadTimeout,
    this.idleTimeout = kToolIdleTimeout,
    this.maxRequestBody = kToolMaxRequestBodyBytes,
    this.maxWsMessage = kToolMaxWsMessageBytes,
  }) : pacer = pacer ?? ToolTokenPacer(),
       _connect = connect ?? connectToolPort {
    _client = toolHttpClient(_connect);
  }

  final ToolPacer pacer;
  final Duration headTimeout;
  final Duration idleTimeout;

  /// E10: a larger request body ends `too_large`.
  final int maxRequestBody;

  /// E10: a larger WebSocket message, either way, closes with 1009.
  final int maxWsMessage;

  /// Opens a socket to a tool's port (E9: loopback only, never a name).
  final ToolConnect _connect;
  late final HttpClient _client;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final _phones = <String, _Phone>{};
  ToolCatalog? _catalog;
  bool _closed = false;
  Timer? _idleCheck;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  bool get serving => !_closed;

  /// The tools phones may open now; null before the window said.
  ToolCatalog? get catalog => _catalog;

  /// V2-4 E5, E9: the tools phones may open from now on. A stream of a tool
  /// that left the list ends `disabled` (its flag is off) or `gone`; one
  /// whose URL changed ends `gone`. Phones that list hear the new list.
  void serve(ToolCatalog? catalog) {
    if (_closed) return;
    _catalog = catalog;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        final tool = catalog?.byId(stream.tool.id);
        if (catalog == null) {
          stream.abort(ToolCode.unavailable);
        } else if (tool == null) {
          stream.abort(catalog.endCodeFor(stream.tool.id));
        } else if (tool.url != stream.tool.url) {
          stream.abort(ToolCode.gone);
        }
      }
      if (phone.listing) _sendListing(phone);
    }
  }

  /// The window quits (in-process, E5): every stream ends `desktop_closed`,
  /// phones that list hear `available: false`; from now on this proxy does
  /// not serve.
  void close() {
    if (_closed) return;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        stream.abort(ToolCode.desktopClosed);
      }
      if (phone.listing) {
        _emit(
          phone,
          ToolListResult(available: false, body: emptyToolListingBody),
        );
      }
      phone.dispose();
    }
    _phones.clear();
    _closed = true;
    _idleCheck?.cancel();
    _client.close(force: true);
  }

  @override
  void handle(String mobileId, ToolMessage message) {
    if (_closed) {
      final reply = toolUnavailableReply(message);
      if (reply != null) _out.add(OutboundMessage(mobileId, reply));
      return;
    }
    final phone = _phones[mobileId] ??= _Phone(mobileId, this);
    switch (message) {
      case ToolList():
        phone.listing = true;
        phone.listed = null; // the phone asked: answer even when unchanged
        _sendListing(phone);
      case ToolOpen(:final rid, :final tool):
        unawaited(_open(phone, rid, tool));
      case ToolClose(:final tool):
        for (final stream in [...phone.streams.values]) {
          if (stream.tool.id == tool) stream.abort(null);
        }
      case ToolRequest():
        _request(phone, message);
      case ToolData(:final id):
        phone.streams[id]?.onData(message);
      case ToolWsMessage(:final id):
        phone.streams[id]?.onWsMessage(message);
      case ToolAck(:final acks):
        for (var i = 0; i + 1 < acks.length; i += 2) {
          phone.streams[acks[i]]?.onAck(acks[i + 1]);
        }
      case ToolEnd(:final id):
        phone.streams[id]?.onPhoneEnd(message);
      case ToolListResult() || ToolOpened() || ToolResponse():
        break; // the desktop's own kinds never come from a phone
    }
  }

  @override
  void phoneGone(String mobileId) => _phones.remove(mobileId)?.dispose();

  @override
  void allPhonesGone() {
    for (final phone in _phones.values) {
      phone.dispose();
    }
    _phones.clear();
  }

  void _sendListing(_Phone phone) {
    final catalog = _catalog;
    final available = catalog != null;
    final body = catalog?.listingBody() ?? emptyToolListingBody;
    final listed = phone.listed;
    // An empty list has the bytes of "no list yet": only `available` tells
    // them apart.
    if (listed != null &&
        listed.available == available &&
        _same(listed.body, body)) {
      return;
    }
    phone.listed = (available: available, body: body);
    _emit(phone, ToolListResult(available: available, body: body));
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _open(_Phone phone, int rid, String id) async {
    ToolOpened answer(String code) =>
        ToolOpened(rid: rid, ok: false, code: code);
    if (!phone.budget.take()) return _emit(phone, answer(ToolCode.busy));
    final catalog = _catalog;
    if (catalog == null) return _emit(phone, answer(ToolCode.unavailable));
    final tool = catalog.byId(id);
    if (tool == null) return _emit(phone, answer(catalog.endCodeFor(id)));
    try {
      final socket = await _connect(tool.port);
      socket.destroy();
    } on Object {
      if (phone.live) _emit(phone, answer(ToolCode.refused));
      return;
    }
    // The list may have changed meanwhile: answer from the one of now.
    final now = _catalog?.byId(id);
    if (!phone.live) return;
    if (now == null || now.url != tool.url) {
      return _emit(phone, answer(_catalog?.endCodeFor(id) ?? ToolCode.gone));
    }
    _emit(
      phone,
      ToolOpened(rid: rid, ok: true, body: _catalog!.openedBody(now)),
    );
  }

  void _request(_Phone phone, ToolRequest request) {
    final id = request.id;
    void refuse(String code) => _emit(phone, ToolEnd(id: id, code: code));
    if (phone.streams.containsKey(id)) return; // a number in use: ignored
    if (!phone.budget.take()) return refuse(ToolCode.busy);
    final catalog = _catalog;
    if (catalog == null) return refuse(ToolCode.unavailable);
    // E9: the flag is checked at every stream, never from an older list.
    final tool = catalog.byId(request.tool);
    if (tool == null) return refuse(catalog.endCodeFor(request.tool));
    final alias = request.alias;
    if (!isToolMethod(request.method) ||
        !isToolTarget(request.target) ||
        // Never `//` (an authority), also as sent: building the URL removes
        // dot segments, and "/a/../..//host" becomes "//host".
        toolUri(tool, request.target).path.startsWith('//') ||
        !isToolHead(request.head) ||
        (alias != null && (alias < 1 || alias > 65535)) ||
        (request.ws && request.method.toUpperCase() != 'GET')) {
      return refuse(ToolCode.badRequest);
    }
    final ws = phone.streams.values.whereType<_WsStream>().length;
    final http = phone.streams.length - ws;
    if (request.ws ? ws >= kToolMaxWsStreams : http >= kToolMaxHttpStreams) {
      return refuse(ToolCode.busy);
    }
    final stream = request.ws
        ? _WsStream(this, phone, tool, request)
        : _HttpStream(this, phone, tool, request);
    phone.streams[id] = stream;
    _idleCheck ??= Timer.periodic(
      Duration(microseconds: max(1, idleTimeout.inMicroseconds ~/ 4)),
      (_) => _checkIdle(),
    );
    stream.start();
  }

  /// E10: a stream with bytes in flight and no acknowledgement for
  /// [idleTimeout] is dropped.
  void _checkIdle() {
    var any = false;
    for (final phone in [..._phones.values]) {
      for (final stream in [...phone.streams.values]) {
        any = true;
        if (stream.stalledFor >= idleTimeout) stream.abort(ToolCode.aborted);
      }
    }
    if (!any) {
      _idleCheck?.cancel();
      _idleCheck = null;
    }
  }

  /// Every message to a phone goes through here: one over a sealed batch
  /// would make `SecureChannel.seal` throw and drop the channel (terminals and
  /// AI too), so it is never sent (RF 1).
  void _emit(_Phone phone, ToolMessage message) {
    if (!phone.live) return;
    if (encodeBatch([message]).length > kMaxSealedBatchBytes) return;
    _out.add(OutboundMessage(phone.id, message));
  }
}

/// One phone's tools: what it was told, its streams, its windows.
final class _Phone {
  _Phone(this.id, this.proxy) {
    acks = ToolAckBook((ack) => proxy._emit(this, ack));
  }

  final String id;
  final ToolProxy proxy;
  bool listing = false;

  /// The list it was last sent (null: send it even when unchanged).
  ({bool available, Uint8List body})? listed;
  bool live = true;

  /// Desktop → phone bytes in flight over all its streams (E7).
  final credit = ToolCredit();

  /// What the desktop took of the phone's bodies and messages.
  late final ToolAckBook acks;
  final budget = _Bucket(kToolOpenBurst, kToolOpensPerSecond);
  final streams = <int, _Stream>{};

  /// Gone (channel lost, revoked, relay stopped): its streams end without a
  /// word to it.
  void dispose() {
    for (final stream in [...streams.values]) {
      stream.abort(null);
    }
    live = false;
    acks.clear();
  }
}

/// E10: [burst] at once, then [perSecond].
final class _Bucket {
  _Bucket(this.burst, this.perSecond) : _tokens = burst.toDouble();
  final int burst;
  final int perSecond;
  double _tokens;
  final _watch = Stopwatch()..start();
  int _last = 0;

  bool take() {
    final now = _watch.elapsedMicroseconds;
    _tokens = min(burst.toDouble(), _tokens + (now - _last) * perSecond / 1e6);
    _last = now;
    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}

/// A response nobody takes: its connection is closed.
void _drop(HttpClientResponse response) => unawaited(
  response.detachSocket().then((s) => s.destroy(), onError: (Object _) {}),
);

/// One phone stream to a tool.
sealed class _Stream {
  _Stream(this.proxy, this.phone, this.tool, this.request)
    : window = ToolSendWindow(phone.credit);

  final ToolProxy proxy;
  final _Phone phone;
  final ServedTool tool;
  final ToolRequest request;
  final ToolSendWindow window;
  bool ended = false;
  final _sinceAck = Stopwatch()..start();
  int get id => request.id;

  /// How long bytes have waited in flight without an acknowledgement.
  Duration get stalledFor =>
      window.inFlight == 0 ? Duration.zero : _sinceAck.elapsed;

  void start();
  void onData(ToolData message);
  void onWsMessage(ToolWsMessage message);
  void onPhoneEnd(ToolEnd message);

  void onAck(int total) {
    if (ended) return;
    _sinceAck.reset();
    if (!acked(total)) abort(ToolCode.badRequest);
  }

  /// Passes the acknowledgement on; false when it is beyond what was sent.
  bool acked(int total);

  void send(ToolMessage message) {
    // A stall is timed from the first piece in flight since everything was
    // acknowledged, not from an ack long before it (SSE, an idle WebSocket).
    // The outlets count a piece in [window] before they hand it here, so
    // nothing was in flight before it when it is all that is.
    final piece = switch (message) {
      ToolData(:final data) => data.length,
      ToolWsMessage(:final data) => toolWsPieceCost(data.length),
      _ => 0,
    };
    if (window.inFlight == piece) _sinceAck.reset();
    proxy._emit(phone, message);
  }

  /// Ends the stream: the phone hears [code] (nothing when null), the tool's
  /// connection is dropped.
  void abort(String? code) {
    if (ended) return;
    _finish();
    release();
    if (code != null) proxy._emit(phone, ToolEnd(id: id, code: code));
  }

  /// Drops what is held toward the tool.
  void release();

  /// The tool's answer to the phone as HTTP, for a request and for a refused
  /// upgrade alike: its head ([forwardResponseHead]; over the limits ends
  /// `too_large`), then its body within the windows. [bodyless]: the head
  /// ends the stream. The body's outlet, null when no body follows.
  ToolBytesOut? _forward(HttpClientResponse response, {bool bodyless = false}) {
    final head = forwardResponseHead(
      flatHeaders(response.headers),
      tool,
      alias: request.alias,
    );
    if (head == null) {
      _drop(response);
      abort(ToolCode.tooLarge);
      return null;
    }
    send(
      ToolResponse(
        id: id,
        status: response.statusCode,
        head: head,
        end: bodyless,
      ),
    );
    if (bodyless) {
      _drop(response);
      _finish();
      return null;
    }
    return ToolBytesOut(
      id: id,
      source: response,
      window: window,
      pacer: proxy.pacer,
      send: send,
      onError: (_) => abort(ToolCode.aborted),
      onDone: _finish,
    )..start();
  }

  /// The stream is over (both ways): forget it.
  void _finish() {
    ended = true;
    window.close();
    phone.acks.forget(id);
    if (identical(phone.streams[id], this)) phone.streams.remove(id);
  }
}

/// An HTTP request: its body to the tool, the response to the phone.
final class _HttpStream extends _Stream {
  _HttpStream(super.proxy, super.phone, super.tool, super.request);

  HttpClientRequest? _upstream;
  ToolBytesIn? _body;
  ToolBytesOut? _response;

  @override
  void start() {
    if (!request.end) {
      _body = ToolBytesIn(
        onConsumed: (total) => phone.acks.consumed(id, total),
        maxBytes: proxy.maxRequestBody,
      );
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    final HttpClientRequest upstream;
    try {
      upstream = await proxy._client.openUrl(
        request.method,
        toolUri(tool, request.target),
      );
    } on Object {
      abort(ToolCode.refused); // nothing listens, or not within 5 s (E10)
      return;
    }
    if (ended) {
      upstream.abort();
      return;
    }
    final HttpClientResponse response;
    try {
      _upstream = upstream;
      // E9: a 3xx goes to the phone as is; an upload goes as it comes. M3: a
      // connection is used for one request: dart:io takes a 1xx other than
      // 100 and 101 (103 Early Hints) for the final answer, and the real one
      // behind it on a kept-alive connection would raise an error nobody
      // hears. (Never on the WebSocket upgrade: `Connection: close` would
      // replace `Connection: Upgrade`.)
      upstream
        ..followRedirects = false
        ..persistentConnection = false
        ..bufferOutput = false;
      final head = forwardRequestHead(request.head, tool, alias: request.alias);
      head.applyTo(upstream);
      final body = _body;
      if (body != null) {
        if (head.contentLength == null) {
          upstream.headers.chunkedTransferEncoding = true;
        }
        await upstream.addStream(body.stream);
      }
      response = await upstream.close().timeout(proxy.headTimeout);
    } on TimeoutException {
      abort(ToolCode.timeout);
      return;
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      _drop(response);
      return;
    }
    final status = response.statusCode;
    _response = _forward(
      response,
      bodyless:
          request.method.toUpperCase() == 'HEAD' ||
          status == 204 ||
          status == 304 ||
          (status >= 100 && status < 200),
    );
  }

  @override
  void onData(ToolData message) {
    final body = _body;
    if (ended || body == null) return;
    if (!body.add(message.data, end: message.end)) {
      abort(
        body.received > proxy.maxRequestBody
            ? ToolCode.tooLarge
            : ToolCode.badRequest,
      );
    }
  }

  @override
  void onWsMessage(ToolWsMessage message) => abort(ToolCode.badRequest);

  @override
  void onPhoneEnd(ToolEnd message) => abort(null);

  @override
  bool acked(int total) => _response?.onAck(total) ?? total == 0;

  @override
  void release() {
    _response?.cancel();
    _body?.fail(const SocketException('ended'));
    _upstream?.abort();
  }
}

/// A WebSocket: the desktop makes its own upgrade to the tool (pinned like
/// any request), then carries messages both ways.
final class _WsStream extends _Stream {
  _WsStream(super.proxy, super.phone, super.tool, super.request);

  HttpClientRequest? _upstream;
  Socket? _socket;
  WebSocket? _ws;
  ToolWsOut? _out;
  ToolWsIn? _in;
  ToolBytesOut? _refusal;

  @override
  void start() => unawaited(_run());

  Future<void> _run() async {
    final key = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    final protocols = [
      for (final value in toolHeadValues(
        request.head,
        'sec-websocket-protocol',
      ))
        for (final p in value.split(','))
          if (p.trim().isNotEmpty) p.trim(),
    ];
    final HttpClientRequest upstream;
    try {
      upstream = await proxy._client.openUrl(
        'GET',
        toolUri(tool, request.target),
      );
    } on Object {
      abort(ToolCode.refused);
      return;
    }
    if (ended) {
      upstream.abort();
      return;
    }
    _upstream = upstream;
    final HttpClientResponse response;
    try {
      upstream.followRedirects = false;
      forwardRequestHead(
        request.head,
        tool,
        alias: request.alias,
        ws: true,
      ).applyTo(upstream);
      upstream.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('sec-websocket-key', key)
        ..set('sec-websocket-version', '13');
      response = await upstream.close().timeout(proxy.headTimeout);
    } on TimeoutException {
      abort(ToolCode.timeout);
      return;
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      _drop(response);
      return;
    }
    if (response.statusCode != HttpStatus.switchingProtocols) {
      return _refused(response);
    }
    // At most one, and one the webview offered (RFC 6455 §4.1); never
    // `headers.value`, which throws on two.
    final chosen = response.headers['sec-websocket-protocol'] ?? const [];
    final protocol = chosen.isEmpty ? null : chosen.first;
    if (chosen.length > 1 ||
        (protocol != null && !protocols.contains(protocol))) {
      _drop(response);
      abort(ToolCode.aborted); // a protocol the webview did not offer
      return;
    }
    final Socket socket;
    try {
      socket = await response.detachSocket();
    } on Object {
      abort(ToolCode.aborted);
      return;
    }
    if (ended) {
      socket.destroy();
      return;
    }
    _socket = socket;
    final ws = _ws = WebSocket.fromUpgradedSocket(
      socket,
      protocol: protocol,
      serverSide: false,
    );
    send(
      ToolResponse(
        id: id,
        status: HttpStatus.switchingProtocols,
        head: [
          if (protocol != null) ...['sec-websocket-protocol', protocol],
        ],
        end: false,
      ),
    );
    _in = ToolWsIn(
      write: (message) => ws.addStream(Stream.value(message)),
      onConsumed: (total) => phone.acks.consumed(id, total),
      maxMessage: proxy.maxWsMessage,
    );
    _out = ToolWsOut(
      id: id,
      source: ws,
      window: window,
      pacer: proxy.pacer,
      send: send,
      maxMessage: proxy.maxWsMessage,
      onTooBig: () => _closeBoth(WebSocketStatus.messageTooBig, null),
      onDone: () => _closed(ws.closeCode, ws.closeReason),
    )..start();
  }

  /// The tool did not upgrade: the phone gets its answer as plain HTTP.
  void _refused(HttpClientResponse response) {
    _refusal = _forward(response);
  }

  /// The tool closed: the phone hears its code.
  void _closed(int? code, String? reason) {
    if (ended) return;
    _finish();
    release();
    proxy._emit(phone, ToolEnd(id: id, wsCode: code, wsReason: reason));
  }

  /// Ends the stream with a close frame to the tool ([code], once what the
  /// phone sent was written); the phone hears [code] too unless it closed
  /// first ([tellPhone]).
  void _closeBoth(int? code, String? reason, {bool tellPhone = true}) {
    if (ended) return;
    _finish();
    _out?.discard(); // keep reading: the tool's close frame must come in
    _refusal?.cancel();
    _closeTool(code, reason);
    if (tellPhone) {
      proxy._emit(phone, ToolEnd(id: id, wsCode: code, wsReason: reason));
    }
  }

  void _closeTool(int? code, String? reason) {
    final ws = _ws;
    if (ws == null) return;
    final valid = code != null && _sendable(code);
    unawaited(
      (_in?.idle ?? Future<void>.value())
          .timeout(const Duration(seconds: 5))
          .then((_) => valid ? ws.close(code, reason) : ws.close())
          .catchError((Object _) => _socket?.destroy()),
    );
  }

  /// A close code an endpoint may send (RFC 6455 §7.4).
  static bool _sendable(int code) =>
      (code >= 1000 && code <= 1003) ||
      (code >= 1007 && code <= 1011) ||
      (code >= 3000 && code <= 4999);

  @override
  void onData(ToolData message) => abort(ToolCode.badRequest);

  @override
  void onWsMessage(ToolWsMessage message) {
    final input = _in;
    if (ended || input == null) return;
    if (!input.add(message)) _closeBoth(WebSocketStatus.messageTooBig, null);
  }

  @override
  void onPhoneEnd(ToolEnd message) {
    if (ended) return;
    if (message.code != null || _ws == null) {
      abort(null);
      return;
    }
    // The webview closed: the tool hears the same code once everything the
    // phone sent was written.
    _closeBoth(message.wsCode, _truncate(message.wsReason), tellPhone: false);
  }

  /// [reason] within a close frame's 123 bytes of UTF-8, cut at a character
  /// boundary (one pass: a long reason from the phone never stalls us).
  static String? _truncate(String? reason) {
    if (reason == null) return null;
    final bytes = utf8.encode(reason);
    if (bytes.length <= 123) return reason;
    var end = 123;
    while ((bytes[end] & 0xC0) == 0x80) {
      end--; // a continuation byte: the character starts before it
    }
    return utf8.decode(bytes.sublist(0, end));
  }

  @override
  bool acked(int total) =>
      (_out?.onAck(total) ?? _refusal?.onAck(total)) ?? total == 0;

  @override
  void release() {
    _upstream?.abort(); // drops the connection while the tool has not answered
    _out?.cancel();
    _refusal?.cancel();
    _socket?.destroy();
  }
}
