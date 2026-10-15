import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';
import 'machine_tools.dart';

/// V2-4 E15, E16: where the page of an open tool is.
enum ToolPhase {
  /// Asking the computer (first open, or again after a change).
  opening,

  /// Served: the webview shows the page.
  ready,

  /// Nothing listens on the tool's port on the computer: tried again by
  /// itself (1, 2, 4, 8 s, then every 10 s).
  refused,

  /// Its phone flag was turned off.
  disabled,

  /// Deleted on the computer, or its URL changed.
  gone,

  /// The computer has no list yet (only the background service runs).
  unavailable,

  /// The computer has too many streams of this phone; tried again.
  busy,

  /// The channel is gone: the page stays, and reloads when it is back.
  reconnecting,

  /// The app is in the background: nothing is served (Apple TN2277).
  paused,

  /// The page was left.
  closed,
}

/// What the page must do (the webview's side of E13, E3, E12).
sealed class ToolPageEvent {
  const ToolPageEvent();
}

/// Load [url]: the phone's one-time entry page, which sets the gate cookie
/// and goes on to the start page.
final class ToolLoad extends ToolPageEvent {
  const ToolLoad(this.url);
  final Uri url;
  @override
  String toString() => 'ToolLoad(…)';
}

/// Reload the page (the channel or the tool came back).
final class ToolReload extends ToolPageEvent {
  const ToolReload();
}

/// A page asked for the tool on [port] of the same workspace, which is not
/// on for the phone any more (E4).
final class ToolSiblingOff extends ToolPageEvent {
  const ToolSiblingOff(this.port);
  final int port;
}

/// The tool sent a file to download (E12: not on the phone yet).
final class ToolDownloadBlocked extends ToolPageEvent {
  const ToolDownloadBlocked();
}

/// The plain-text bodies the phone's server answers with itself; the app
/// gives them in the phone's language.
class ToolHostTexts {
  const ToolHostTexts();
  String refused(int port) =>
      'Nothing is running at localhost:$port on the computer.';
  String siblingOff(int port) => "The tool on port $port isn't on for phone.";
  String get disabled => 'This tool can no longer be opened on the phone.';
  String get gone => 'This tool was deleted on the computer.';
  String get needsDesktop => 'Open ShellX on the computer to use tools.';
  String get tooLarge => "The tool's response is too large.";
}

/// The delays between tries while the tool's port refuses (V2-3 D13).
const List<Duration> kToolRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 10),
];

const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

const _policyHeader = 'content-security-policy';

/// RFC 6455: the `Sec-WebSocket-Accept` for [key].
String webSocketAccept(String key) => base64Encode(
  const DartSha1().hashSync(utf8.encode('$key$_webSocketGuid')).bytes,
);

/// The top-level CSP ruling: the one `Content-Security-Policy` the phone's
/// server adds to every response of a tool page, for [ports] (every port it
/// serves for that page: the tool's own or its alias P′ (E3), and the other
/// tools of its workspace (E4)), deduplicated and in ascending order.
///
/// Cookies ignore ports: the webview would send the gate cookie (and the
/// tool's own cookies) to any `localhost` port a page asks for, and an app
/// on the phone listening there would get the secret (spec §9 Review Focus
/// 5). The policy keeps every subresource, fetch, WebSocket, frame, worker
/// and form of the page on the served ports, on `https:`/`wss:` (a
/// localhost certificate fails before a cookie is sent), and on `data:` and
/// `blob:`. `'unsafe-inline' 'unsafe-eval'` keep dev servers working (Vite's
/// inline preamble, eval source maps); a tool's own, stricter policy still
/// applies beside it. Never `upgrade-insecure-requests`.
String toolContentSecurityPolicy(Iterable<int> ports) {
  final served = ports.toSet().toList()..sort();
  return [
    "default-src 'self'",
    for (final q in served) 'http://localhost:$q ws://localhost:$q',
    "https: wss: data: blob: 'unsafe-inline' 'unsafe-eval';",
    "form-action 'self'",
    for (final q in served) 'http://localhost:$q',
    'https:',
  ].join(' ');
}

