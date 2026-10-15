/// V2-3 D1, D2, D11, D15: a personal tool — a name and an http(s) URL in a
/// workspace — and the rules its URL follows. Pure Dart: the registry, the
/// dock, the restore file and V2-4's phone list all read it.
library;

/// D2: at most this many tools per workspace.
const int kMaxToolsPerWorkspace = 50;

/// D2: a tool's name, in characters (runes).
const int kMaxToolNameLength = 60;

/// D2: a tool's URL, in characters, after [parseToolUrl] normalised it.
const int kMaxToolUrlLength = 2048;

/// D2: `id` is 10 characters `[a-z0-9]`.
final RegExp kToolIdPattern = RegExp(r'^[a-z0-9]{10}$');

/// Same bound as A2's stored workspace ids (`Workspace.decode`).
const int _maxWorkspaceId = 64;

final RegExp _control = RegExp(r'[\x00-\x1f\x7f]');
final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');

/// `localhost:5173`, `app.local:8080/x`: a host and a port, which also reads
/// as a scheme (`localhost:`), so it is taken as "no scheme".
final RegExp _hostPort = RegExp(r'^[A-Za-z0-9._-]+:\d{1,5}(?:[/?#].*)?$');
final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

/// A registered host name: letters, digits, dots, dashes and underscores
/// (Docker service names); a percent sign means Dart encoded a space or a
/// non-ASCII letter into it.
final RegExp _hostName = RegExp(r'^[a-z0-9._-]+$');

/// Why [parseToolUrl] refused a URL (§4.2 shows a red line for each).
enum ToolUrlError { notHttp, userinfo, backslash, noHost, badPort, tooLong }

/// [parseToolUrl]'s answer: [ToolUrlOk] with the normalised URL, or
/// [ToolUrlBad] with the reason.
sealed class ToolUrlResult {
  const ToolUrlResult();
}

final class ToolUrlOk extends ToolUrlResult {
  const ToolUrlOk(this.url);

  /// http/https, a host, no user information, no fragment, the path and
  /// query kept (the page the tool starts on), "/" for an empty path.
  final String url;

  @override
  String toString() => 'ToolUrlOk(…)';
}

final class ToolUrlBad extends ToolUrlResult {
  const ToolUrlBad(this.error);
  final ToolUrlError error;

  @override
  String toString() => 'ToolUrlBad(${error.name})';
}

/// D1: what the URL field accepts. Leading and trailing spaces go; a
/// missing scheme becomes `http://`; only http and https load (never
/// `javascript:`, `file:`, `data:`); no `user:pass@`; no `\` (a browser
/// reads it as `/`, Dart does not); a host; a port 1–65535; the fragment
/// goes; at most [kMaxToolUrlLength] characters.
ToolUrlResult parseToolUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return const ToolUrlBad(ToolUrlError.noHost);
  if (text.length > kMaxToolUrlLength) {
    return const ToolUrlBad(ToolUrlError.tooLong);
  }
  if (text.contains(r'\')) return const ToolUrlBad(ToolUrlError.backslash);
  if (_control.hasMatch(text)) return const ToolUrlBad(ToolUrlError.noHost);
  final scheme = _scheme.firstMatch(text)?.group(1)?.toLowerCase();
  final String full;
  if (scheme == 'http' || scheme == 'https') {
    full = text;
  } else if (scheme == null || _hostPort.hasMatch(text)) {
    full = 'http://$text';
  } else {
    return const ToolUrlBad(ToolUrlError.notHttp);
  }
  final Uri uri;
  try {
    uri = Uri.parse(full);
  } on Object {
    // FormatException (a bad port), StateError ("http://" with no host).
    return const ToolUrlBad(ToolUrlError.noHost);
  }
  if (uri.userInfo.isNotEmpty) return const ToolUrlBad(ToolUrlError.userinfo);
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return const ToolUrlBad(ToolUrlError.noHost);
  if (!host.contains(':') && !_hostName.hasMatch(host)) {
    return const ToolUrlBad(ToolUrlError.noHost);
  }
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
    return const ToolUrlBad(ToolUrlError.badPort);
  }
  final clean = Uri(
    scheme: uri.scheme.toLowerCase(),
    host: host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.isEmpty ? '/' : uri.path,
    query: uri.hasQuery ? uri.query : null,
  ).toString();
  if (clean.length > kMaxToolUrlLength) {
    return const ToolUrlBad(ToolUrlError.tooLong);
  }
  return ToolUrlOk(clean);
}

