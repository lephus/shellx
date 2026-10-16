import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../remote/session_launch.dart';
import '../session/local_sessions.dart';
import '../session/session_manager.dart';
import '../session/session_notice.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';
import 'ui_api.dart';

/// An error answer of the peer, or `disconnected` once the link is gone.
/// [fields] are the extra keys of the `error` message (`max` for
/// `session_limit`).
final class MuxRemoteException implements Exception {
  const MuxRemoteException(this.code, [this.message, this.fields = const {}]);
  final String code;
  final String? message;
  final Map<String, Object?> fields;

  @override
  String toString() => 'MuxRemoteException($code)';
}

/// A5b §3.2: request/response and events over one [MuxConnection] of the
/// client side.
///
/// - [request] completes with the `result` or throws [MuxRemoteException];
///   when the link ends every pending request, and any later one, fails with
///   code `disconnected`.
/// - [events] carries everything that is not an answer and not a request
///   (a broadcast stream). [early] messages (what arrived after `ready`,
///   before this client listened: [MuxPeerInfo.early]) are delivered to the
///   first listener, in order.
/// - A request from the daemon (a message with a `q`, e.g. `ui.*`) goes to
///   [onRequest]; its result (or [MuxRemoteException] / [CliFailure]) is
///   sent back on the same `q`. Without a handler the answer is
///   `error{unknown_type}`.
///
/// Never logs message contents.
final class MuxClient {
  MuxClient(this._c, {Iterable<MuxMessage> early = const [], this.onRequest}) {
    _early.addAll(early);
    _events = StreamController<MuxMessage>.broadcast(
      sync: true,
      onListen: () => scheduleMicrotask(_drainEarly),
    );
    _sub = _c.messages.listen(_onMessage);
    unawaited(_c.done.then((_) => _failAll()));
    final queued = [..._early];
    _early.clear();
    queued.forEach(_onMessage);
  }

  final MuxConnection _c;
  final Future<Map<String, Object?>> Function(MuxMessage request)? onRequest;
  late final StreamSubscription<MuxMessage> _sub;
  late final StreamController<MuxMessage> _events;
  final _pending = <int, Completer<MuxMessage>>{};
  final _early = <MuxMessage>[];
  var _next = 1;
  var _gone = false;

  Stream<MuxMessage> get events => _events.stream;
  Future<void> get done => _c.done;

  Future<MuxMessage> request(
    String type, [
    Map<String, Object?> fields = const {},
  ]) {
    if (_gone) return Future.error(const MuxRemoteException('disconnected'));
    final q = _next++;
    final c = Completer<MuxMessage>();
    _pending[q] = c;
    try {
      _c.send(MuxMessage(type, q: q, fields: fields));
    } on Object {
      _pending.remove(q);
      return Future.error(const MuxRemoteException(MuxError.internal));
    }
    return c.future;
  }

  /// No answer is expected (and none is asked for).
  void send(String type, [Map<String, Object?> fields = const {}]) {
    if (_gone) return;
    try {
      _c.send(MuxMessage(type, fields: fields));
    } on Object {
      // A message the wire refuses (over 64 KiB) is dropped.
    }
  }

  void _drainEarly() {
    if (_early.isEmpty) return;
    final queued = [..._early];
    _early.clear();
    queued.forEach(_events.add);
  }

  void _onMessage(MuxMessage m) {
    final q = m.q;
    if (m.type == MuxType.result || m.type == MuxType.error) {
      final waiting = q == null ? null : _pending.remove(q);
      if (waiting == null) return;
      if (m.type == MuxType.error) {
        waiting.completeError(
          MuxRemoteException(
            m.get<String>('code') ?? MuxError.internal,
            m.get<String>('message'),
            m.fields,
          ),
        );
      } else {
        waiting.complete(m);
      }
      return;
    }
    if (q != null) {
      unawaited(_answer(m, q));
      return;
    }
    // While earlier messages wait for their drain, later ones queue behind
    // them: order is kept.
    if (_events.hasListener && _early.isEmpty) {
      _events.add(m);
    } else {
      _early.add(m);
    }
  }

