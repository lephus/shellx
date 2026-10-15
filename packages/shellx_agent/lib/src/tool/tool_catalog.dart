import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// V2-4 E5: the largest `tool.serve` body (one mux frame holds 64 KiB).
const int kToolServeMaxBytes = 60 * 1024;

/// At most this many ids of tools with the phone flag off in a `tool.serve`
/// (one past it ends a stream `gone` rather than `disabled`).
const int kToolServeMaxOff = 1000;

/// V2-4 E1, E5: one tool the window lets phones open, as `tool.serve` carries
/// it: `{"id", "name", "ws", "group", "url"}`. Only `http` on `localhost`,
/// `127.0.0.1` or `[::1]` with a port 1–65535, no user info, no fragment
/// (V2-3 D15 `phoneAllowed`); the background service checks again what the
/// window sends.
final class ServedTool {
  const ServedTool._({
    required this.id,
    required this.name,
    required this.ws,
    required this.group,
    required this.url,
    required this.host,
    required this.port,
    required this.path,
  });

  /// V2-3 D2: 10 characters `[a-z0-9]`; any 1–64 of `[A-Za-z0-9_-]` here.
  final String id;
  final String name;

  /// The workspace's name, for the phone's row ("shop-web · localhost:5173").
  final String ws;

  /// The workspace's key: tools of one group are served together (E4).
  final String group;
  final String url;

  /// `localhost`, `127.0.0.1` or `::1`.
  final String host;
  final int port;

  /// The start page: path and query, `/` at least.
  final String path;

  /// What the tool sees in `Host` when the request does not name it itself.
  String get hostHeader => host == '::1' ? '[::1]:$port' : '$host:$port';

  /// `http://host:port`, the port always written.
  String get origin => 'http://$hostHeader';

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Null for an entry this version does not take (never throws).
  static ServedTool? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final ws = json['ws'];
    final group = json['group'];
    final url = json['url'];
    if (id is! String || !_id.hasMatch(id)) return null;
    if (name is! String || name.isEmpty || name.length > 200) return null;
    if (ws is! String || ws.length > 200) return null;
    if (group is! String || group.length > 200) return null;
    if (url is! String || url.length > 2048) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !const {'localhost', '127.0.0.1', '::1'}.contains(uri.host) ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    final path =
        (uri.path.isEmpty ? '/' : uri.path) +
        (uri.hasQuery ? '?${uri.query}' : '');
    if (!isToolTarget(path)) return null;
    return ServedTool._(
      id: id,
      name: name,
      ws: ws,
      group: group,
      url: url,
      host: uri.host,
      port: uri.port,
      path: path,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'ws': ws,
    'group': group,
    'url': url,
  };

  @override
  String toString() => 'ServedTool(…)';
}

/// V2-4 E5: the tools a phone may open now, and the ids of those that exist
/// with the phone flag off ([off]: a stream of one of them ends `disabled`,
/// of any other unknown id `gone`).
final class ToolCatalog {
  ToolCatalog(List<ServedTool> tools, {Set<String> off = const {}})
    : tools = List.unmodifiable(tools),
      off = Set.unmodifiable(off),
      _byId = {for (final tool in tools) tool.id: tool};

  final List<ServedTool> tools;
  final Set<String> off;
  final Map<String, ServedTool> _byId;

  /// `tool.serve`'s `b`: `{"v": 1, "tools": [...], "off": [...]}`. Entries
  /// this version does not take are left out; null when [body] is not such
  /// an object (never throws).
  static ToolCatalog? fromServeBody(Uint8List body) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException {
      return null;
    }
    if (json is! Map || json['v'] != 1 || json['tools'] is! List) return null;
    final tools = <ServedTool>[];
    final seen = <String>{};
    for (final entry in json['tools'] as List) {
      final tool = ServedTool.fromJson(entry);
      if (tool != null && seen.add(tool.id)) tools.add(tool);
    }
    final off = json['off'];
    return ToolCatalog(
      tools,
      off: {
        if (off is List)
          for (final id in off)
            if (id is String && !seen.contains(id)) id,
      },
    );
  }

  /// What the window sends (`tool.serve`'s `b`, or the in-process proxy's
  /// list): the same bytes either way. At most [kToolServeMaxBytes] (a mux
  /// frame is 64 KiB): the tools past that are left out, in order.
  static Uint8List serveBody(
    List<Map<String, Object?>> tools, {
    Iterable<String> off = const [],
  }) {
    final offIds = off.take(kToolServeMaxOff).toList();
    final kept = <Map<String, Object?>>[];
    var size = utf8
        .encode(jsonEncode({'v': 1, 'tools': [], 'off': offIds}))
        .length;
    for (final tool in tools) {
      final length = utf8.encode(jsonEncode(tool)).length + 1;
      if (size + length > kToolServeMaxBytes) break;
      size += length;
      kept.add(tool);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': kept, 'off': offIds})),
    );
  }

  ServedTool? byId(String id) => _byId[id];

  /// Why a stream of [id], not in [tools], ends.
  String endCodeFor(String id) =>
      off.contains(id) ? ToolCode.disabled : ToolCode.gone;

  /// V2-4 §4.2: `{"v": 1, "tools": [{"id", "name", "ws", "port", "path",
  /// "group"}]}`, at most [kToolMaxChunkBytes]: the tools past that are left
  /// out (in the window's order).
  Uint8List listingBody() {
    final entries = <Map<String, Object?>>[];
    var size = 20;
    for (final tool in tools) {
      final entry = {
        'id': tool.id,
        'name': tool.name,
        'ws': tool.ws,
        'port': tool.port,
        'path': tool.path,
        'group': tool.group,
      };
      final length = utf8.encode(jsonEncode(entry)).length + 1;
      if (size + length > kToolMaxChunkBytes) break;
      size += length;
      entries.add(entry);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': entries})),
    );
  }

  /// V2-4 E4: what a phone serves when it opens [tool]: [tool] first, then
  /// the other tools of its workspace, one per port, at most
  /// [kToolMaxChunkBytes] in all (the main tool always fits: its path is at
  /// most 8 KiB).
  Uint8List openedBody(ServedTool tool) {
    final ports = <int>{tool.port};
    final served = [
      {'id': tool.id, 'port': tool.port, 'path': tool.path},
    ];
    var size = utf8.encode(jsonEncode(served.first)).length + 20;
    for (final other in tools) {
      if (other.group != tool.group || ports.contains(other.port)) continue;
      final entry = {'id': other.id, 'port': other.port, 'path': other.path};
      final length = utf8.encode(jsonEncode(entry)).length + 1;
      if (size + length > kToolMaxChunkBytes) break;
      size += length;
      ports.add(other.port);
      served.add(entry);
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'v': 1, 'tools': served})),
    );
  }

  @override
  String toString() => 'ToolCatalog(…)';
}
