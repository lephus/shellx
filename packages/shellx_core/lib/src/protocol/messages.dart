// Application messages carried inside TRANSPORT payloads (spec section 6.4).
// Each message is a CBOR map with key "t"; other keys are snake_case.
import 'dart:typed_data';

import '../util/cbor_values.dart';

sealed class AppMessage {
  const AppMessage();

  /// Value of the "t" key.
  String get type;

  Map<String, Object?> toMap();

  /// Returns null when "t" is a string this version does not know.
  /// Throws [FormatException] when "t" or a required field is missing or has
  /// the wrong type, or when an enum field has an unknown value.
  static AppMessage? fromMap(Map<Object?, Object?> map) {
    final t = map['t'];
    if (t is! String) {
      throw const FormatException('Message without a string "t"');
    }
    final f = _Fields(map, t);
    return switch (t) {
      'pair.confirm' => const PairConfirm(),
      'session.list' => SessionList(
        desktop: f.optionalBoolean('desktop') ?? false,
      ),
      'session.list.result' => SessionListResult(
        [
          for (final item in f.list('sessions'))
            // ignore: use_null_aware_elements
            if (SessionInfo._fromMap(item, t) case final info?) info,
        ],
        desktopSharing: f.optionalBoolean('desktop_sharing'),
      ),
      'session.open' => SessionOpen(
        cols: f.integer('cols'),
        rows: f.integer('rows'),
      ),
      'session.opened' => SessionOpened(
        id: f.integer('id'),
        index: f.integer('index'),
        shell: f.string('shell'),
      ),
      'session.attach' => SessionAttach(
        id: f.integer('id'),
        cols: f.integer('cols'),
        rows: f.integer('rows'),
        lastSeq: f.integer('last_seq'),
      ),
      'session.attached' => SessionAttached(id: f.integer('id')),
      'session.reset' => SessionReset(id: f.integer('id')),
      'output' => OutputMessage(
        id: f.integer('id'),
        seq: f.integer('seq'),
        data: f.bytes('data'),
      ),
      'ack' => AckMessage(id: f.integer('id'), seq: f.integer('seq')),
      'input' => InputMessage(id: f.integer('id'), data: f.bytes('data')),
      'resize' => ResizeMessage(
        id: f.integer('id'),
        cols: f.integer('cols'),
        rows: f.integer('rows'),
      ),
      'session.close' => SessionClose(id: f.integer('id')),
      'session.detach' => SessionDetach(id: f.integer('id')),
      'session.driver' => SessionDriver(
        id: f.integer('id'),
        by: DriverSide.fromWire(f.string('by')),
      ),
      'session.exited' => SessionExited(
        id: f.integer('id'),
        exitCode: f.integer('exit_code'),
      ),
      'session.detached' => SessionDetached(
        id: f.integer('id'),
        reason: DetachReason.fromWire(f.string('reason')),
      ),
      'error' => ErrorMessage(
        code: AppErrorCode.fromWire(f.string('code')),
        message: f.string('message'),
        id: f.optionalInteger('id'),
      ),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AppMessage &&
      other.runtimeType == runtimeType &&
      _deepEquals(toMap(), other.toMap());

  @override
  int get hashCode => _deepHash(toMap());

  /// Never prints terminal bytes: byte strings are shown as their length.
  @override
  String toString() => '$runtimeType${_describe(toMap())}';
}

final class PairConfirm extends AppMessage {
  const PairConfirm();
  @override
  String get type => 'pair.confirm';
  @override
  Map<String, Object?> toMap() => {'t': type};
}

final class SessionList extends AppMessage {
  const SessionList({this.desktop = false});

  /// Also list desktop terminals and report `desktop_sharing` (spec §8).
  /// Only written when true, so the old wire form is unchanged.
  final bool desktop;
  @override
  String get type => 'session.list';
  @override
  Map<String, Object?> toMap() => {'t': type, if (desktop) 'desktop': true};
}

/// Where a session's terminal lives (spec §7.1). Absent on the wire means
/// [shellx].
enum SessionKind { shellx, desktop }

final class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attached,
    this.kind = SessionKind.shellx,
    this.app = '',
    this.title = '',
  });

  final int id;
  final int index;
  final String shell;

  /// Unix milliseconds.
  final int createdAt;
  final bool attached;
  final SessionKind kind;

  /// Terminal application (desktop sessions only; may be empty).
  final String app;

  /// Latest window title (desktop sessions only; may be empty).
  final String title;

  Map<String, Object?> toMap() => {
    'id': id,
    'index': index,
    'shell': shell,
    'created_at': createdAt,
    'attached': attached,
    if (kind == SessionKind.desktop) ...{
      'kind': 'desktop',
      'app': app,
      'title': title,
    },
  };

  /// Null for a `kind` this version does not know: the entry is skipped so
  /// a newer agent's new session kinds never break the list (spec §7.9).
  static SessionInfo? _fromMap(Object? value, String type) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$type: session entry must be a map');
    }
    final f = _Fields(value, type);
    final kind = switch (f.optionalString('kind')) {
      null => SessionKind.shellx,
      'desktop' => SessionKind.desktop,
      _ => null,
    };
    if (kind == null) return null;
    return SessionInfo(
      id: f.integer('id'),
      index: f.integer('index'),
      shell: f.string('shell'),
      createdAt: f.integer('created_at'),
      attached: f.boolean('attached'),
      kind: kind,
      app: f.optionalString('app') ?? '',
      title: f.optionalString('title') ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionInfo && _deepEquals(toMap(), other.toMap());

  @override
  int get hashCode => _deepHash(toMap());

  @override
  String toString() => 'SessionInfo${_describe(toMap())}';
}