  Future<void> _answer(MuxMessage m, int q) async {
    MuxMessage reply;
    try {
      final handler = onRequest;
      if (handler == null) {
        reply = MuxMessage(
          MuxType.error,
          q: q,
          fields: {'code': MuxError.unknownType},
        );
      } else {
        reply = MuxMessage(MuxType.result, q: q, fields: await handler(m));
      }
    } on MuxRemoteException catch (e) {
      reply = _failure(q, e.code, e.message);
    } on CliFailure catch (e) {
      reply = _failure(q, e.code, e.message);
    } on Object catch (e) {
      reply = _failure(q, MuxError.internal, e.runtimeType.toString());
    }
    if (_gone) return;
    try {
      _c.send(reply);
    } on Object {
      // The link went away meanwhile.
    }
  }

  MuxMessage _failure(int q, String code, String? message) => MuxMessage(
    MuxType.error,
    q: q,
    fields: {'code': code, 'message': ?message},
  );

  void _failAll() {
    _gone = true;
    for (final c in _pending.values) {
      c.completeError(const MuxRemoteException('disconnected'));
    }
    _pending.clear();
    unawaited(_events.close());
  }

  Future<void> close() async {
    await _sub.cancel();
    await _c.close();
  }
}

/// What a view shows after `view.reset` (D11): the daemon dropped output
/// while the UI could not keep up, so the screen is cleared and the ring
/// buffer replayed. A fresh `ESC` ends any escape sequence the dropped
/// output left half-written.
const String kViewResetPrefix = '\r\n\x1b[H\x1b[2J';

/// A5b D10: [LocalSessions] of a daemon, over a [MuxClient].
///
/// - [sessions] is a cache fed by `sessions.list` and `sessions.changed`
///   (the daemon coalesces changes within 16 ms). [open] returns only once
///   the new session is in it.
/// - [notify] is synchronous in the interface: it sends the request without
///   waiting and returns true iff [id] is in the cached [sessions] (stale by
///   at most the coalescing delay).
/// - A dead link does not end the views (the UI must not print exit lines):
///   watch [disconnected]. Writes after it are dropped, never queued.
/// - One live view per session id: a second [view] of the same id detaches
///   the first silently.
final class RemoteLocalSessions implements LocalSessions {
  RemoteLocalSessions(
    this._client, {
    this.ackEvery = 65536,
    this.ackDelay = const Duration(milliseconds: 100),
  }) {
    _client.events.listen(_onEvent);
    disconnected = _client.done.then((_) {
      _connected = false;
      for (final v in [..._views.values]) {
        v._lose();
      }
      if (!_ready.isCompleted) {
        _ready.completeError(const MuxRemoteException('disconnected'));
      }
    });
    unawaited(_ready.future.then((_) {}, onError: (Object _) {}));
    // The daemon sends nothing unsolicited: the first list is asked for.
    unawaited(
      _refresh().then(
        (_) {},
        onError: (Object e) {
          if (!_ready.isCompleted) _ready.completeError(e);
        },
      ),
    );
  }

  final MuxClient _client;

  /// A view acks once this many bytes are unacked, or after [ackDelay].
  final int ackEvery;
  final Duration ackDelay;
  var _sessions = const <SessionSummary>[];
  final _changes = StreamController<void>.broadcast();
  final _notices = StreamController<SessionNotice>.broadcast();
  final _views = <int, RemoteSessionView>{};
  final _ready = Completer<void>();
  var _connected = true;

  /// Completes when the link ends (the daemon went away or [close]).
  late final Future<void> disconnected;

  /// Completes when the first `sessions.list` answer arrived (with a
  /// [MuxRemoteException] if the link ended first).
  Future<void> get ready => _ready.future;
  bool get connected => _connected;

  /// The request channel, for `daemon.status` / `daemon.quit` / `agent.*`.
  MuxClient get client => _client;

  @override
  List<SessionSummary> get sessions => _sessions;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Stream<SessionNotice> get notices => _notices.stream;

  Future<void> _refresh() async {
    final r = await _client.request(MuxType.sessionsList);
    _apply(r.get<List<Object?>>('sessions') ?? const []);
  }

  void _apply(List<Object?> wire) {
    final next = <SessionSummary>[];
    for (final s in wire) {
      if (s is! Map<Object?, Object?>) continue;
      try {
        next.add(summaryFromWire(s));
      } on Object {
        // A summary this version cannot read is skipped.
      }
    }
    _sessions = List.unmodifiable(next);
    if (!_ready.isCompleted) _ready.complete();
    _changes.add(null);
  }