/// D11: "On this computer" — `localhost`, `*.localhost`, 127.0.0.0/8, `::1`
/// and `0.0.0.0` (A6 D11's local class). [host] as `Uri.host` gives it
/// (IPv6 without brackets).
bool isLocalToolHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h == '::1' || h == '0.0.0.0') return true;
  final v4 = _ipv4.firstMatch(h);
  if (v4 == null || v4.group(1) != '127') return false;
  return [2, 3, 4].every((i) => int.parse(v4.group(i)!) <= 255);
}

/// D15 / V2-4 E1: the hosts a phone may reach a tool on.
const Set<String> _phoneHosts = {'localhost', '127.0.0.1', '::1'};

/// A user-perceived name cut to [kMaxToolNameLength] runes, trimmed.
String _cleanName(String text) {
  final trimmed = text.replaceAll(_control, ' ').trim();
  final runes = trimmed.runes;
  return runes.length <= kMaxToolNameLength
      ? trimmed
      : String.fromCharCodes(runes.take(kMaxToolNameLength)).trim();
}

/// V2-3 D1/D2: a personal tool — a name and an http(s) URL in a workspace.
final class ToolEntry {
  const ToolEntry({
    required this.id,
    required this.ws,
    required this.name,
    required this.url,
    this.phone = false,
  });

  /// 10 chars `[a-z0-9]`, stable for the tool's life.
  final String id;

  /// The workspace id (`Workspace.id`).
  final String ws;

  /// ≤ 60 chars, never empty.
  final String name;

  /// Normalised by [parseToolUrl]: http/https, a host, no userinfo, no
  /// fragment.
  final String url;

  /// D15: "Allow on phone" (only [phoneOn] counts).
  final bool phone;

  Uri get uri => Uri.parse(url);

  /// `scheme://host:port`, the port always written (`http://[::1]:8080`).
  String get origin {
    final u = uri;
    return '${u.scheme}://${_hostForUrl(u.host)}:${u.port}';
  }

  /// The effective port (80 / 443 when the URL has none).
  int get port => uri.port;

  /// D11 bar and sidebar: `localhost:5173`, `[::1]:8080`.
  String get hostPort => '${_hostForUrl(uri.host)}:$port';

  /// D11: "On this computer".
  bool get isLocal => isLocalToolHost(uri.host);

  /// D11: `http` not on this computer adds "not encrypted".
  bool get unencrypted => uri.scheme == 'http' && !isLocal;

  /// D15: http, and the host is `localhost`, `127.0.0.1` or `::1`.
  bool get phoneAllowed =>
      uri.scheme == 'http' && _phoneHosts.contains(uri.host.toLowerCase());

  bool get phoneOn => phone && phoneAllowed;

  ToolEntry copyWith({String? name, String? url, bool? phone}) => ToolEntry(
    id: id,
    ws: ws,
    name: name ?? this.name,
    url: url ?? this.url,
    phone: phone ?? this.phone,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ws': ws,
    'name': name,
    'url': url,
    'phone': phone,
  };

  /// Never throws; null for an entry that is not a tool (bad id, workspace
  /// or URL). A damaged name or flag is repaired: an empty name becomes
  /// `host:port`, a long one is cut, a flag that is not `true` is off.
  static ToolEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final ws = json['ws'];
    final url = json['url'];
    if (id is! String || !kToolIdPattern.hasMatch(id)) return null;
    if (ws is! String || ws.isEmpty || ws.length > _maxWorkspaceId) {
      return null;
    }
    if (url is! String) return null;
    final parsed = parseToolUrl(url);
    if (parsed is! ToolUrlOk) return null;
    final rawName = json['name'];
    final draft = ToolEntry(id: id, ws: ws, name: '', url: parsed.url);
    final name = rawName is String ? _cleanName(rawName) : '';
    return ToolEntry(
      id: id,
      ws: ws,
      name: name.isEmpty ? draft.hostPort : name,
      url: parsed.url,
      phone: json['phone'] == true,
    );
  }

  /// D24: never the name or the URL.
  @override
  String toString() => 'ToolEntry(…)';
}

/// The name a tool gets: [name] cleaned, or `host:port` of [url] when it is
/// blank (D1). [url] is already normalised.
String toolNameFor(String name, String url) {
  final clean = _cleanName(name);
  if (clean.isNotEmpty) return clean;
  return ToolEntry(id: '', ws: '', name: '', url: url).hostPort;
}

String _hostForUrl(String host) => host.contains(':') ? '[$host]' : host;