/// V2-4 E2, E3, E11, E13: the phone's side of one open tool. It serves the
/// tool (and the other tools of its workspace, E4) on this phone's loopback
/// only, on the tool's own port when it can (else another, E3), and carries
/// every request through [link] to the computer. Only the page's webview
/// gets in: a one-time entry URL ([ToolLoad]) sets an HttpOnly, SameSite
/// gate cookie, and every request must carry it and name a loopback host.
/// Pure Dart (`dart:io`); never logs what it carries.
final class ToolSession {
  ToolSession({
    required this.tool,
    required int port,
    required String path,
    required this.link,
    this.texts = const ToolHostTexts(),
    this.nonceLife = const Duration(seconds: 10),
    this.maxRequestBody = kToolMaxRequestBodyBytes,
    this.maxWsMessage = kToolMaxWsMessageBytes,
    this.retryDelays = kToolRetryDelays,
  }) : _port = port,
       _path = path;

  /// The tool's id (never its URL: E1).
  final String tool;
  final MachineTools link;
  final ToolHostTexts texts;
  final Duration nonceLife;
  final int maxRequestBody;
  final int maxWsMessage;
  final List<Duration> retryDelays;

  final int _port;
  String _path;
  ToolPhase _phase = ToolPhase.opening;
  final _servers = <_Served>[];
  final _streams = <_Stream>{};
  String _secret = '';
  String? _nonce;
  DateTime? _nonceAt;
  int _requests = 0;
  final _events = StreamController<ToolPageEvent>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast(sync: true);
  void Function()? _release;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _retry;
  int _tries = 0;
  bool _checking = false;
  bool _checkAgain = false;

  ToolPhase get phase => _phase;

  /// The tool's port on the computer.
  int get port => _port;

  /// The port this phone serves the tool on; null while nothing is served.
  int? get servedPort => _servers.isEmpty ? null : _servers.first.port;

  /// The served port when it is not the tool's own (E3); null otherwise.
  int? get alias {
    final served = servedPort;
    return served != null && served != _port ? served : null;
  }

  /// The origins this phone serves now (the webview may go there, E12).
  Set<String> get origins => {
    for (final served in _servers) 'http://localhost:${served.port}',
  };

  /// Requests served since [resetRequests] (E20).
  int get requests => _requests;
  void resetRequests() => _requests = 0;

  Stream<ToolPageEvent> get events => _events.stream;

  /// After every change of [phase].
  Stream<void> get changes => _changes.stream;

  /// Opens the tool: asks the computer, then serves it.
  void start() {
    _release ??= link.hold();
    _subscriptions
      ..add(link.links.listen(_onLink))
      ..add(link.listings.listen(_onListing));
    unawaited(_check());
  }

  /// "Về trang đầu": the start page.
  void home() {
    final served = servedPort;
    if (served != null && _phase == ToolPhase.ready) {
      _events.add(ToolLoad(Uri.parse('http://localhost:$served$_path')));
    }
  }

  /// The app goes to the background (E13): nothing is served until
  /// [resume]; every stream ends.
  Future<void> pause() async {
    if (_phase == ToolPhase.closed) return;
    _retry?.cancel();
    await _unserve();
    _set(ToolPhase.paused);
  }

  /// The app is back: served again (the port may change), then loaded.
  void resume() {
    if (_phase != ToolPhase.paused) return;
    _set(ToolPhase.opening);
    unawaited(_check());
  }

  /// The page was left (E13): nothing is served, the computer is told.
  Future<void> close() async {
    if (_phase == ToolPhase.closed) return;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _unserve();
    link.enqueue(ToolClose(tool: tool));
    _release?.call();
    _release = null;
    _set(ToolPhase.closed);
    unawaited(_events.close());
    unawaited(_changes.close());
  }

  void _set(ToolPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    if (!_changes.isClosed) _changes.add(null);
  }

  void _onLink(bool up) {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    if (!up) {
      _set(ToolPhase.reconnecting);
    } else {
      unawaited(_check());
    }
  }

  void _onListing(ToolListing listing) {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    final me = listing.tools.where((t) => t.id == tool).firstOrNull;
    if (!listing.available || me == null || me.port != _port) {
      unawaited(_check());
    }
  }

