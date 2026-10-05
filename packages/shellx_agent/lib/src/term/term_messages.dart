import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Local-link protocol version (spec §6.3).
const int kTermProtocolVersion = 1;

/// Encodes with keys in bytewise ascending order (spec §6.2): every key is
/// ASCII, so `String.compareTo` order is byte order.
Uint8List _encode(Map<String, Object?> fields) {
  final keys = fields.keys.toList()..sort();
  return encodeCbor({for (final key in keys) key: fields[key]});
}

(Map<Object?, Object?>, String) _parse(Uint8List payload) {
  final value = decodeCbor(payload);
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('local-link message must be a CBOR map');
  }
  final t = value['t'];
  if (t is! String) throw const FormatException('local-link message without "t"');
  return (value, t);
}

final class _Fields {
  _Fields(this._map, this._t);
  final Map<Object?, Object?> _map;
  final String _t;

  FormatException _bad(String key) =>
      FormatException('$_t: "$key" missing or wrong type');

  int uint(String key) {
    final value = _map[key];
    if (value is int && value >= 0) return value;
    throw _bad(key);
  }

  int u32(String key) {
    final value = uint(key);
    if (value > 0xffffffff) throw _bad(key);
    return value;
  }

  int dim(String key) {
    final value = uint(key);
    if (value < 1 || value > 0xffff) throw _bad(key);
    return value;
  }

  Uint8List bytes(String key, [int? length]) {
    final value = _map[key];
    if (value is Uint8List && (length == null || value.length == length)) {
      return value;
    }
    throw _bad(key);
  }

  String text(String key) {
    final value = _map[key];
    if (value is String) return value;
    throw _bad(key);
  }

  bool boolean(String key) {
    final value = _map[key];
    if (value is bool) return value;
    throw _bad(key);
  }
}

/// What `shellx-term` reported about its window in `auth` (spec §6.3).
final class TermInfo {
  const TermInfo({
    required this.termId,
    required this.app,
    required this.shell,
    required this.pid,
    required this.cols,
    required this.rows,
    required this.startedAt,
  });

  /// 16 random bytes per window, kept across reconnects.
  final Uint8List termId;
  final String app;
  final String shell;

  /// The inner shell's pid.
  final int pid;
  final int cols;
  final int rows;

  /// Unix milliseconds when `shellx-term` started.
  final int startedAt;

  /// [termId] as hex: the key a reconnecting window is found by.
  String get key => bytesToHex(termId);

  @override
  String toString() => 'TermInfo(app: $app, shell: $shell, pid: $pid, '
      '${cols}x$rows)';
}

/// `shellx-term` → agent (spec §6.3, §6.4).
sealed class TermToAgent {
  const TermToAgent();
  Map<String, Object?> _fields();
  Uint8List encode() => _encode(_fields());

  /// Null for an unknown `t`. Throws [FormatException] when malformed.
  static TermToAgent? decode(Uint8List payload) {
    final (map, t) = _parse(payload);
    final f = _Fields(map, t);
    return switch (t) {
      'hello' => TermHello(v: f.uint('v'), nonce: f.bytes('nonce', 32)),
      'auth' => TermAuth(
        mac: f.bytes('mac', 32),
        info: TermInfo(
          termId: f.bytes('term_id', 16),
          app: f.text('app'),
          shell: f.text('shell'),
          pid: f.u32('pid'),
          cols: f.dim('cols'),
          rows: f.dim('rows'),
          startedAt: f.uint('started_at'),
        ),
      ),
      'snapshot' => TermSnapshot(
        data: f.bytes('data'),
        last: f.boolean('last'),
      ),
      'out' => TermOut(data: f.bytes('data')),
      'size' => TermSize(cols: f.dim('cols'), rows: f.dim('rows')),
      'local' => const TermLocal(),
      'exit' => TermExit(code: f.u32('code')),
      _ => null,
    };
  }

  @override
  String toString() => '$runtimeType';
}

