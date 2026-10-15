import 'dart:io';

import 'package:shellx_core/shellx_core.dart';

import 'tool_catalog.dart';

/// V2-4 E10: connecting to a tool's port gives up after this (`refused`).
const Duration kToolConnectTimeout = Duration(seconds: 5);

/// V2-4 E10: a response head that takes longer ends the stream (`timeout`).
/// Once the body streams there is no limit (SSE, long polling).
const Duration kToolHeadTimeout = Duration(seconds: 60);

/// V2-4 E10: a stream with bytes in flight and no acknowledgement for this
/// long is dropped.
const Duration kToolIdleTimeout = Duration(minutes: 5);

/// V2-4 E9: a socket to [port] on this computer: 127.0.0.1, then ::1. A name
/// is never resolved, so nothing but this computer's loopback is reached.
Future<Socket> connectToolPort(
  int port, {
  Duration timeout = kToolConnectTimeout,
}) async {
  try {
    return await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: timeout,
    );
  } on SocketException {
    return Socket.connect(InternetAddress.loopbackIPv6, port, timeout: timeout);
  }
}

/// How the proxy reaches a tool's port ([connectToolPort] by default).
typedef ToolConnect = Future<Socket> Function(int port);

/// V2-4 E9: an [HttpClient] that only reaches what [connect] opens (this
/// computer's loopback, on the port of the URL it is given); it never uses a
/// proxy (`http_proxy` and the like are ignored), never unpacks a body and
/// sends no `User-Agent` of its own. Redirects are turned off per request.
HttpClient toolHttpClient(ToolConnect connect) => HttpClient()
  ..findProxy = ((_) => 'DIRECT')
  ..autoUncompress = false
  ..userAgent = null
  ..connectionFactory = (uri, proxyHost, proxyPort) async =>
      ConnectionTask.fromSocket(connect(uri.port), () {});

/// The URL a request for [tool] goes to: the loopback address and the
/// tool's port, with [target]'s path and query (built, never concatenated:
/// V2-4 E9).
Uri toolUri(ServedTool tool, String target) {
  final q = target.indexOf('?');
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: tool.port,
    path: q < 0 ? target : target.substring(0, q),
    query: q < 0 ? null : target.substring(q + 1),
  );
}

/// V2-4 E9, E2, E3: what the tool gets of a phone's request head.
final class ToolForwardedHead {
  const ToolForwardedHead({
    required this.host,
    required this.headers,
    this.contentLength,
  });

  /// `Host`: the phone's when it names the tool's own port on a loopback
  /// spelling (E2), else the tool's.
  final String host;
  final List<(String, String)> headers;

  /// The body's length when the phone said it.
  final int? contentLength;

  /// Writes it on [request]: no `Accept-Encoding` but the phone's.
  void applyTo(HttpClientRequest request) {
    request.headers
      ..removeAll(HttpHeaders.acceptEncodingHeader)
      ..set(HttpHeaders.hostHeader, host);
    for (final (name, value) in headers) {
      request.headers.add(name, value);
    }
    final length = contentLength;
    if (length != null) request.contentLength = length;
  }

  @override
  String toString() => 'ToolForwardedHead(…)';
}

/// V2-4 E9, E2, E3: a phone's request head as the tool gets it. Hop-by-hop
/// headers, `Forwarded`, `X-Forwarded-*`, `Via` and every `__shellx_` cookie
/// are dropped, cookies go in one `Cookie` (`; `), and in alias mode
/// ([alias]: the port the phone serves the tool on) `Origin` and `Referer`
/// of the phone's origin become the tool's. For a WebSocket ([ws]) the
/// phone's handshake headers are dropped too: the desktop makes its own.
/// A value `dart:io` cannot write is left out.
ToolForwardedHead forwardRequestHead(
  List<String> head,
  ServedTool tool, {
  int? alias,
  bool ws = false,
}) {
  final dropped = toolDroppedNames(head);
  if (ws) {
    dropped.addAll(const [
      'sec-websocket-key',
      'sec-websocket-version',
      'sec-websocket-extensions',
    ]);
  }
  final headers = <(String, String)>[];
  final cookies = <String>[];
  String? host;
  int? contentLength;
  for (var i = 0; i + 1 < head.length; i += 2) {
    final name = head[i].toLowerCase();
    var value = head[i + 1];
    if (dropped.contains(name)) continue;
    switch (name) {
      case 'host':
        host ??= value;
        continue;
      case 'content-length':
        final length = int.tryParse(value);
        if (length != null && length >= 0) contentLength = length;
        continue;
      case 'cookie':
        final kept = stripToolGateCookies(value);
        if (kept != null) cookies.add(kept);
        continue;
      case 'origin' when alias != null:
        if (toolLoopbackPrefix(value, alias) == value) value = tool.origin;
      case 'referer' when alias != null:
        final prefix = toolLoopbackPrefix(value, alias);
        if (prefix != null) {
          value = tool.origin + value.substring(prefix.length);
        }
    }
    if (isWritableHeaderValue(value)) headers.add((name, value));
  }
  if (cookies.isNotEmpty) {
    final cookie = cookies.join('; ');
    if (isWritableHeaderValue(cookie)) headers.add(('cookie', cookie));
  }
  final keep =
      alias == null && host != null && isToolLoopbackAuthority(host, tool.port);
  return ToolForwardedHead(
    host: keep ? host : tool.hostHeader,
    headers: headers,
    contentLength: contentLength,
  );
}

/// `[name, value, …]` of [headers] (lower-case names, one pair per value).
List<String> flatHeaders(HttpHeaders headers) {
  final out = <String>[];
  headers.forEach((name, values) {
    for (final value in values) {
      out
        ..add(name)
        ..add(value);
    }
  });
  return out;
}

/// V2-4 E9, E3, E11: the tool's response head as the phone gets it (from
/// [flatHeaders]). Hop-by-hop headers and a `Set-Cookie` of a `__shellx_`
/// cookie are dropped; in alias mode a `Location` and an
/// `Access-Control-Allow-Origin` that name the tool's origin name the
/// phone's (`http://localhost:<alias>`). Null when what is left is over
/// [kToolMaxHeaders] or [kToolMaxHeadBytes] (the phone answers 502).
List<String>? forwardResponseHead(
  List<String> raw,
  ServedTool tool, {
  int? alias,
}) {
  final dropped = toolDroppedNames(raw);
  final out = <String>[];
  for (var i = 0; i + 1 < raw.length; i += 2) {
    final name = raw[i].toLowerCase();
    var value = raw[i + 1];
    if (dropped.contains(name)) continue;
    if (name == 'set-cookie' && setsToolGateCookie(value)) continue;
    if (alias != null) {
      final prefix = toolLoopbackPrefix(value, tool.port);
      if (name == 'location' && prefix != null) {
        value = 'http://localhost:$alias${value.substring(prefix.length)}';
      } else if (name == 'access-control-allow-origin' && prefix == value) {
        value = 'http://localhost:$alias';
      }
    }
    if (!isWritableHeaderValue(value)) continue;
    out
      ..add(name)
      ..add(value);
  }
  if (out.length > kToolMaxHeaders * 2 ||
      toolHeadBytes(out) > kToolMaxHeadBytes) {
    return null;
  }
  return out;
}