  /// Asks the computer about the tool (`tool.open`) and acts on the answer.
  Future<void> _check() async {
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    try {
      do {
        _checkAgain = false;
        await _checkOnce();
      } while (_checkAgain);
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkOnce() async {
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    final ToolOpened opened;
    try {
      opened = await link.open(tool);
    } on MachineConnectionException {
      _set(ToolPhase.reconnecting); // asked again when the channel is back
      return;
    }
    if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) return;
    if (!opened.ok) {
      final code = toolEndCode(opened.code) ?? ToolCode.gone;
      switch (code) {
        case ToolCode.refused || ToolCode.busy:
          _set(code == ToolCode.busy ? ToolPhase.busy : ToolPhase.refused);
          _scheduleRetry();
        case ToolCode.disabled:
          await _unserve();
          _set(ToolPhase.disabled);
        case ToolCode.unavailable || ToolCode.desktopClosed:
          await _unserve();
          _set(ToolPhase.unavailable);
        default:
          await _unserve();
          _set(ToolPhase.gone);
      }
      return;
    }
    final serving = ToolServing.fromBody(opened.body);
    final main = serving.isEmpty ? null : serving.first;
    if (main == null || main.id != tool || main.port != _port) {
      // §7: its URL changed on the computer; the user opens it again.
      await _unserve();
      _set(ToolPhase.gone);
      return;
    }
    _tries = 0;
    _path = main.path;
    final wasReady = _phase == ToolPhase.ready;
    if (_servers.isEmpty) {
      await _serve(serving);
      if (_phase == ToolPhase.closed || _phase == ToolPhase.paused) {
        await _unserve();
        return;
      }
      if (_servers.isEmpty) {
        _set(ToolPhase.refused); // no port at all on this phone
        _scheduleRetry();
        return;
      }
      _set(ToolPhase.ready);
      _events.add(ToolLoad(_entryUrl()));
    } else {
      _set(ToolPhase.ready);
      if (!wasReady) _events.add(const ToolReload());
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final delay = retryDelays[min(_tries, retryDelays.length - 1)];
    _tries++;
    _retry = Timer(delay, () => unawaited(_check()));
  }

  /// A request of the main tool was refused or the tool left the list: the
  /// computer is asked again (once at a time).
  void _recheck() {
    if (_phase == ToolPhase.ready) unawaited(_check());
  }

  // ------------------------------------------------------------- serving --

  String _random() {
    final r = Random.secure();
    return base64UrlNoPad(
      Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))),
    );
  }

  Uri _entryUrl() {
    final nonce = _nonce = _random();
    _nonceAt = DateTime.now();
    return Uri(
      scheme: 'http',
      host: 'localhost',
      port: servedPort,
      path: '${kToolReservedPrefix}enter',
      queryParameters: {'n': nonce, 'to': _path},
    );
  }

  String get _cookieName => toolGateCookieName(servedPort ?? _port);

  /// Binds the tool on its port (or another, E3) and each other tool of the
  /// workspace on its own port when it is free (E4).
  Future<void> _serve(List<ToolServing> serving) async {
    _secret = _random();
    final main = serving.first;
    final own = await _bind(main.port) ?? await _bind(0);
    if (own == null) return;
    _servers.add(_Served(this, main.id, own, main: true));
    for (final other in serving.skip(1)) {
      final servers = await _bind(other.port);
      if (servers != null) _servers.add(_Served(this, other.id, servers));
    }
  }

  /// 127.0.0.1:[port] and, when it can, [::1] on the same port; never any
  /// other address (E11). Null when the port cannot be had.
  Future<List<HttpServer>?> _bind(int port) async {
    final HttpServer v4;
    try {
      v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException {
      return null;
    }
    final servers = [v4];
    try {
      servers.add(
        await HttpServer.bind(
          InternetAddress.loopbackIPv6,
          v4.port,
          v6Only: true,
        ),
      );
    } on SocketException {
      // IPv4 only: `localhost` still reaches it.
    }
    for (final server in servers) {
      server
        ..defaultResponseHeaders
            .clear() // E11: nothing the tool did not send
        ..serverHeader = null
        ..autoCompress = false;
    }
    return servers;
  }

  Future<void> _unserve() async {
    for (final stream in [..._streams]) {
      stream.abort();
    }
    _streams.clear();
    final servers = [..._servers];
    _servers.clear();
    _nonce = null;
    for (final served in servers) {
      await served.close();
    }
  }

  bool _allowedOrigin(String origin) {
    for (final served in _servers) {
      if (toolLoopbackPrefix(origin, served.port) == origin) return true;
    }
    return false;
  }

  bool _hasGate(HttpRequest request) {
    final expected = utf8.encode(_secret);
    for (final cookie in request.headers['cookie'] ?? const <String>[]) {
      for (final pair in cookie.split(';')) {
        final at = pair.indexOf('=');
        if (at < 0 || pair.substring(0, at).trim() != _cookieName) continue;
        final value = utf8.encode(pair.substring(at + 1).trim());
        if (constantTimeEquals(value, expected)) return true;
      }
    }
    return false;
  }

  Future<void> _handle(_Served served, int port, HttpRequest request) async {
    final response = request.response;
    // E11: a page of another host (DNS rebinding) is refused.
    final host = request.headers.value(HttpHeaders.hostHeader) ?? '';
    if (!isToolLoopbackAuthority(host, port)) {
      return _answer(request, HttpStatus.forbidden);
    }
    // E11: the reserved prefix is the phone's own, never the tool's.
    if (request.uri.path.startsWith(kToolReservedPrefix)) {
      return _enter(request, served);
    }
    final origin = request.headers.value('origin');
    final preflight =
        request.method == 'OPTIONS' &&
        origin != null &&
        _allowedOrigin(origin) &&
        request.headers.value('access-control-request-method') != null;
    // E11: only the page's webview has the gate cookie (a CORS preflight of
    // one of the served origins carries none: it is let through, R6).
    if (!preflight && !_hasGate(request)) {
      return _answer(request, HttpStatus.forbidden);
    }
    final upgrade = WebSocketTransformer.isUpgradeRequest(request);
    final safe = const {'GET', 'HEAD', 'OPTIONS'}.contains(request.method);
    if (!safe || upgrade) {
      if (origin != null && !_allowedOrigin(origin)) {
        return _answer(request, HttpStatus.forbidden);
      }
      if (request.headers.value('sec-fetch-site') == 'cross-site') {
        return _answer(request, HttpStatus.forbidden);
      }
    }
    switch (_phase) {
      case ToolPhase.ready:
        break;
      case ToolPhase.disabled:
        return _answer(request, HttpStatus.badGateway, texts.disabled);
      case ToolPhase.gone:
        return _answer(request, HttpStatus.badGateway, texts.gone);
      case ToolPhase.unavailable:
        return _answer(
          request,
          HttpStatus.serviceUnavailable,
          texts.needsDesktop,
        );
      default:
        return _answer(request, HttpStatus.serviceUnavailable);
    }
    if (!link.connected) {
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    final uri = request.uri;
    if (uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasFragment ||
        !uri.path.startsWith('/')) {
      return _answer(request, HttpStatus.badRequest);
    }
    final target = uri.toString();
    if (!isToolTarget(target)) {
      return _answer(request, HttpStatus.requestUriTooLong);
    }
    if (!isToolMethod(request.method)) {
      return _answer(request, HttpStatus.methodNotAllowed);
    }
    final head = _head(request);
    if (!isToolHead(head)) {
      return _answer(request, HttpStatus.requestHeaderFieldsTooLarge);
    }
    final length = request.headers.contentLength;
    if (length > maxRequestBody) {
      return _answer(request, HttpStatus.requestEntityTooLarge);
    }
    final ws = _streams.whereType<_WsStream>().length;
    final http = _streams.length - ws;
    if (upgrade ? ws >= kToolMaxWsStreams : http >= kToolMaxHttpStreams) {
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    _requests++;
    final id = link.newStreamId();
    final stream = upgrade
        ? _WsStream(this, served, id, request)
        : _HttpStream(
            this,
            served,
            id,
            request,
            hasBody: length > 0 || request.headers.chunkedTransferEncoding,
          );
    _streams.add(stream);
    link.listen(id, stream);
    final sent = link.enqueue(
      ToolRequest(
        id: id,
        tool: served.tool,
        method: request.method,
        target: target,
        head: head,
        alias: served.main ? alias : null,
        ws: upgrade,
        end: stream is! _HttpStream || !stream.hasBody,
      ),
    );
    if (!sent) {
      stream.forget();
      return _answer(request, HttpStatus.serviceUnavailable);
    }
    response.bufferOutput = false; // a piece goes as it comes (SSE)
    stream.start();
  }

  /// The request's head as the computer gets it: no hop-by-hop header, no
  /// gate cookie (E11).
  List<String> _head(HttpRequest request) {
    final raw = <String>[];
    request.headers.forEach((name, values) {
      for (final value in values) {
        raw
          ..add(name)
          ..add(value);
      }
    });
    final dropped = toolDroppedNames(raw);
    final head = <String>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      final name = raw[i];
      if (dropped.contains(name)) continue;
      final value = name == 'cookie'
          ? stripToolGateCookies(raw[i + 1])
          : raw[i + 1];
      if (value == null) continue;
      head
        ..add(name)
        ..add(value);
    }
    return head;
  }

  /// `/__shellx/enter?n=<nonce>&to=<path>`: once, within [nonceLife], sets
  /// the gate cookie and goes on to `to` (E11). Anything else there: 404.
  Future<void> _enter(HttpRequest request, _Served served) async {
    final uri = request.uri;
    if (uri.path != '${kToolReservedPrefix}enter' || !served.main) {
      return _answer(request, HttpStatus.notFound);
    }
    final nonce = _nonce;
    final at = _nonceAt;
    final given = uri.queryParameters['n'] ?? '';
    final fresh =
        nonce != null &&
        at != null &&
        DateTime.now().difference(at) <= nonceLife &&
        constantTimeEquals(utf8.encode(given), utf8.encode(nonce));
    if (!fresh) return _answer(request, HttpStatus.forbidden);
    _nonce = null; // one time only
    final to = uri.queryParameters['to'] ?? '/';
    final response = request.response..statusCode = HttpStatus.seeOther;
    _addPolicy(response);
    response
      ..headers.set(HttpHeaders.locationHeader, isToolTarget(to) ? to : '/')
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('referrer-policy', 'no-referrer')
      ..headers.add(
        HttpHeaders.setCookieHeader,
        '$_cookieName=$_secret; Path=/; HttpOnly; SameSite=Strict',
      )
      ..contentLength = 0;
    await request.drain<void>().catchError((Object _) {});
    await response.close().catchError((Object _) => response);
  }

  /// The top-level CSP ruling: ShellX's one policy on [response], for the
  /// ports served at the moment its head is written (a tool served after
  /// the page loaded is reachable from it after a reload). Each policy is a
  /// line of its own, never folded into a tool's (browsers enforce each):
  /// call it before a tool's headers are copied, which only ever `add`.
  void _addPolicy(HttpResponse response) {
    response.headers
      ..noFolding(_policyHeader)
      ..add(
        _policyHeader,
        toolContentSecurityPolicy([for (final served in _servers) served.port]),
      );
  }

  /// Answers [request] here, with [text] as a plain body when given. The
  /// request is read to its end before the response is closed — by [read]
  /// when a stream reads it already (a second `listen` throws), else drained
  /// here — so a webview still sending a body takes the answer (dart:io
  /// drops a connection whose request it did not read). Whatever happens to
  /// the request, the response is closed.
  Future<void> _answer(
    HttpRequest request,
    int status, [
    String? text,
    Future<void>? read,
  ]) async {
    final response = request.response;
    try {
      response.statusCode = status;
      _addPolicy(response);
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (text == null) {
        response.contentLength = 0;
      } else {
        final bytes = utf8.encode(text);
        response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/plain; charset=utf-8',
        );
        response.contentLength = bytes.length;
        response.add(bytes);
      }
    } on Object {
      return; // the webview went away
    }
    try {
      await (read ?? request.drain<void>());
    } on Object {
      // The webview went away while sending.
    }
    try {
      await response.close();
    } on Object {
      // The webview went away meanwhile.
    }
  }

  /// What [stream], ended before its response, answers the webview.
  Future<void> _answerEnd(_Stream stream, String? code) {
    final served = stream.served;
    final c = toolEndCode(code) ?? ToolCode.aborted;
    if (served.main &&
        (c == ToolCode.refused ||
            c == ToolCode.disabled ||
            c == ToolCode.gone ||
            c == ToolCode.unavailable)) {
      _recheck();
    }
    if (!served.main && (c == ToolCode.disabled || c == ToolCode.gone)) {
      _events.add(ToolSiblingOff(served.port));
    }
    return switch (c) {
      ToolCode.refused => stream.reply(
        HttpStatus.badGateway,
        texts.refused(served.main ? _port : served.port),
      ),
      ToolCode.disabled || ToolCode.gone =>
        served.main
            ? stream.reply(HttpStatus.badGateway, texts.disabled)
            : stream.reply(
                HttpStatus.badGateway,
                texts.siblingOff(served.port),
              ),
      ToolCode.busy => stream.reply(HttpStatus.serviceUnavailable),
      ToolCode.tooLarge => stream.reply(HttpStatus.badGateway, texts.tooLarge),
      ToolCode.timeout => stream.reply(HttpStatus.gatewayTimeout),
      ToolCode.unavailable || ToolCode.desktopClosed => stream.reply(
        HttpStatus.serviceUnavailable,
        texts.needsDesktop,
      ),
      ToolCode.badRequest => stream.reply(HttpStatus.badRequest),
      _ => stream.reply(HttpStatus.badGateway),
    };
  }

  @override
  String toString() => 'ToolSession(…)';
}

