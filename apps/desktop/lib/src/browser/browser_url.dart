/// A6 D9–D11, D29: what the address field accepts, how an origin is
/// classified, and what of a URL survives into the restore file.
library;

/// D11. `none` is `about:blank` (and anything that is not http/https).
enum BrowserOrigin { local, secure, insecure, none }

/// The only page that is not http/https a browser pane may show.
final Uri aboutBlank = Uri.parse('about:blank');

const int kMaxAddressLength = 2048;

final RegExp _digits = RegExp(r'^\d{1,5}$');
final RegExp _whitespace = RegExp(r'\s');
final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
final RegExp _hostPort = RegExp(r'^[A-Za-z0-9.-]+:\d{1,5}(?:[/?#].*)?$');
final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// D9: the address field's text → the URL to load, or `null` for "Không
/// phải địa chỉ web". Never a search: text that is not an address is
/// refused, so nothing typed ever reaches a search engine.
Uri? parseAddressInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.length > kMaxAddressLength) return null;
  if (text.toLowerCase() == 'about:blank') return aboutBlank;
  if (_digits.hasMatch(text)) {
    final port = int.parse(text);
    if (port < 1 || port > 65535) return null;
    return Uri.parse('http://localhost:$port/');
  }
  if (_whitespace.hasMatch(text)) return null;
  final scheme = _scheme.firstMatch(text)?.group(1)?.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return _web(text);
  // "localhost:3000" also looks like a scheme; anything else with a
  // scheme (javascript:, file:, data:, mailto:) is refused.
  if (scheme != null && !_hostPort.hasMatch(text)) return null;
  final guess = _web('http://$text');
  if (guess == null) return null;
  final host = guess.host;
  if (isLocalHost(host) || _isIpLiteral(host)) return guess;
  if (!host.contains('.')) return null;
  return guess.replace(scheme: 'https');
}

Uri? _web(String text) {
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (uri.host.isEmpty) return null;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
  return uri.path.isEmpty ? uri.replace(path: '/') : uri;
}

bool _isIpLiteral(String host) => _ipv4.hasMatch(host) || host.contains(':');

/// D11: loopback and `*.localhost` (RFC 6761: never resolved outside).
bool isLocalHost(String rawHost) {
  final host = rawHost.toLowerCase();
  if (host == 'localhost' || host.endsWith('.localhost')) return true;
  if (host == '::1' || host == '[::1]' || host == '0.0.0.0') return true;
  final v4 = _ipv4.firstMatch(host);
  return v4 != null && v4.group(1) == '127';
}

BrowserOrigin classifyOrigin(Uri? uri) {
  if (uri == null) return BrowserOrigin.none;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return BrowserOrigin.none;
  if (isLocalHost(uri.host)) return BrowserOrigin.local;
  return scheme == 'https' ? BrowserOrigin.secure : BrowserOrigin.insecure;
}

/// D10: the only top-level pages a browser pane may show.
bool isNavigable(Uri uri) {
  if (uri == aboutBlank) return true;
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') && uri.host.isNotEmpty;
}

/// D29: what the restore file keeps — http/https only, no credentials, no
/// fragment, ≤ 2048 characters; anything else restores as `about:blank`.
String? urlForRestore(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  final clean = uri.replace(userInfo: '').removeFragment();
  final text = clean.toString();
  return text.length > kMaxAddressLength ? null : text;
}

/// UI-A6 §2.1: the unfocused address — no scheme for local and secure
/// pages (the origin mark says it), `http://` kept for insecure ones;
/// percent-escapes decoded for reading.
String displayAddress(Uri uri) {
  if (uri == aboutBlank) return '';
  final text = Uri.decodeFull(uri.toString());
  return switch (classifyOrigin(uri)) {
    BrowserOrigin.local || BrowserOrigin.secure => text.replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    ),
    _ => text,
  };
}
