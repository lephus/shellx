import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../notify/command_tracker.dart';
import '../remote/session_launch.dart';
import '../session/session_manager.dart';
import '../session/session_notice.dart';
import '../term/term_frames.dart';

/// A5b D7: bump only for a breaking change.
const int kMuxProtocol = 1;

abstract final class MuxType {
  static const hello = 'hello', auth = 'auth', ready = 'ready';
  static const result = 'result', error = 'error';
  static const daemonStatus = 'daemon.status', daemonQuit = 'daemon.quit';
  static const sessionsList = 'sessions.list';
  static const sessionsChanged = 'sessions.changed';
  static const sessionsOpen = 'sessions.open';
  static const sessionsClose = 'sessions.close';
  static const sessionsNotice = 'sessions.notice';
  static const sessionsWatchPorts = 'sessions.watchPorts';
  static const viewOpen = 'view.open', viewOut = 'view.out';
  static const viewDriver = 'view.driver', viewExit = 'view.exit';
  static const viewWrite = 'view.write', viewReply = 'view.reply';
  static const viewResize = 'view.resize', viewAck = 'view.ack';
  static const viewReset = 'view.reset', viewClose = 'view.close';
  static const agentState = 'agent.state', agentCall = 'agent.call';
  static const agentGet = 'agent.get';
}

abstract final class MuxError {
  static const unknownType = 'unknown_type', badRequest = 'bad_request';
  static const notFound = 'not_found', busy = 'busy';
  static const unsupportedRole = 'unsupported_role';
  static const sessionLimit = 'session_limit', spawnFailed = 'spawn_failed';
  static const internal = 'internal';
}

/// One message (D9): `{"t": type, "q": request id?, …fields}`. An open
/// map: unknown keys are carried and ignored (D7).
final class MuxMessage {
  const MuxMessage(this.type, {this.q, this.fields = const {}});
  final String type;
  final int? q;
  final Map<String, Object?> fields;

  T? get<T>(String key) {
    final v = fields[key];
    return v is T ? v : null;
  }

  @override
  String toString() => 'MuxMessage($type${q == null ? '' : ' #$q'})';
}

Uint8List encodeMux(MuxMessage m) =>
    termFrame(encodeCbor({'t': m.type, 'q': ?m.q, ...m.fields}));

/// Bytes from a connection → messages. Throws [FormatException] on a frame
/// over 64 KiB, bad CBOR (depth > 8 included) or a payload that is not a
/// map with a string `t`: the caller closes the connection (D26).
final class MuxFrameDecoder {
  final _frames = TermFrameReader();

  List<MuxMessage> add(List<int> chunk) => [
    for (final payload in _frames.add(chunk)) _decode(payload),
  ];

  static MuxMessage _decode(Uint8List payload) {
    final value = decodeCbor(payload);
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('mux payload is not a map');
    }
    final type = value['t'];
    final q = value['q'];
    if (type is! String || (q != null && q is! int)) {
      throw const FormatException('mux message without a type');
    }
    return MuxMessage(
      type,
      q: q as int?,
      fields: {
        for (final MapEntry(:key, :value) in value.entries)
          if (key is String && key != 't' && key != 'q') key: value,
      },
    );
  }
}

Map<String, Object?> summaryToWire(SessionSummary s) => {
  'id': s.id,
  'index': s.index,
  'shell': s.shell,
  'created': s.createdAt.toUtc().microsecondsSinceEpoch,
  'mobile': s.attachedMobileId,
  'origin': s.origin.name,
  'title': s.title,
  'driver': s.driver.wire,
  'running': s.runningCommand,
  'cwd': s.cwd,
  'branch': s.gitBranch,
  'ports': s.ports,
  if (s.remote case final r?)
    'remote': {
      'launch': r.launch.toJson(),
      'connected': r.connected,
      'home': r.home,
    },
};

SessionSummary summaryFromWire(Map<Object?, Object?> m) => SessionSummary(
  id: m['id']! as int,
  index: m['index']! as int,
  shell: m['shell']! as String,
  createdAt: DateTime.fromMicrosecondsSinceEpoch(
    m['created']! as int,
    isUtc: true,
  ),
  attachedMobileId: m['mobile'] as String?,
  origin: SessionOrigin.values.byName(m['origin']! as String),
  title: m['title'] as String? ?? '',
  driver: DriverSide.fromWire(m['driver']! as String),
  runningCommand: m['running'] as bool? ?? false,
  cwd: m['cwd'] as String?,
  gitBranch: m['branch'] as String?,
  ports: [for (final p in m['ports'] as List<Object?>? ?? const []) p! as int],
  remote: _remoteFromWire(m['remote']),
);

SessionRemote? _remoteFromWire(Object? json) {
  if (json is! Map<Object?, Object?>) return null;
  final launch = SessionLaunch.fromJson(json['launch']);
  if (launch == null) return null;
  return SessionRemote(
    launch: launch,
    connected: json['connected'] == true,
    home: json['home'] as String?,
  );
}

Map<String, Object?> noticeToWire(SessionNotice n) => {
  'id': n.sessionId,
  'kind': n.kind.name,
  'at': n.at.toUtc().microsecondsSinceEpoch,
  'title': n.title,
  'body': n.body,
  if (n.command case final c?) ...{
    'cmd': c.commandLine,
    'code': c.exitCode,
    'ms': c.duration.inMilliseconds,
  },
};

SessionNotice noticeFromWire(Map<Object?, Object?> m) => SessionNotice(
  sessionId: m['id']! as int,
  kind: SessionNoticeKind.values.byName(m['kind']! as String),
  at: DateTime.fromMicrosecondsSinceEpoch(m['at']! as int, isUtc: true),
  title: m['title'] as String?,
  body: m['body'] as String?,
  command: m.containsKey('code')
      ? CompletedCommand(
          commandLine: m['cmd'] as String?,
          exitCode: m['code']! as int,
          duration: Duration(milliseconds: m['ms']! as int),
        )
      : null,
);