/// One tool served on this phone: its servers (IPv4 and maybe IPv6).
final class _Served {
  _Served(this.session, this.tool, this.servers, {this.main = false}) {
    for (final server in servers) {
      server.listen(
        (request) => unawaited(
          session._handle(this, server.port, request).catchError((Object _) {}),
        ),
        onError: (Object _) {},
      );
    }
  }

  final ToolSession session;
  final String tool;
  final List<HttpServer> servers;
  final bool main;

  int get port => servers.first.port;

  Future<void> close() async {
    for (final server in servers) {
      await server.close(force: true).catchError((Object _) => server);
    }
  }
}

/// One webview request through the tunnel.
sealed class _Stream implements ToolStreamListener {
  _Stream(this.session, this.served, this.id, this.request)
    : window = ToolSendWindow(session.link.credit);

  final ToolSession session;
  final _Served served;
  final int id;
  final HttpRequest request;
  final ToolSendWindow window;
  bool done = false;
  bool responded = false;

  MachineTools get link => session.link;

  void start();

  /// Completes once the request was read to its end, when this stream reads
  /// it; null when nothing does (an answer drains it then).
  Future<void>? get read => null;

  /// Answers the webview here, before any response of the tool.
  Future<void> reply(int status, [String? text]) =>
      session._answer(request, status, text, read);