  @override
  Future<int> open({
    required int cols,
    required int rows,
    String? cwd,
    int? tabId,
    SessionLaunch? launch,
  }) async {
    final MuxMessage r;
    try {
      r = await _client.request(MuxType.sessionsOpen, {
        'cols': cols,
        'rows': rows,
        'cwd': ?cwd,
        'tabId': ?tabId,
        'launch': ?launch?.toJson(),
      });
    } on MuxRemoteException catch (e) {
      throw switch (e.code) {
        MuxError.sessionLimit => SessionLimitException(
          e.fields['max'] is int ? e.fields['max']! as int : 0,
        ),
        MuxError.spawnFailed => SpawnFailedException(e.message ?? ''),
        _ => e,
      };
    }
    final id = r.get<int>('id')!;
    if (!_sessions.any((s) => s.id == id)) await _refresh();
    return id;
  }

  /// Sends and returns at once; true iff [id] is a session in [sessions].
  @override
  bool notify(int id, {String? title, required String body}) {
    final listed = _connected && _sessions.any((s) => s.id == id);
    if (listed) {
      _client.send(MuxType.sessionsNotify, {
        'id': id,
        'title': ?title,
        'body': body,
      });
    }
    return listed;
  }

  @override
  LocalSessionView view(int id) {
    _views.remove(id)?._detach();
    final v = RemoteSessionView._(this, id);
    _views[id] = v;
    _client
        .request(MuxType.viewOpen, {'id': id})
        .then(
          (_) {},
          onError: (Object _) {
            if (identical(_views[id], v)) v._lose();
          },
        );
    return v;
  }

  @override
  void close(int id) => _client.send(MuxType.sessionsClose, {'id': id});

  @override
  void watchPorts(bool visible) =>
      _client.send(MuxType.sessionsWatchPorts, {'visible': visible});

  void _onEvent(MuxMessage m) {
    try {
      switch (m.type) {
        case MuxType.sessionsChanged:
          _apply(m.get<List<Object?>>('sessions') ?? const []);
        case MuxType.sessionsNotice:
          _notices.add(noticeFromWire(m.fields));
        case MuxType.viewOut:
          _views[m.get<int>('id')]?._out(
            m.get<Uint8List>('data')!,
            backlog: m.get<bool>('bl') ?? false,
          );
        case MuxType.viewLive:
          _views[m.get<int>('id')]?._live();
        case MuxType.viewReset:
          _views[m.get<int>('id')]?._reset();
        case MuxType.viewDriver:
          _views[m.get<int>('id')]?._driver(
            DriverSide.fromWire(m.get<String>('side')!),
          );
        case MuxType.viewExit:
          _views
              .remove(m.get<int>('id'))
              ?._end(
                m.get<int>('code') ?? -1,
                onRequest: m.get<bool>('onRequest') ?? false,
              );
      }
    } on Object {
      // A message this version cannot read is ignored (D7).
    }
  }
}

/// One view of a remote session. [backlog] is empty: the daemon streams the
/// ring buffer first, flagged, and [pendingBacklog] completes with it before
/// any live byte reaches [output] (D10). After a `view.reset` the replay is
/// part of [output] (behind a clear-screen), and [reply] is dropped until
/// it has ended, so a query in replayed text is never answered into the
/// shell.
final class RemoteSessionView implements LocalSessionView {
  RemoteSessionView._(this._owner, this.id);

  final RemoteLocalSessions _owner;
  @override
  final int id;
  // Sync: [replaying] is read inside the listener, per chunk.
  final _output = StreamController<Uint8List>(sync: true);
  final _driverChanges = StreamController<DriverSide>.broadcast();
  final _exit = Completer<int>();
  var _onRequest = false;
  var _unacked = 0;
  Timer? _ackTimer;
  var _disposed = false;

  /// The daemon is replaying the ring buffer (first backlog or a reset).
  var _replaying = true;

  /// The first replay is collected for [pendingBacklog]; later ones stream.
  var _first = true;
  final _firstBytes = BytesBuilder(copy: false);
  final _pending = Completer<Uint8List>();

  /// Live output held for one microtask after [pendingBacklog] completes, so
  /// its consumer runs first.
  var _holding = false;
  final _held = <Uint8List>[];

  @override
  Uint8List get backlog => Uint8List(0);
  @override
  Future<Uint8List>? get pendingBacklog => _pending.future;
  @override
  bool get replaying => _replaying && !_first;

