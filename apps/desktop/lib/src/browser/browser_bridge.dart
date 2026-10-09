/// A6 D19, D21–D23: the page → ShellX bridge. Everything that arrives here
/// was written by the page (or anything running in it): it is data, never
/// a command — it only fills the console/network buffers, updates the
/// title, or settles an eval that is waiting for its own nonce.
library;

import 'dart:convert';

/// D21: one bridge message, JSON. Bigger ones are dropped unread. Sized so
/// an eval result of [kEvalResultMax] bytes plus its envelope fits.
const int kBridgeMessageMax = 64 * 1024;

/// D22: console text kept per entry; D19: eval error message.
const int kConsoleTextMax = 2048;

/// D23: URL kept per network entry.
const int kNetworkUrlMax = 2048;

/// D19: an eval result must fit one A5b frame (64 KiB) with room to spare.
const int kEvalResultMax = 48 * 1024;

/// D19: an eval body (A7 `ui.browser.eval.script`).
const int kEvalScriptMax = 32 * 1024;

/// How a page reaches ShellX: macOS WKScriptMessageHandler, Windows
/// WebView2 `chrome.webview.postMessage`.
enum BridgeTransport {
  webkit('window.webkit.messageHandlers.ShellxBrowser'),
  webview2('window.chrome.webview');

  const BridgeTransport(this.target);

  /// The object whose `postMessage` sends a string. Scripts capture it and
  /// its method once at injection, before the page can replace them.
  final String target;
}

sealed class BridgeMessage {
  const BridgeMessage();
}

final class ConsoleMessage extends BridgeMessage {
  const ConsoleMessage({
    required this.level,
    required this.text,
    required this.url,
  });
  final String level;
  final String text;
  final String url;
}

final class NetworkMessage extends BridgeMessage {
  const NetworkMessage({
    required this.url,
    required this.type,
    this.method,
    this.status,
    this.durationMs,
    this.size,
  });
  final String url;
  final String type;
  final String? method;
  final int? status;
  final int? durationMs;
  final int? size;
}

final class TitleMessage extends BridgeMessage {
  const TitleMessage(this.title);
  final String title;
}

final class EvalResultMessage extends BridgeMessage {
  const EvalResultMessage.ok(this.nonce, String this.json)
    : code = null,
      message = null;
  const EvalResultMessage.failed(this.nonce, String this.code, this.message)
    : json = null;
  final String nonce;
  final String? json;
  final String? code;
  final String? message;
  bool get ok => code == null;
}

const Set<String> _levels = {'log', 'info', 'warn', 'error', 'debug'};
const Set<String> _evalCodes = {
  'forbidden_origin',
  'eval_error',
  'not_serializable',
  'result_too_large',
};

String _cut(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

int? _int(Object? v) => v is num && v.isFinite && v >= 0 ? v.round() : null;

/// Parses one message; `null` for anything malformed, oversized or unknown
/// (dropped silently — a page can send anything).
BridgeMessage? parseBridgeMessage(String raw) {
  if (raw.length > kBridgeMessageMax) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  switch (decoded['t']) {
    case 'console':
      final level = decoded['level'];
      final text = decoded['text'];
      if (level is! String || !_levels.contains(level) || text is! String) {
        return null;
      }
      final url = decoded['url'];
      return ConsoleMessage(
        level: level,
        text: _cut(text, kConsoleTextMax),
        url: url is String ? _cut(url, kNetworkUrlMax) : '',
      );
    case 'net':
      final url = decoded['url'];
      final type = decoded['type'];
      if (url is! String || url.isEmpty || type is! String) return null;
      final method = decoded['method'];
      return NetworkMessage(
        url: _cut(url, kNetworkUrlMax),
        type: _cut(type, 32),
        method: method is String ? _cut(method.toUpperCase(), 16) : null,
        status: _int(decoded['status']),
        durationMs: _int(decoded['dur']),
        size: _int(decoded['size']),
      );
    case 'title':
      final title = decoded['title'];
      return title is String ? TitleMessage(_cut(title, 1024)) : null;
    case 'eval':
      final nonce = decoded['n'];
      if (nonce is! String || nonce.isEmpty) return null;
      if (decoded['ok'] == true) {
        final json = decoded['json'];
        if (json is! String) return null;
        if (utf8.encode(json).length > kEvalResultMax) {
          return EvalResultMessage.failed(nonce, 'result_too_large', null);
        }
        return EvalResultMessage.ok(nonce, json);
      }
      final code = decoded['code'];
      if (code is! String || !_evalCodes.contains(code)) return null;
      final message = decoded['message'];
      return EvalResultMessage.failed(
        nonce,
        code,
        message is String ? _cut(message, kConsoleTextMax) : null,
      );
  }
  return null;
}

/// D19, D20: the script text the engine runs for one `evalJs`. The body
/// runs as an async function body; the page's origin is checked again
/// inside the page (it may have navigated since Dart checked); the result
/// goes back through the bridge tagged with [nonce]. No `eval()` or
/// `new Function`, so the page's CSP does not apply. `JSON.stringify` and
/// the transport's `postMessage` are captured on the first lines, so a
/// page that patches them later cannot read or forge the result (S8).
///
/// A [body] that does not parse makes the whole script a syntax error:
/// the engine's `runScript` rejects and [BrowserController.evalJs] fails
/// fast with `eval_error` (S10) instead of waiting for the timeout.
String buildEvalScript({
  required String nonce,
  required String body,
  required bool allowAnyOrigin,
  required BridgeTransport transport,
}) {
  final n = jsonEncode(nonce);
  return '''
(function () {
  var stringify = JSON.stringify;
  var target = ${transport.target};
  var send = target.postMessage;
  var post = function (m) {
    try { send.call(target, stringify(m)); } catch (e) {}
  };
  var n = $n;
  var h = location.hostname, p = location.protocol;
  var allowed = $allowAnyOrigin || location.href === 'about:blank' ||
    ((p === 'http:' || p === 'https:') &&
     (h === 'localhost' || h === '[::1]' || h === '::1' || /^127\\.\\d+\\.\\d+\\.\\d+\$/.test(h)));
  if (!allowed) { post({t: 'eval', n: n, ok: false, code: 'forbidden_origin'}); return; }
  var fail = function (code, e) {
    post({t: 'eval', n: n, ok: false, code: code,
          message: String(e && e.message || e).slice(0, $kConsoleTextMax)});
  };
  (async function () {
$body
  })().then(function (v) {
    var s;
    try { s = stringify(v === undefined ? null : v); }
    catch (e) { fail('not_serializable', e); return; }
    if (s === undefined) s = 'null';
    if (s.length > $kEvalResultMax) { post({t: 'eval', n: n, ok: false, code: 'result_too_large'}); return; }
    post({t: 'eval', n: n, ok: true, json: s});
  }, function (e) { fail('eval_error', e); });
})();
''';
}