  /// Ended here (page left, app paused): the computer is told.
  void abort() {
    if (done) return;
    link.enqueue(ToolEnd(id: id, code: ToolCode.aborted));
    forget();
    cut();
  }

  /// Drops what is held toward the webview.
  void cut();

  /// The stream is over: forget it.
  void forget() {
    done = true;
    window.close();
    link.release(id);
    session._streams.remove(this);
  }

  @override
  void onLost() {
    if (done) return;
    forget();
    if (responded) {
      cut();
    } else {
      unawaited(reply(HttpStatus.badGateway));
    }
  }
}

/// An HTTP request: its body to the computer, the answer to the webview.
final class _HttpStream extends _Stream {
  _HttpStream(
    super.session,
    super.served,
    super.id,
    super.request, {
    required this.hasBody,
  });

  final bool hasBody;
  ToolBytesOut? _body;
  ToolBytesIn? _answer;

  /// The webview's request, read by this stream from [start] on.
  StreamSubscription<List<int>>? _upload;
  final _read = Completer<void>();

  @override
  Future<void> get read => _read.future;

  void _readAll() {
    if (!_read.isCompleted) _read.complete();
  }

  @override
  void start() {
    final source = hasBody ? StreamController<List<int>>(sync: true) : null;
    final upload = _upload = request.listen(
      source?.add,
      onError: (Object error) {
        _readAll();
        source?.addError(error);
      },
      onDone: () {
        _readAll();
        unawaited(source?.close());
      },
      cancelOnError: true,
    );
    if (source == null) return; // no body: read to its end
    // The outlet reads the body through [source], pausing the request with
    // it. Once the outlet stops (the stream is over, or the body too large)
    // what is left is read and dropped, so a webview still sending finishes
    // and takes the answer: cancelling the request itself would make dart:io
    // drop the connection before the answer is out.
    source
      ..onPause = upload.pause
      ..onResume = upload.resume
      ..onCancel = () {
        upload.onData(null);
        if (upload.isPaused) upload.resume();
      };
    _body = ToolBytesOut(
      id: id,
      source: source.stream,
      window: window,
      pacer: const ToolUnpaced(),
      send: link.enqueue,
      maxBytes: session.maxRequestBody,
      onTooLarge: () {
        if (done) return;
        link.enqueue(ToolEnd(id: id, code: ToolCode.aborted));
        forget();
        if (responded) {
          cut(); // the tool's answer is under way: it is cut
        } else {
          unawaited(reply(HttpStatus.requestEntityTooLarge));
        }
      },
      onError: (_) => abort(),
    )..start();
  }

