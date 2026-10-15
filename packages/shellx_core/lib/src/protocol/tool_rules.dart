import 'messages.dart';

/// V2-4 E10: at most this many HTTP streams per phone at once.
const int kToolMaxHttpStreams = 32;

/// V2-4 E10: at most this many WebSocket streams per phone at once.
const int kToolMaxWsStreams = 16;

/// V2-4 E10: the largest request body (413 above it).
const int kToolMaxRequestBodyBytes = 64 * 1024 * 1024;

/// V2-4 E10: the largest WebSocket message (close 1009 above it).
const int kToolMaxWsMessageBytes = 16 * 1024 * 1024;

/// V2-4 E11: the reserved path prefix of the phone's server; never sent on.
const String kToolReservedPrefix = '/__shellx/';

/// V2-4 E11: every gate cookie's name starts with this (`__shellx_<port>`).
const String kToolGateCookiePrefix = '__shellx_';

/// The gate cookie of the phone server on [port] (V2-4 E11).
String toolGateCookieName(int port) => '$kToolGateCookiePrefix$port';

/// RFC 9110 `tchar`: what a method or a header name is made of.
bool isToolToken(String s) {
  if (s.isEmpty) return false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final ok =
        (c >= 0x30 && c <= 0x39) || // 0-9
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        '!#\$%&\'*+-.^_`|~'.codeUnits.contains(c);
    if (!ok) return false;
  }
  return true;
}

/// V2-4 E9: a header value carries no CR, LF or NUL.
bool isToolHeaderValue(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x0D || c == 0x0A || c == 0x00) return false;
  }
  return true;
}

/// What `dart:io` can write as a header value: visible ASCII, space and tab.
/// A value with any other byte (obs-text above 0x7E) is dropped when written,
/// never sent half (`HttpHeaders.add` throws on it).
bool isWritableHeaderValue(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (!((c >= 0x20 && c <= 0x7E) || c == 0x09)) return false;
  }
  return true;
}

/// V2-4 E9: a method is a token of at most 16 characters, and never one that
/// would turn the tool's server into a tunnel or reflect the request.
bool isToolMethod(String method) =>
    method.length <= kToolMaxMethodLength &&
    isToolToken(method) &&
    !const {'CONNECT', 'TRACE', 'TRACK'}.contains(method.toUpperCase());

/// V2-4 E9: origin form only (`/path?query`): starts with one `/` (never
/// `//`, an authority), at most [kToolMaxTargetBytes], and no CR, LF, NUL
/// (nor any other control character), space, `#`, backslash or DEL.
bool isToolTarget(String target) {
  if (!target.startsWith('/') || target.startsWith('//')) return false;
  if (toolHeadBytes([target]) > kToolMaxTargetBytes) return false;
  for (var i = 0; i < target.length; i++) {
    final c = target.codeUnitAt(i);
    if (c <= 0x20 || c == 0x23 || c == 0x5C || c == 0x7F) return false;
  }
  return true;
}

/// V2-4 E9: a `head` is pairs of a token name and a value without CR, LF or
/// NUL; at most [kToolMaxHeaders] pairs and [kToolMaxHeadBytes] bytes.
bool isToolHead(List<String> head) {
  if (head.length.isOdd || head.length > kToolMaxHeaders * 2) return false;
  if (toolHeadBytes(head) > kToolMaxHeadBytes) return false;
  for (var i = 0; i < head.length; i += 2) {
    if (!isToolToken(head[i]) || !isToolHeaderValue(head[i + 1])) return false;
  }
  return true;
}

/// Hop-by-hop headers (RFC 9110 §7.6.1) and the ones a proxy must not pass
/// on (V2-4 E9), lower case. `connection` also names more, see
/// [toolDroppedNames].
const Set<String> kToolHopByHop = {
  'connection',
  'keep-alive',
  'proxy-connection',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'forwarded',
  'via',
  'expect',
};

/// The lower-case names of [head] that are never passed on: [kToolHopByHop],
/// `x-forwarded-*`, and every name its `connection` headers list.
Set<String> toolDroppedNames(List<String> head) {
  final dropped = {...kToolHopByHop};
  for (var i = 0; i < head.length; i += 2) {
    final name = head[i].toLowerCase();
    if (name.startsWith('x-forwarded-')) dropped.add(name);
    if (name == 'connection') {
      for (final token in head[i + 1].split(',')) {
        final listed = token.trim().toLowerCase();
        if (listed.isNotEmpty) dropped.add(listed);
      }
    }
  }
  return dropped;
}

/// The values of header [name] (lower case) in [head], in order.
List<String> toolHeadValues(List<String> head, String name) => [
  for (var i = 0; i < head.length; i += 2)
    if (head[i].toLowerCase() == name) head[i + 1],
];

/// A `Cookie` value without any `__shellx_*` pair (V2-4 E11); null when no
/// pair is left.
String? stripToolGateCookies(String cookie) {
  final kept = [
    for (final pair in cookie.split(';'))
      if (pair.trim().isNotEmpty &&
          !pair.trim().startsWith(kToolGateCookiePrefix))
        pair.trim(),
  ];
  return kept.isEmpty ? null : kept.join('; ');
}

/// Whether a `Set-Cookie` value sets a `__shellx_*` cookie (dropped, V2-4
/// E11: a tool must not overwrite the phone's gate).
bool setsToolGateCookie(String setCookie) =>
    setCookie.trimLeft().startsWith(kToolGateCookiePrefix);

/// [authority] (a `Host` value) is `localhost`, `127.0.0.1` or `[::1]` with
/// [port] (written, or 80 left out).
bool isToolLoopbackAuthority(String authority, int port) {
  final a = authority.toLowerCase();
  for (final host in const ['localhost', '127.0.0.1', '[::1]']) {
    if (a == '$host:$port' || (port == 80 && a == host)) return true;
  }
  return false;
}

/// `http://host[:port]` at the start of [url] when host is a loopback
/// spelling and the port is [port] (V2-4 E3: the origin the desktop and the
/// phone rewrite); null otherwise.
String? toolLoopbackPrefix(String url, int port) {
  if (!url.toLowerCase().startsWith('http://')) return null;
  final rest = url.substring(7);
  final end = rest.indexOf(RegExp('[/?#]'));
  final authority = end < 0 ? rest : rest.substring(0, end);
  return isToolLoopbackAuthority(authority, port)
      ? url.substring(0, 7 + authority.length)
      : null;
}