final class SessionListResult extends AppMessage {
  const SessionListResult(this.sessions, {this.desktopSharing});
  final List<SessionInfo> sessions;

  /// Whether terminal sharing is on (spec §8); only in answers to
  /// `session.list {desktop: true}`. Null means an agent without terminal
  /// sharing, or a list that did not ask.
  final bool? desktopSharing;
  @override
  String get type => 'session.list.result';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'sessions': [for (final session in sessions) session.toMap()],
    if (desktopSharing != null) 'desktop_sharing': desktopSharing,
  };
}

final class SessionOpen extends AppMessage {
  const SessionOpen({required this.cols, required this.rows});
  final int cols, rows;
  @override
  String get type => 'session.open';
  @override
  Map<String, Object?> toMap() => {'t': type, 'cols': cols, 'rows': rows};
}

final class SessionOpened extends AppMessage {
  const SessionOpened({
    required this.id,
    required this.index,
    required this.shell,
  });
  final int id, index;
  final String shell;
  @override
  String get type => 'session.opened';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'index': index,
    'shell': shell,
  };
}

final class SessionAttach extends AppMessage {
  const SessionAttach({
    required this.id,
    required this.cols,
    required this.rows,
    required this.lastSeq,
  });
  final int id, cols, rows, lastSeq;
  @override
  String get type => 'session.attach';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'cols': cols,
    'rows': rows,
    'last_seq': lastSeq,
  };
}

final class SessionAttached extends AppMessage {
  const SessionAttached({required this.id});
  final int id;
  @override
  String get type => 'session.attached';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id};
}

final class SessionReset extends AppMessage {
  const SessionReset({required this.id});
  final int id;
  @override
  String get type => 'session.reset';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id};
}

final class OutputMessage extends AppMessage {
  const OutputMessage({
    required this.id,
    required this.seq,
    required this.data,
  });
  final int id, seq;
  final Uint8List data;
  @override
  String get type => 'output';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'seq': seq,
    'data': data,
  };
}

final class AckMessage extends AppMessage {
  const AckMessage({required this.id, required this.seq});
  final int id, seq;
  @override
  String get type => 'ack';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'seq': seq};
}

final class InputMessage extends AppMessage {
  const InputMessage({required this.id, required this.data});
  final int id;
  final Uint8List data;
  @override
  String get type => 'input';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'data': data};
}

final class ResizeMessage extends AppMessage {
  const ResizeMessage({
    required this.id,
    required this.cols,
    required this.rows,
  });
  final int id, cols, rows;
  @override
  String get type => 'resize';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'id': id,
    'cols': cols,
    'rows': rows,
  };
}

final class SessionClose extends AppMessage {
  const SessionClose({required this.id});
  final int id;
  @override
  String get type => 'session.close';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id};
}

/// The phone leaves a desktop session; the terminal keeps running (spec §8).
/// Never answered.
final class SessionDetach extends AppMessage {
  const SessionDetach({required this.id});
  final int id;
  @override
  String get type => 'session.detach';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id};
}

/// Who sets a desktop terminal's size now (spec §5.5, §7.3).
enum DriverSide {
  desktop('desktop'),
  phone('phone');

  const DriverSide(this.wire);
  final String wire;

  /// Throws [FormatException] for an unknown value.
  static DriverSide fromWire(String wire) {
    for (final side in values) {
      if (side.wire == wire) return side;
    }
    throw FormatException('Unknown driver side', wire);
  }
}

