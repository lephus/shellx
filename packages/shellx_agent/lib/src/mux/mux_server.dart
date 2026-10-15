import 'dart:async';
import 'dart:typed_data';

import '../remote/session_launch.dart';
import '../session/local_sessions.dart';
import '../term/term_frames.dart';
import '../tool/tool_catalog.dart';
import '../tool/tool_proxy.dart';
import 'cli_host.dart';
import 'cli_wire.dart';
import 'mux_ai.dart';
import 'mux_handshake.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';
import 'ui_api.dart';

/// The daemon's agent, as the wire sees it (`agent.get`, `agent.state`,
/// `agent.call`).
abstract interface class AgentBridge {
  Stream<Map<String, Object?>> get states;
  Map<String, Object?> get current;
  Future<Object?> call(String method, Map<String, Object?> args);
}

/// A5b §3.1: serves one [LocalSessions] to authenticated local clients over
/// the one listener of the daemon. Role `ui` (one at a time) gets sessions,
/// views and the agent; role `cli` goes to [cli] ([CliHost.adopt]); any
/// other role is `unsupported_role`.
///
/// Never logs message contents, tokens, secrets, paths or terminal text.
final class MuxServer {
  MuxServer({
    required this.sessions,
    required Uint8List secret,
    required MuxPeerInfo self,
    this.agent,
    required this.onQuit,
    this.onUiChanged,
    this.cli,
    this.stopAbove = 2097152,
    this.resumeBelow = 524288,
    this.coalesce = const Duration(milliseconds: 16),
  }) : _secret = secret,
       _self = self {
    uiApi = _UiForwarder(this);
  }

  final LocalSessions sessions;
  final AgentBridge? agent;
  final Future<void> Function() onQuit;
  final void Function(bool uiAttached)? onUiChanged;

  /// Takes the `cli` connections (A5b D22); null → `unsupported_role`.
  /// Assignable because the host needs [uiApi] and the server the host.
  ///
  /// `daemon.status` over a `cli` connection is answered by the host and
  /// keeps the frozen A7 `{host, clients}` shape. Settings changes (tray
  /// toggles) call `cli.recheck()` directly in the daemon; there is no
  /// `daemon.cli.recheck` message.
  CliHost? cli;

  /// V2-2 D1: phones' `ai.*` messages for the attached window; null: the
  /// window's `ai.*` messages are ignored (like an older service).
  MuxAiForwarder? ai;

  /// V2-4 E5: the proxy the window's `tool.serve` lists go to; null: they are
  /// ignored (like an older service).
  ToolProxy? tools;

  /// D11: stop streaming a view above this many unacked bytes; resume
  /// (with `view.reset`) below [resumeBelow].
  final int stopAbove, resumeBelow;
  final Duration coalesce;
  final Uint8List _secret;
  final MuxPeerInfo _self;
  final _links = <_UiLink>{};
  StreamSubscription<MuxConnection>? _accept;
  MuxListener? _listener;
  int _handshaking = 0;
  _UiLink? _ui;
  Future<void>? _quit;

  /// `daemon.quit`: [onQuit] runs once; repeated and concurrent requests
  /// share its result.
  ///
  /// From the first request on the server accepts nobody (the listener is
  /// closed, a straggler is closed unanswered, and a connection that is
  /// mid-handshake is refused): existing links stay, so the caller's reply
  /// still goes out.
  Future<void> _quitOnce() {
    final running = _quit;
    if (running != null) return running;
    stopAccepting();
    return _quit = onQuit();
  }

  bool _stopped = false;

  /// Accepts nobody from now on (the listener is closed, a straggler and a
  /// connection mid-handshake are refused). Existing links stay. Used by
  /// every way the service quits, not only `daemon.quit`.
  void stopAccepting() {
    if (_stopped) return;
    _stopped = true;
    final listener = _listener;
    if (listener != null) unawaited(listener.close().catchError((Object _) {}));
  }

  /// `ui.*` requests of `cli` clients, forwarded to the attached UI (no UI
  /// → `not_found`, D22). Hand it to the [CliHost].
  late final UiApi uiApi;

  bool get uiAttached => _ui != null;

  void serve(MuxListener listener) {
    _listener = listener;
    _accept = listener.connections.listen((c) => unawaited(_onConnection(c)));
  }