  /// Every end of the stream stops the body's outlet (it would otherwise
  /// wait on the shared credit, holding its buffer and the request).
  @override
  void forget() {
    _body?.cancel();
    super.forget();
  }

  /// Closes the forwarded [response] once the request was read to its end.
  Future<void> _close(HttpResponse response) async {
    await read;
    try {
      await response.close();
    } on Object {
      // The webview went away.
    }
  }

  @override
  void onResponse(ToolResponse message) {
    if (done || responded) return;
    responded = true;
    final response = request.response;
    final status = message.status;
    if (status < 100 || status > 599 || status == 101) {
      forget();
      unawaited(reply(HttpStatus.badGateway));
      return;
    }
    response.statusCode = status;
    session._addPolicy(response); // before the tool's own (CSP ruling)
    int? length;
    for (var i = 0; i + 1 < message.head.length; i += 2) {
      final name = message.head[i];
      final value = message.head[i + 1];
      if (name == 'content-length') {
        length = int.tryParse(value);
        continue;
      }
      if (kToolHopByHop.contains(name) || !isWritableHeaderValue(value)) {
        continue;
      }
      if (name == 'content-disposition' &&
          value.toLowerCase().startsWith('attachment')) {
        session._events.add(const ToolDownloadBlocked());
      }
      try {
        response.headers.add(name, value);
      } on FormatException {
        // A name dart:io refuses: left out.
      }
    }
    final head = request.method == 'HEAD';
    final noBody = status == 204 || status == 304 || status < 200;
    if (length != null && length >= 0 && !noBody) {
      response.contentLength = length;
    }
    if (message.end || head || noBody) {
      forget();
      unawaited(_close(response));
      return;
    }
    final inlet = _answer = ToolBytesIn(
      onConsumed: (total) => link.acks.consumed(id, total),
    );
    unawaited(
      response
          .addStream(inlet.stream)
          .then((_) => _close(response))
          .catchError((Object _) {}),
    );
  }