final class SessionDriver extends AppMessage {
  const SessionDriver({required this.id, required this.by});
  final int id;
  final DriverSide by;
  @override
  String get type => 'session.driver';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'by': by.wire};
}

final class SessionExited extends AppMessage {
  const SessionExited({required this.id, required this.exitCode});
  final int id, exitCode;
  @override
  String get type => 'session.exited';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'exit_code': exitCode};
}

enum DetachReason {
  takenOver('taken_over'),
  closedByHost('closed_by_host'),
  terminalGone('terminal_gone');

  const DetachReason(this.wire);
  final String wire;

  /// Throws [FormatException] for an unknown value.
  static DetachReason fromWire(String wire) {
    for (final reason in values) {
      if (reason.wire == wire) {
        return reason;
      }
    }
    throw FormatException('Unknown detach reason', wire);
  }
}

final class SessionDetached extends AppMessage {
  const SessionDetached({required this.id, required this.reason});
  final int id;
  final DetachReason reason;
  @override
  String get type => 'session.detached';
  @override
  Map<String, Object?> toMap() => {'t': type, 'id': id, 'reason': reason.wire};
}

enum AppErrorCode {
  sessionLimit('session_limit'),
  sessionNotFound('session_not_found'),
  spawnFailed('spawn_failed');

  const AppErrorCode(this.wire);
  final String wire;

  /// Throws [FormatException] for an unknown value.
  static AppErrorCode fromWire(String wire) {
    for (final code in values) {
      if (code.wire == wire) {
        return code;
      }
    }
    throw FormatException('Unknown app error code', wire);
  }
}

final class ErrorMessage extends AppMessage {
  const ErrorMessage({required this.code, required this.message, this.id});
  final AppErrorCode code;
  final String message;
  final int? id;
  @override
  String get type => 'error';

  /// "id" is omitted (not null) when absent.
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'code': code.wire,
    'message': message,
    if (id != null) 'id': id,
  };
}

/// Encodes 1..n messages as a CBOR array of maps.
Uint8List encodeBatch(List<AppMessage> messages) =>
    encodeCbor([for (final message in messages) message.toMap()]);

/// Decodes a CBOR array of maps, skipping messages whose "t" is unknown.
/// Throws [FormatException] if [bytes] is not a CBOR array of maps or a
/// known message is malformed.
List<AppMessage> decodeBatch(Uint8List bytes) {
  final decoded = decodeCbor(bytes);
  if (decoded is! List<Object?>) {
    throw const FormatException('Message batch must be a CBOR array');
  }
  final messages = <AppMessage>[];
  for (final item in decoded) {
    if (item is! Map<Object?, Object?>) {
      throw const FormatException('Batch item must be a CBOR map');
    }
    final message = AppMessage.fromMap(item);
    if (message != null) {
      messages.add(message);
    }
  }
  return messages;
}

final class _Fields {
  _Fields(this._map, this._type);
  final Map<Object?, Object?> _map;
  final String _type;

  int integer(String key) => _get<int>(key);
  String string(String key) => _get<String>(key);
  bool boolean(String key) => _get<bool>(key);
  Uint8List bytes(String key) => _get<Uint8List>(key);
  List<Object?> list(String key) => _get<List<Object?>>(key);

  int? optionalInteger(String key) {
    final value = _map[key];
    if (value == null || value is int) {
      return value as int?;
    }
    throw FormatException('$_type: "$key" must be an integer');
  }

  bool? optionalBoolean(String key) {
    final value = _map[key];
    if (value == null || value is bool) return value as bool?;
    throw FormatException('$_type: "$key" must be a boolean');
  }

  String? optionalString(String key) {
    final value = _map[key];
    if (value == null || value is String) return value as String?;
    throw FormatException('$_type: "$key" must be a string');
  }

  T _get<T>(String key) {
    final value = _map[key];
    if (value is T) {
      return value;
    }
    throw FormatException('$_type: "$key" missing or not a $T');
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) => switch (value) {
  Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((entry) => Object.hash(entry.key, _deepHash(entry.value))),
  ),
  List<Object?> list => Object.hashAll(list.map(_deepHash)),
  _ => value.hashCode,
};

String _describe(Object? value) => switch (value) {
  Uint8List bytes => '<${bytes.length} bytes>',
  Map<Object?, Object?> map =>
    '{${map.entries.map((entry) => '${entry.key}: ${_describe(entry.value)}').join(', ')}}',
  List<Object?> list => '[${list.map(_describe).join(', ')}]',
  _ => '$value',
};