  Future<void> _onConnection(MuxConnection c) async {
    if (_stopped || _handshaking >= 4) {
      await c.close(); // D23
      return;
    }
    _handshaking++;
    final MuxPeerInfo peer;
    try {
      peer = await serverHandshake(
        c,
        secret: _secret,
        self: MuxPeerInfo(
          protocol: _self.protocol,
          app: _self.app,
          instance: _self.instance,
          pid: _self.pid,
          sessions: sessions.sessions.length,
          caps: _self.caps,
        ),
      );
    } on MuxHandshakeException {
      return; // serverHandshake closed the connection
    } on Object {
      await c.close();
      return;
    } finally {
      _handshaking--;
    }
    if (_stopped) {
      _refuse(c, MuxError.busy); // quitting: nobody attaches any more
      return;
    }
    // Synchronous from here to the link's listener: nothing read after the
    // handshake's last message may be lost.
    switch (peer.role) {
      case 'ui':
        if (_ui != null) {
          _refuse(c, MuxError.busy);
          return;
        }
        final link = _UiLink(this, c);
        _links.add(link);
        _ui = link;
        onUiChanged?.call(true);
        unawaited(
          c.done.then((_) {
            link.dispose();
            _links.remove(link);
            if (identical(_ui, link)) {
              _ui = null;
              onUiChanged?.call(false);
            }
          }),
        );
        link.start(peer.early);
      case 'cli' when cli != null:
        cli!.adopt(c, peer);
      default:
        _refuse(c, MuxError.unsupportedRole);
    }
  }

  void _refuse(MuxConnection c, String code) {
    c.send(MuxMessage(MuxType.error, fields: {'code': code}));
    unawaited(c.close());
  }

  Future<void> close() async {
    await _accept?.cancel();
    for (final l in [..._links]) {
      await l.connection.close();
    }
  }
}

/// D22: `ui.*` of `cli` clients to the attached UI over the wire.
final class _UiForwarder implements UiApi {
  _UiForwarder(this._server);
  final MuxServer _server;
  final _events = StreamController<Map<String, Object?>>.broadcast();

  void emit(Map<String, Object?> event) => _events.add(event);

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) {
    final ui = _server._ui;
    if (ui == null) {
      throw const CliFailure(MuxError.notFound, 'ShellX is not open');
    }
    return ui.ask(request.type, request.fields, cancelled: cancelled);
  }

  @override
  Stream<Map<String, Object?>> events() => _events.stream;

  @override
  Future<void> notifyApp({String? title, required String body}) async {
    final ui = _server._ui;
    if (ui == null) return;
    try {
      await ui.ask(CliType.uiNotify, {'title': ?title, 'body': body});
    } on CliFailure {
      // The window refused or went away: nothing else shows it (D24 is the
      // daemon's own notifier, not this call).
    }
  }

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      _server.sessions.notify(pane, title: title, body: body);
}

final class _ViewLink {
  _ViewLink(this.view);
  LocalSessionView view;
  StreamSubscription<Uint8List>? out;
  StreamSubscription<Object?>? driver;
  int unacked = 0;
  bool paused = false;
}

final class _UiLink {
  _UiLink(this.server, this.connection);
  final MuxServer server;
  final MuxConnection connection;
  final _views = <int, _ViewLink>{};
  final _subs = <StreamSubscription<Object?>>[];
  final _asked = <int, Completer<Map<String, Object?>>>{};
  Timer? _changedTimer;
  int _nextQ = 0;

  /// Nothing goes out unsolicited before the client's first request (it
  /// attaches its listener only after the handshake returns).
  bool _primed = false;

  void start(List<MuxMessage> early) {
    early.forEach(_onMessage);
    _subs
      ..add(connection.messages.listen(_onMessage))
      ..add(server.sessions.changes.listen((_) => _scheduleChanged()))
      ..add(
        server.sessions.notices.listen((n) {
          if (_primed) {
            _send(MuxMessage(MuxType.sessionsNotice, fields: noticeToWire(n)));
          }
        }),
      );
    final agent = server.agent;
    if (agent != null) {
      _subs.add(
        agent.states.listen((s) {
          if (_primed) {
            _send(MuxMessage(MuxType.agentState, fields: {'state': s}));
          }
        }),
      );
    }
  }

  /// A daemon → UI request (`ui.*`): resolves with the result fields or
  /// throws [CliFailure] (the UI's error, or `not_found` if it went away).
  Future<Map<String, Object?>> ask(
    String type,
    Map<String, Object?> fields, {
    Future<void>? cancelled,
  }) {
    final q = ++_nextQ;
    final done = Completer<Map<String, Object?>>();
    _asked[q] = done;
    unawaited(
      connection.done.then((_) {
        if (!done.isCompleted) {
          done.completeError(
            const CliFailure(MuxError.notFound, 'ShellX was closed'),
          );
        }
      }),
    );
    unawaited(
      cancelled?.then((_) {
        if (!done.isCompleted) {
          done.completeError(const CliFailure(CliError.cancelled));
        }
      }),
    );
    try {
      connection.send(MuxMessage(type, q: q, fields: fields));
    } on Object {
      _asked.remove(q);
      return Future.error(const CliFailure(MuxError.internal));
    }
    return done.future.whenComplete(() => _asked.remove(q));
  }