final class TermHello extends TermToAgent {
  const TermHello({required this.v, required this.nonce});
  final int v;
  final Uint8List nonce;
  @override
  Map<String, Object?> _fields() => {'t': 'hello', 'v': v, 'nonce': nonce};
}

final class TermAuth extends TermToAgent {
  const TermAuth({required this.mac, required this.info});
  final Uint8List mac;
  final TermInfo info;
  @override
  Map<String, Object?> _fields() => {
    't': 'auth',
    'mac': mac,
    'term_id': info.termId,
    'app': info.app,
    'shell': info.shell,
    'pid': info.pid,
    'cols': info.cols,
    'rows': info.rows,
    'started_at': info.startedAt,
  };
}

final class TermSnapshot extends TermToAgent {
  const TermSnapshot({required this.data, required this.last});
  final Uint8List data;
  final bool last;
  @override
  Map<String, Object?> _fields() => {
    't': 'snapshot',
    'data': data,
    'last': last,
  };
}

final class TermOut extends TermToAgent {
  const TermOut({required this.data});
  final Uint8List data;
  @override
  Map<String, Object?> _fields() => {'t': 'out', 'data': data};
}

final class TermSize extends TermToAgent {
  const TermSize({required this.cols, required this.rows});
  final int cols, rows;
  @override
  Map<String, Object?> _fields() => {'t': 'size', 'cols': cols, 'rows': rows};
}

final class TermLocal extends TermToAgent {
  const TermLocal();
  @override
  Map<String, Object?> _fields() => {'t': 'local'};
}

final class TermExit extends TermToAgent {
  const TermExit({required this.code});
  final int code;
  @override
  Map<String, Object?> _fields() => {'t': 'exit', 'code': code};
}

/// Agent → `shellx-term` (spec §6.3, §6.4).
sealed class AgentToTerm {
  const AgentToTerm();
  Map<String, Object?> _fields();
  Uint8List encode() => _encode(_fields());

  /// Null for an unknown `t`. Throws [FormatException] when malformed.
  static AgentToTerm? decode(Uint8List payload) {
    final (map, t) = _parse(payload);
    final f = _Fields(map, t);
    return switch (t) {
      'challenge' => AgentChallenge(
        nonce: f.bytes('nonce', 32),
        mac: f.bytes('mac', 32),
      ),
      'ready' => const AgentReady(),
      'reject' => AgentReject(reason: f.text('reason')),
      'in' => AgentIn(data: f.bytes('data')),
      'resize' => AgentResize(cols: f.dim('cols'), rows: f.dim('rows')),
      'local_size' => const AgentLocalSize(),
      _ => null,
    };
  }

  @override
  String toString() => '$runtimeType';
}

final class AgentChallenge extends AgentToTerm {
  const AgentChallenge({required this.nonce, required this.mac});
  final Uint8List nonce;
  final Uint8List mac;
  @override
  Map<String, Object?> _fields() => {
    't': 'challenge',
    'nonce': nonce,
    'mac': mac,
  };
}

final class AgentReady extends AgentToTerm {
  const AgentReady();
  @override
  Map<String, Object?> _fields() => {'t': 'ready'};
}

final class AgentReject extends AgentToTerm {
  const AgentReject({required this.reason});
  static const limit = 'limit';
  static const version = 'version';
  final String reason;
  @override
  Map<String, Object?> _fields() => {'t': 'reject', 'reason': reason};
  @override
  String toString() => 'AgentReject($reason)';
}

final class AgentIn extends AgentToTerm {
  const AgentIn({required this.data});
  final Uint8List data;
  @override
  Map<String, Object?> _fields() => {'t': 'in', 'data': data};
}

final class AgentResize extends AgentToTerm {
  const AgentResize({required this.cols, required this.rows});
  final int cols, rows;
  @override
  Map<String, Object?> _fields() => {
    't': 'resize',
    'cols': cols,
    'rows': rows,
  };
  @override
  String toString() => 'AgentResize(${cols}x$rows)';
}

final class AgentLocalSize extends AgentToTerm {
  const AgentLocalSize();
  @override
  Map<String, Object?> _fields() => {'t': 'local_size'};
}