  @override
  void onData(ToolData message) {
    final inlet = _answer;
    if (done || inlet == null) return;
    if (!inlet.add(message.data, end: message.end)) {
      abort();
      return;
    }
    if (message.end) forget();
  }

  @override
  void onWsMessage(ToolWsMessage message) => abort();

  @override
  void onAck(int total) {
    if (_body?.onAck(total) == false) abort();
  }

  @override
  void onEnd(ToolEnd message) {
    if (done) return;
    forget();
    if (responded) {
      cut();
    } else {
      unawaited(session._answerEnd(this, message.code));
    }
  }

  @override
  void cut() {
    _body?.cancel();
    _answer?.fail(const SocketException('cut'));
    if (!responded) {
      unawaited(reply(HttpStatus.badGateway));
    } else {
      // The response is cut: its connection goes, the request with it.
      unawaited(_upload?.cancel());
      _readAll();
    }
  }
}

/// A WebSocket: upgraded once the tool's side is open (`tool.res 101`).
final class _WsStream extends _Stream {
  _WsStream(super.session, super.served, super.id, super.request);

  Socket? _socket;
  WebSocket? _ws;
  ToolWsOut? _out;
  ToolWsIn? _in;
  ToolBytesIn? _refusal;

  List<String> get _offered => [
    for (final value in request.headers['sec-websocket-protocol'] ?? const [])
      for (final p in value.split(','))
        if (p.trim().isNotEmpty) p.trim(),
  ];

  @override
  void start() {}

  @override
  void onResponse(ToolResponse message) {
    if (done || responded) return;
    responded = true;
    if (message.status != HttpStatus.switchingProtocols) {
      _refused(message);
      return;
    }
    final protocols = toolHeadValues(message.head, 'sec-websocket-protocol');
    final protocol = protocols.isEmpty ? null : protocols.first;
    final key = request.headers.value('sec-websocket-key');
    if (key == null || (protocol != null && !_offered.contains(protocol))) {
      abort();
      return;
    }
    unawaited(_upgrade(key, protocol));
  }