  void _send(MuxMessage m) {
    try {
      connection.send(m);
    } on Object {
      // A message the wire refuses (over 64 KiB) is dropped; never throws
      // into the session layer.
    }
  }

  void _scheduleChanged() {
    if (!_primed) return;
    _changedTimer ??= Timer(server.coalesce, () {
      _changedTimer = null;
      _send(
        MuxMessage(MuxType.sessionsChanged, fields: {'sessions': _summaries()}),
      );
    });
  }

  List<Map<String, Object?>> _summaries() => [
    for (final s in server.sessions.sessions) summaryToWire(s),
  ];

  void _reply(int? q, [Map<String, Object?> fields = const {}]) {
    if (q != null) _send(MuxMessage(MuxType.result, q: q, fields: fields));
  }

  void _error(
    int? q,
    String code, {
    String? message,
    Map<String, Object?>? more,
  }) {
    if (q != null) {
      _send(
        MuxMessage(
          MuxType.error,
          q: q,
          fields: {'code': code, 'message': ?message, ...?more},
        ),
      );
    }
  }

  Future<void> _onMessage(MuxMessage m) async {
    final q = m.q;
    // An answer to a daemon → UI request.
    if (m.type == MuxType.result || m.type == MuxType.error) {
      final waiting = q == null ? null : _asked[q];
      if (waiting == null || waiting.isCompleted) return;
      if (m.type == MuxType.result) {
        waiting.complete(m.fields);
      } else {
        waiting.completeError(
          CliFailure(
            m.get<String>('code') ?? MuxError.internal,
            m.get<String>('message'),
          ),
        );
      }
      return;
    }
    if (m.type == MuxType.uiEvent) {
      (server.uiApi as _UiForwarder).emit(m.fields);
      return;
    }
    // V2-2: no answer is ever asked for (an older service ignores them).
    if (m.type == MuxType.aiServe) {
      server.ai?.serve(this, _send);
      return;
    }
    if (m.type == MuxType.aiOut || m.type == MuxType.aiPush) {
      server.ai?.fromUi(this, m);
      return;
    }
    // V2-4 E5: kept when the window goes (tools stay open like shells).
    if (m.type == MuxType.toolServe) {
      final body = m.get<Uint8List>('b');
      final catalog = body == null ? null : ToolCatalog.fromServeBody(body);
      if (catalog != null) server.tools?.serve(catalog);
      return;
    }
    _primed = true;
    try {
      switch (m.type) {
        case MuxType.daemonStatus:
          final self = server._self;
          _reply(q, {
            'sessions': server.sessions.sessions.length,
            'instance': self.instance,
            'app': self.app,
            'protocol': self.protocol,
            'pid': self.pid,
            'caps': self.caps,
          });
        case MuxType.daemonQuit:
          await server._quitOnce();
          _reply(q);
        case MuxType.sessionsList:
          _reply(q, {'sessions': _summaries()});
        case MuxType.sessionsOpen:
          await _open(m);
        case MuxType.sessionsClose:
          server.sessions.close(m.get<int>('id')!);
          _reply(q);
        case MuxType.sessionsWatchPorts:
          server.sessions.watchPorts(m.get<bool>('visible')!);
          _reply(q);
        case MuxType.sessionsNotify:
          final title = m.fields['title'];
          if (title != null && title is! String) {
            throw const FormatException('title');
          }
          _reply(q, {
            'ok': server.sessions.notify(
              m.get<int>('id')!,
              title: title as String?,
              body: m.get<String>('body')!,
            ),
          });
        case MuxType.viewOpen:
          _openView(m.get<int>('id')!);
          _reply(q);
        case MuxType.viewWrite:
          _views[m.get<int>('id')]?.view.write(m.get<Uint8List>('data')!);
        case MuxType.viewReply:
          _views[m.get<int>('id')]?.view.reply(m.get<Uint8List>('data')!);
        case MuxType.viewResize:
          _views[m.get<int>('id')]?.view.resize(
            m.get<int>('cols')!,
            m.get<int>('rows')!,
          );
        case MuxType.viewAck:
          _ack(m.get<int>('id')!, m.get<int>('bytes')!);
        case MuxType.viewClose:
          _closeView(m.get<int>('id')!);
        case MuxType.agentGet:
          _reply(q, {'state': server.agent?.current});
        case MuxType.agentCall:
          final agent = server.agent;
          if (agent == null) {
            _error(q, MuxError.unknownType);
            return;
          }
          final args = m.get<Map<Object?, Object?>>('a') ?? const {};
          final value = await agent.call(m.get<String>('m')!, {
            for (final e in args.entries) '${e.key}': e.value,
          });
          _reply(q, {'value': value});
        default:
          _error(q, MuxError.unknownType);
      }
    } on SessionLimitException catch (e) {
      _error(q, MuxError.sessionLimit, more: {'max': e.max});
    } on SpawnFailedException catch (e) {
      _error(q, MuxError.spawnFailed, message: e.message);
    } on TypeError {
      _error(q, MuxError.badRequest); // a missing or mistyped field
    } on FormatException {
      _error(q, MuxError.badRequest);
    } on Object catch (e) {
      _error(q, MuxError.internal, message: e.runtimeType.toString());
    }
  }