  /// The connection ended (or `view.open` failed) before the session did:
  /// [output] is done and [pendingBacklog] complete, but [exitCode] never
  /// completes, so no exit line is written. The desktop learns of the loss
  /// from [RemoteLocalSessions.disconnected] (A5b Task 8).
  bool get lost => _lost;
  var _lost = false;
  Timer? _liveTimer;
  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Stream<DriverSide> get driver => _driverChanges.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get closedOnRequest => _onRequest;

  void _out(Uint8List data, {required bool backlog}) {
    if (_disposed || _output.isClosed) return;
    _unacked += data.length;
    if (backlog && _first) {
      _firstBytes.add(data);
      // A daemon that never says `view.live` must not hold the pane's
      // input and replies shut.
      _liveTimer ??= Timer(const Duration(seconds: 5), _live);
    } else if (_holding) {
      _held.add(data);
    } else {
      _output.add(data);
    }
    if (_unacked >= _owner.ackEvery) {
      _ack();
    } else {
      _ackTimer ??= Timer(_owner.ackDelay, _ack);
    }
  }

  void _ack() {
    _ackTimer?.cancel();
    _ackTimer = null;
    if (_unacked == 0 || _disposed) return;
    final n = _unacked;
    _unacked = 0;
    _owner._client.send(MuxType.viewAck, {'id': id, 'bytes': n});
  }

  void _live() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _replaying = false;
    if (!_first) return;
    _first = false;
    _holding = true;
    _pending.complete(_firstBytes.takeBytes());
    scheduleMicrotask(() {
      _holding = false;
      for (final d in _held) {
        if (!_output.isClosed) _output.add(d);
      }
      _held.clear();
    });
  }

  void _reset() {
    if (_disposed || _output.isClosed) return;
    _replaying = true;
    _ackTimer?.cancel();
    _ackTimer = null;
    _unacked = 0;
    _output.add(Uint8List.fromList(utf8.encode(kViewResetPrefix)));
  }

  void _driver(DriverSide side) {
    if (!_driverChanges.isClosed) _driverChanges.add(side);
  }

  void _end(int code, {required bool onRequest}) {
    _onRequest = onRequest;
    _liveTimer?.cancel();
    _ackTimer?.cancel();
    if (!_pending.isCompleted) _pending.complete(_firstBytes.takeBytes());
    for (final d in _held) {
      if (!_output.isClosed) _output.add(d);
    }
    _held.clear();
    if (!_exit.isCompleted) _exit.complete(code);
    unawaited(_output.close());
    unawaited(_driverChanges.close());
  }

  /// The link is gone: stop without an exit (see [lost]).
  void _lose() {
    if (_disposed || _lost || _exit.isCompleted) return;
    _lost = true;
    _liveTimer?.cancel();
    _ackTimer?.cancel();
    if (!_pending.isCompleted) _pending.complete(_firstBytes.takeBytes());
    for (final d in _held) {
      if (!_output.isClosed) _output.add(d);
    }
    _held.clear();
    unawaited(_output.close());
    unawaited(_driverChanges.close());
  }

  /// Another view took this id: stop without an exit.
  void _detach() {
    _disposed = true;
    _liveTimer?.cancel();
    _ackTimer?.cancel();
    unawaited(_output.close());
    unawaited(_driverChanges.close());
  }

  @override
  void write(Uint8List data) => _data(MuxType.viewWrite, data);

  @override
  void reply(Uint8List data) {
    // Relies on the consumer writing replay text synchronously (the desktop
    // TerminalFeed does): a reply to a query in the replay is then made
    // while [_replaying] still holds, and dropped here.
    if (!_replaying) _data(MuxType.viewReply, data);
  }

  void _data(String type, Uint8List data) {
    if (_disposed) return;
    _owner._client.send(type, {'id': id, 'data': data});
  }

  @override
  void resize(int cols, int rows) {
    if (_disposed) return;
    _owner._client.send(MuxType.viewResize, {
      'id': id,
      'cols': cols,
      'rows': rows,
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _liveTimer?.cancel();
    _ackTimer?.cancel();
    if (identical(_owner._views[id], this)) _owner._views.remove(id);
    _owner._client.send(MuxType.viewClose, {'id': id});
    unawaited(_output.close());
    unawaited(_driverChanges.close());
  }
}