  Future<void> _upgrade(String key, String? protocol) async {
    final response = request.response
      ..statusCode = HttpStatus.switchingProtocols;
    session._addPolicy(response);
    response
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('sec-websocket-accept', webSocketAccept(key))
      ..contentLength = 0;
    if (protocol != null) {
      response.headers.set('sec-websocket-protocol', protocol);
    }
    final Socket socket;
    try {
      socket = await response.detachSocket();
    } on Object {
      abort();
      return;
    }
    if (done) {
      socket.destroy();
      return;
    }
    _socket = socket;
    final ws = _ws = WebSocket.fromUpgradedSocket(
      socket,
      protocol: protocol,
      serverSide: true,
    );
    _in = ToolWsIn(
      write: (message) => ws.addStream(Stream.value(message)),
      onConsumed: (total) => link.acks.consumed(id, total),
      maxMessage: session.maxWsMessage,
    );
    _out = ToolWsOut(
      id: id,
      source: ws,
      window: window,
      pacer: const ToolUnpaced(),
      send: link.enqueue,
      maxMessage: session.maxWsMessage,
      onTooBig: () => _closeBoth(WebSocketStatus.messageTooBig),
      onDone: () {
        if (done) return;
        link.enqueue(
          ToolEnd(id: id, wsCode: ws.closeCode, wsReason: ws.closeReason),
        );
        forget();
        _socket?.destroy();
      },
    )..start();
  }

  /// The tool would not upgrade: the webview gets its answer as HTTP.
  void _refused(ToolResponse message) {
    final response = request.response..statusCode = message.status;
    session._addPolicy(response); // before the tool's own (CSP ruling)
    for (var i = 0; i + 1 < message.head.length; i += 2) {
      final name = message.head[i];
      final value = message.head[i + 1];
      if (kToolHopByHop.contains(name) ||
          name == 'content-length' ||
          !isWritableHeaderValue(value)) {
        continue;
      }
      try {
        response.headers.add(name, value);
      } on FormatException {
        // left out
      }
    }
    if (message.end) {
      forget();
      unawaited(response.close().catchError((Object _) => response));
      return;
    }
    final inlet = _refusal = ToolBytesIn(
      onConsumed: (total) => link.acks.consumed(id, total),
    );
    unawaited(
      response
          .addStream(inlet.stream)
          .then((_) => response.close())
          .catchError((Object _) => response),
    );
  }

  /// A message over the limit: both sides close with [code].
  void _closeBoth(int code) {
    if (done) return;
    link.enqueue(ToolEnd(id: id, wsCode: code));
    forget();
    _out?.discard();
    _closeWebview(code, null);
  }

  void _closeWebview(int? code, String? reason) {
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

  static bool _sendable(int code) =>
      (code >= 1000 && code <= 1003) ||
      (code >= 1007 && code <= 1011) ||
      (code >= 3000 && code <= 4999);

  @override
  void onData(ToolData message) {
    final inlet = _refusal;
    if (done || inlet == null) return;
    if (!inlet.add(message.data, end: message.end)) {
      abort();
      return;
    }
    if (message.end) forget();
  }

  @override
  void onWsMessage(ToolWsMessage message) {
    final input = _in;
    if (done || input == null) return;
    if (!input.add(message)) _closeBoth(WebSocketStatus.messageTooBig);
  }

  @override
  void onAck(int total) {
    if (_out?.onAck(total) == false) abort();
  }

  @override
  void onEnd(ToolEnd message) {
    if (done) return;
    forget();
    if (!responded) {
      unawaited(session._answerEnd(this, message.code));
      return;
    }
    if (_ws == null) {
      _refusal?.fail(const SocketException('cut'));
      return;
    }
    _out?.discard();
    // The tool closed (its code), or the stream failed (going away).
    _closeWebview(
      message.code == null ? message.wsCode : WebSocketStatus.goingAway,
      message.code == null ? message.wsReason : null,
    );
  }

  @override
  void cut() {
    _out?.cancel();
    _refusal?.fail(const SocketException('cut'));
    final ws = _ws;
    if (ws != null) {
      _closeWebview(WebSocketStatus.goingAway, null);
    } else if (!responded) {
      unawaited(reply(HttpStatus.badGateway));
    }
  }
}