  Future<void> _open(MuxMessage m) async {
    final rawLaunch = m.fields['launch'];
    final launch = rawLaunch == null ? null : SessionLaunch.fromJson(rawLaunch);
    if (rawLaunch != null && launch == null) {
      // The strings the UI shows for a launch it cannot start (A8).
      throw const SpawnFailedException('bad_launch');
    }
    final tabId = m.fields['tabId'];
    final cwd = m.fields['cwd'];
    if ((tabId != null && tabId is! int) || (cwd != null && cwd is! String)) {
      throw const FormatException('open');
    }
    final id = await server.sessions.open(
      cols: m.get<int>('cols')!,
      rows: m.get<int>('rows')!,
      cwd: cwd as String?,
      tabId: tabId as int?,
      launch: launch,
    );
    _reply(m.q, {'id': id});
  }

  void _openView(int id) {
    _closeView(id);
    final LocalSessionView view;
    try {
      view = server.sessions.view(id);
    } on StateError {
      _send(
        MuxMessage(
          MuxType.viewExit,
          fields: {'id': id, 'code': -1, 'onRequest': true},
        ),
      );
      return;
    }
    final link = _ViewLink(view);
    _views[id] = link;
    _sendBacklog(id, link, view.backlog);
    _listen(id, link);
    link.driver = view.driver.listen(
      (side) => _send(
        MuxMessage(MuxType.viewDriver, fields: {'id': id, 'side': side.wire}),
      ),
    );
    unawaited(
      view.exitCode.then((code) {
        if (_views[id] != link) return;
        _send(
          MuxMessage(
            MuxType.viewExit,
            fields: {
              'id': id,
              'code': code,
              'onRequest': link.view.closedOnRequest,
            },
          ),
        );
      }),
    );
  }

  void _listen(int id, _ViewLink link) {
    link.out = link.view.output.listen((bytes) {
      // D11: while stopped, output is dropped here; the ring buffer keeps
      // it and the reset carries it.
      if (link.paused) return;
      _sendOut(id, link, bytes);
      if (link.unacked > server.stopAbove) link.paused = true;
    });
  }

  /// The ring buffer: flagged frames, then `view.live`.
  void _sendBacklog(
    int id,
    _ViewLink link,
    Uint8List bytes, {
    bool count = true,
  }) {
    _sendOut(id, link, bytes, count: count, backlog: true);
    _send(MuxMessage(MuxType.viewLive, fields: {'id': id}));
  }

  void _sendOut(
    int id,
    _ViewLink link,
    Uint8List bytes, {
    bool count = true,
    bool backlog = false,
  }) {
    for (var i = 0; i < bytes.length; i += kTermMaxChunk) {
      final end = i + kTermMaxChunk < bytes.length
          ? i + kTermMaxChunk
          : bytes.length;
      final piece = Uint8List.sublistView(bytes, i, end);
      if (count) link.unacked += piece.length;
      _send(
        MuxMessage(
          MuxType.viewOut,
          fields: {'id': id, 'data': piece, if (backlog) 'bl': true},
        ),
      );
    }
  }

  void _ack(int id, int bytes) {
    final link = _views[id];
    if (link == null || bytes < 0) return;
    link.unacked = link.unacked > bytes ? link.unacked - bytes : 0;
    if (link.paused && link.unacked < server.resumeBelow) {
      // A fresh view: its backlog is the ring buffer as it is now (D11).
      unawaited(link.out?.cancel());
      link.view.dispose();
      final LocalSessionView fresh;
      try {
        fresh = server.sessions.view(id);
      } on StateError {
        return; // ended meanwhile: view.exit already went out
      }
      link
        ..view = fresh
        ..paused = false
        ..unacked = 0;
      _send(MuxMessage(MuxType.viewReset, fields: {'id': id}));
      // The re-sent backlog is not counted: it must not re-pause the view
      // it just resumed (D11).
      _sendBacklog(id, link, fresh.backlog, count: false);
      _listen(id, link);
    }
  }

  void _closeView(int id) {
    final link = _views.remove(id);
    if (link == null) return;
    unawaited(link.out?.cancel());
    unawaited(link.driver?.cancel());
    link.view.dispose();
  }

  void dispose() {
    _changedTimer?.cancel();
    server.ai?.unserve(this);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    for (final id in [..._views.keys]) {
      _closeView(id);
    }
  }
}
