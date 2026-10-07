import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'cli_wire.dart';
import 'mux_endpoint.dart';
import 'mux_handshake.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';
import 'ui_api.dart';

/// A7 D2: the CLI API served by the window process (before A5b, and the
/// shape A5b's daemon reuses). Listens on the A5b address, writes the A5b
/// endpoint file, authenticates with the A5b handshake, accepts only
/// `role: "cli"`.
///
/// A7 amendment: a client whose `auth.token` equals [token] (the
/// per-launch `SHELLX_CLI_TOKEN` of ShellX shells), or any client while
/// `allowExternal()` ("Allow other terminals") is on, gets
/// the full API. Any other client is *limited*: it may send `api.version`
/// and a pane-less `cli.notify`; anything else is `forbidden` and closes
/// the connection (final ruling M1: a client with a token that is not this
/// launch's is told it comes from an earlier launch). `allowExternal()` is read per request and per event:
/// unticking it applies to open connections at once.
///
/// D32: at most [maxClients] authenticated clients (final ruling M5: of
/// them at most [maxLimited] limited ones) and four handshakes at once; one connection's requests run in order, at most 64 waiting
/// (`busy` beyond); [maxListeners] event subscribers. Back-pressure from
/// the transport (`pendingBytes`/`drained`): while a client leaves over
/// 256 KiB of answers unread, its requests wait and its input is paused;
/// D24: over 1000 events it has not taken are dropped, then one
/// `overflow{dropped}` once it caught up. The Windows pipe counts too: its
/// writer isolate reports what it wrote (A7 final ruling W1; ⚠ run on
/// Windows by hand).
///
/// Never logs tokens, the secret, notification text or request contents.
final class CliHost {
  CliHost({
    required MuxTransport transport,
    required this.address,
    required MuxEndpointFile endpointFile,
    required UiApi ui,
    required bool Function() enabled,
    required String token,
    required bool Function() allowExternal,
    required this.appVersion,
    this.maxClients = 8,
    this.maxLimited = 2,
    this.maxListeners = 4,
    void Function(String message)? log,
  }) : _transport = transport,
       _file = endpointFile,
       _ui = ui,
       _enabled = enabled,
       _token = utf8.encode(token),
       _allowExternal = allowExternal,
       _log = log ?? ((_) {}),
       _hostKind = (() => 'ui'),
       _uiAttached = (() => true);

  /// A5b D8: a host with no listener of its own. The daemon's `MuxServer`
  /// owns the one listener and hands each authenticated `role: "cli"`
  /// connection to [adopt]; [start] is not available. [hostKind] is what
  /// `api.version` reports as `host` (`daemon`), [uiAttached] its `ui`.
  CliHost.adopted({
    required UiApi ui,
    required bool Function() enabled,
    required String token,
    required bool Function() allowExternal,
    required this.appVersion,
    required String Function() hostKind,
    required bool Function() uiAttached,
    this.maxClients = 8,
    this.maxLimited = 2,
    this.maxListeners = 4,
    void Function(String message)? log,
  }) : address = '',
       _transport = null,
       _file = null,
       _ui = ui,
       _enabled = enabled,
       _token = utf8.encode(token),
       _allowExternal = allowExternal,
       _log = log ?? ((_) {}),
       _hostKind = hostKind,
       _uiAttached = uiAttached;

  final String address;
  final String appVersion;
  final int maxClients;

  /// Final ruling M5: limited clients (no token of this launch, "Allow
  /// other terminals" off) take at most this many of [maxClients].
  final int maxLimited;
  final int maxListeners;
  final MuxTransport? _transport;
  final MuxEndpointFile? _file;
  final String Function() _hostKind;
  final bool Function() _uiAttached;
  final UiApi _ui;
  final bool Function() _enabled;
  final Uint8List _token;
  final bool Function() _allowExternal;
  final void Function(String) _log;

  /// A5b D23: connections still in the handshake.
  static const _maxHandshakes = 4;

  static const _notAShellXShell =
      'This terminal is not a ShellX shell. Allow it in the ShellX tray: '
      'Command line → Allow other terminals';

  /// Final ruling M1: a token, but not this launch's (a shell that outlived
  /// an earlier ShellX, e.g. under tmux).
  static const _earlierLaunch =
      'This shell belongs to an earlier ShellX launch; open a new tab';

  MuxListener? _listener;
  StreamSubscription<MuxConnection>? _accept;
  String? _written;
  late Uint8List _secret;
  late String _instance;
  final _clients = <_Client>{};
  int _handshaking = 0;
  int _listeners = 0;
  bool _stopped = false;

  int get clientCount => _clients.length;

  /// Applies the switch and "Allow other terminals" to open connections
  /// now, not at their next request or event (the tray calls this when
  /// either changes): with the switch off, subscriptions end with
  /// `cli_disabled` (connections stay); token-less connections that used
  /// the full API are refused (`forbidden`) and closed while external
  /// access is off.
  void recheck() {
    final enabled = _enabled();
    for (final c in _clients.toList()) {
      c.recheck(enabled: enabled);
    }
  }

  Future<void> start() async {
    final transport = _transport, file = _file;
    if (transport == null || file == null) {
      throw StateError('an adopting CliHost has no listener of its own');
    }
    final r = Random.secure();
    _secret = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    _instance = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _listener = await transport.listen(address);
    _accept = _listener!.connections.listen((c) => unawaited(_onConnection(c)));
    _written = await file.write(
      MuxEndpointInfo(
        address: address,
        secret: _secret,
        pid: pid,
        instance: _instance,
        protocol: kMuxProtocol,
        app: appVersion,
      ),
    );
  }

  Future<void> stop() async {
    _stopped = true;
    await _accept?.cancel();
    await _listener?.close();
    for (final c in _clients.toList()) {
      await c.connection.close();
    }
    final written = _written;
    if (written != null) await _file?.deleteIfOwned(written);
  }

  Future<void> _onConnection(MuxConnection c) async {
    if (_stopped || _handshaking >= _maxHandshakes) {
      await c.close();
      return;
    }
    _handshaking++;
    final MuxPeerInfo peer;
    try {
      peer = await serverHandshake(
        c,
        secret: _secret,
        self: MuxPeerInfo(
          protocol: kMuxProtocol,
          app: appVersion,
          instance: _instance,
          pid: pid,
          caps: const ['host.ui'],
        ),
      );
    } on MuxHandshakeException catch (e) {
      // serverHandshake closed the connection.
      _log('cli handshake failed: ${e.reason}');
      return;
    } on Object catch (e) {
      _log('cli handshake failed: ${e.runtimeType}');
      await c.close();
      return;
    } finally {
      _handshaking--;
    }
    // Synchronous from here to the client's listener: a message read after
    // the handshake's last one must not reach a stream nobody listens to.
    if (_stopped) {
      unawaited(c.close());
      return;
    }
    if (peer.role != 'cli') {
      unawaited(_refuse(c, cliErrorMessage(null, MuxError.unsupportedRole)));
      return;
    }
    _admit(c, peer);
  }

  /// A5b D8: takes over a connection the daemon's `MuxServer` already
  /// handshook (role `cli`): same token gate, limits and back-pressure as
  /// a connection of this host's own listener. Synchronous, so no message
  /// read after the handshake is lost.
  void adopt(MuxConnection c, MuxPeerInfo peer) {
    if (_stopped) {
      unawaited(c.close());
      return;
    }
    _admit(c, peer);
  }

  void _admit(MuxConnection c, MuxPeerInfo peer) {
    final tokenOk = _isShellXShell(peer.token);
    final limited = !tokenOk && !_externalAllowed();
    if (_clients.length >= maxClients ||
        (limited && _clients.where((k) => k.limited).length >= maxLimited)) {
      unawaited(_refuse(c, cliErrorMessage(null, MuxError.busy)));
      return;
    }
    final client = _Client(
      this,
      c,
      tokenOk: tokenOk,
      limited: limited,
      staleToken: !tokenOk && (peer.token?.isNotEmpty ?? false),
      early: peer.early,
    );
    _clients.add(client);
    unawaited(
      c.done.whenComplete(() {
        _clients.remove(client);
        client.dispose();
      }),
    );
  }

  /// Constant time in the host token's length.
  bool _isShellXShell(String? token) {
    if (token == null || _token.isEmpty) return false;
    final given = utf8.encode(token);
    var diff = given.length ^ _token.length;
    for (var i = 0; i < _token.length; i++) {
      diff |= _token[i] ^ (i < given.length ? given[i] : 0);
    }
    return diff == 0;
  }

  bool _externalAllowed() {
    try {
      return _allowExternal();
    } on Object catch (e) {
      _log('cli allowExternal failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Sends a connection-ending answer, then closes (the transports deliver
  /// what was sent before a close).
  Future<void> _refuse(MuxConnection c, MuxMessage answer) async {
    _send(c, answer);
    await c.close();
  }

  /// One answer out. An answer the wire refuses (over 64 KiB, a value CBOR
  /// cannot carry) becomes `internal`; never throws.
  void _send(MuxConnection c, MuxMessage answer) {
    try {
      c.send(answer);
    } on Object catch (e) {
      _log('cli answer not sent: ${e.runtimeType}');
      try {
        c.send(
          cliErrorMessage(answer.q, MuxError.internal, 'answer too large'),
        );
      } on Object {
        unawaited(c.close());
      }
    }
  }

  /// A7 amendment: all a limited client may send.
  static bool _limitedMayAsk(MuxMessage m) =>
      m.type == CliType.apiVersion ||
      (m.type == CliType.cliNotify && m.fields['pane'] == null);

  /// One request → one answer (never throws).
  Future<MuxMessage> _answer(MuxMessage m, _Client client) async {
    final q = m.q;
    if (q == null) {
      return cliErrorMessage(null, MuxError.badRequest, 'request without q');
    }
    try {
      if (!CliType.allowedForCli(m.type)) {
        return cliErrorMessage(q, CliError.forbidden);
      }
      switch (m.type) {
        case CliType.apiVersion:
          return cliResult(q, {
            'api': kCliApi,
            'app': appVersion,
            'host': _hostKind(),
            'ui': _uiAttached(),
            'caps': kCliCaps,
          });
        case MuxType.daemonStatus:
          return cliResult(q, {
            'host': _hostKind(),
            'clients': _clients.length,
          });
        case CliType.cliNotify:
          return _notify(m);
        case CliType.cliEventsSubscribe:
          if (!_enabled()) return _disabled(q);
          final kinds = m.fields['kinds'];
          if (kinds != null &&
              (kinds is! List<Object?> || kinds.any((k) => k is! String))) {
            return cliErrorMessage(
              q,
              MuxError.badRequest,
              'kinds must be a list of strings',
            );
          }
          if (client.events == null && _listeners >= maxListeners) {
            return cliErrorMessage(q, MuxError.busy);
          }
          final wanted = kinds == null
              ? null
              : [...(kinds as List<Object?>).cast<String>()];
          client.subscribe(wanted?.toSet());
          return cliResult(q, {'kinds': ?wanted});
      }
      if (m.type.startsWith('ui.')) {
        if (!_enabled()) return _disabled(q);
        return cliResult(
          q,
          await _ui.handle(
            m,
            cancelled: client.connection.done,
            isGone: () => client._closed,
          ),
        );
      }
      return cliErrorMessage(q, MuxError.unknownType);
    } on CliFailure catch (f) {
      return cliErrorMessage(q, f.code, f.message);
    } on Object catch (e) {
      _log('cli request ${m.type} failed: ${e.runtimeType}');
      return cliErrorMessage(q, MuxError.internal);
    }
  }

  static MuxMessage _disabled(int? q) => cliErrorMessage(
    q,
    CliError.cliDisabled,
    'Command-line control is off in ShellX (tray → Command line)',
  );

  Future<MuxMessage> _notify(MuxMessage m) async {
    final rawBody = m.fields['body'];
    final rawTitle = m.fields['title'];
    final pane = m.fields['pane'];
    if (rawBody is! String) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'notify needs text');
    }
    final stripped = _stripControls(rawBody);
    if (stripped.trim().isEmpty) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'notify needs text');
    }
    if (rawTitle != null && rawTitle is! String) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'title must be text');
    }
    if (pane != null && pane is! int) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'pane must be a number');
    }
    final body = _clip(stripped, 1024);
    final title = rawTitle == null
        ? null
        : _clip(_stripControls(rawTitle as String), 128);
    if (pane is int) {
      return _ui.notifyPane(pane, title: title, body: body)
          ? cliResult(m.q)
          : cliErrorMessage(m.q, MuxError.notFound, 'no pane p$pane');
    }
    await _ui.notifyApp(title: title, body: body);
    return cliResult(m.q);
  }

  static String _stripControls(String s) =>
      s.replaceAll(RegExp('[\\x00-\\x1F\\x7F\\u0080-\\u009F]'), ' ');

  static String _clip(String s, int max) =>
      s.runes.length <= max ? s : String.fromCharCodes(s.runes.take(max));
}

final class _Client {
  _Client(
    this.host,
    this.connection, {
    required this.tokenOk,
    required this.limited,
    required this.staleToken,
    required List<MuxMessage> early,
  }) : _base = connection.pendingBytes {
    // Read with `auth`, before this listener: first, in order.
    early.forEach(_enqueue);
    _sub = connection.messages.listen(_enqueue);
  }

  /// D32: requests waiting on one connection (more → `busy`).
  static const _maxWaiting = 64;

  /// D32: unread answers past this stop request intake until they drain.
  static const _outputLimit = 256 * 1024;

  /// D24: events the client has not taken past this are dropped.
  static const _maxEventsWaiting = 1000;

  final CliHost host;
  final MuxConnection connection;

  /// Bytes the transport had pending when this client began (handshake).
  final int _base;

  /// Carried this launch's `SHELLX_CLI_TOKEN`.
  final bool tokenOk;

  /// Came in limited (no token, "Allow other terminals" off): counts
  /// against [CliHost.maxLimited] for as long as it stays.
  final bool limited;

  /// Carried a token that is not this launch's (final ruling M1).
  final bool staleToken;
  late final StreamSubscription<MuxMessage> _sub;
  Future<void> _chain = Future.value();
  StreamSubscription<Map<String, Object?>>? events;
  Set<String>? _kinds;
  bool _closed = false;
  bool _inputPaused = false;
  bool _watchingDrain = false;
  int _waiting = 0;
  int _dropped = 0;

  /// Bytes this client sent, as the transport counts them.
  int _sent = 0;

  /// Where each event not yet known to be taken ends, in the stream of
  /// bytes sent (the reader has taken it once it took that many).
  final _eventEnds = Queue<int>();

  /// A token-less client that used more than the limited API (while
  /// "Allow other terminals" was on).
  bool _usedFull = false;

  /// A ShellX shell, or "Allow other terminals" ticked right now
  /// (evaluated per request and per event: unticking applies at once).
  bool get full => tokenOk || host._externalAllowed();

  void _enqueue(MuxMessage m) {
    if (_closed) return;
    if (_waiting >= _maxWaiting) {
      _answer(cliErrorMessage(m.q, MuxError.busy, 'too many requests'));
      return;
    }
    _waiting++;
    // D32: requests on one connection run in order.
    _chain = _chain.then((_) async {
      try {
        await _outputRoom();
        if (_closed) return;
        if (!CliHost._limitedMayAsk(m)) {
          if (!full) {
            _revoke(m.q);
            return;
          }
          _usedFull = true;
        }
        final answer = await host._answer(m, this);
        if (!_closed) _answer(answer);
      } finally {
        _waiting--;
      }
    });
  }

  /// Waits while the client leaves more than [_outputLimit] unread.
  Future<void> _outputRoom() async {
    while (!_closed && connection.pendingBytes > _outputLimit) {
      await connection.drained;
    }
  }

  /// Limited client: `forbidden` with the tray hint, then close.
  void _revoke(int? q) {
    _closed = true;
    unawaited(
      host._refuse(
        connection,
        cliErrorMessage(
          q,
          CliError.forbidden,
          staleToken ? CliHost._earlierLaunch : CliHost._notAShellXShell,
        ),
      ),
    );
  }

  void _answer(MuxMessage answer) {
    _counted(() => host._send(connection, answer));
    _afterSend();
  }

  /// Runs [send] and adds what it queued to [_sent].
  void _counted(void Function() send) {
    final before = connection.pendingBytes;
    send();
    final queued = connection.pendingBytes - before;
    if (queued > 0) _sent += queued;
  }

  /// D24: events sent that the reader has not taken yet.
  int get _eventsWaiting {
    final taken = _base + _sent - connection.pendingBytes;
    while (_eventEnds.isNotEmpty && _eventEnds.first <= taken) {
      _eventEnds.removeFirst();
    }
    return _eventEnds.length;
  }

  void _afterSend() {
    if (!_inputPaused && connection.pendingBytes > _outputLimit) {
      _inputPaused = true;
      connection.pauseInput();
    }
    _watchDrain();
  }

  /// Once the client has taken everything: count events afresh, read
  /// requests again, report what was dropped.
  void _watchDrain() {
    if (_watchingDrain || _closed) return;
    if (connection.pendingBytes == 0) {
      _drained();
      return;
    }
    _watchingDrain = true;
    unawaited(
      connection.drained.then((_) {
        _watchingDrain = false;
        _watchDrain();
      }),
    );
  }

  void _drained() {
    _eventEnds.clear();
    if (_inputPaused) {
      _inputPaused = false;
      connection.resumeInput();
    }
    _reportDropped();
  }

  /// One `overflow{dropped}` once there is room again.
  void _reportDropped() {
    if (_dropped == 0 || events == null) return;
    final dropped = _dropped;
    _dropped = 0;
    _event({'kind': 'overflow', 'dropped': dropped});
  }

  /// See [CliHost.recheck].
  void recheck({required bool enabled}) {
    if (_closed) return;
    if (!tokenOk && (_usedFull || events != null) && !full) {
      _revoke(null);
      return;
    }
    if (!enabled && events != null) _endSubscription();
  }

  /// D26: the switch ends the subscription; the connection stays.
  void _endSubscription() {
    _unsubscribe();
    _answer(CliHost._disabled(null));
  }

  /// A second subscribe replaces the filter.
  void subscribe(Set<String>? kinds) {
    _kinds = kinds;
    if (events != null) return;
    host._listeners++;
    events = host._ui.events().listen(_onEvent);
  }

  void _onEvent(Map<String, Object?> e) {
    if (_closed) return;
    if (!full) {
      _revoke(null);
      return;
    }
    if (!host._enabled()) {
      _endSubscription();
      return;
    }
    final kinds = _kinds;
    if (kinds != null && !kinds.contains(e['kind'])) return;
    // Room for the overflow notice and this event.
    if (_eventsWaiting + (_dropped > 0 ? 1 : 0) >= _maxEventsWaiting) {
      _dropped++;
      return;
    }
    _reportDropped();
    _event(e);
  }

  /// An event the wire refuses is dropped (never throws into the UI).
  void _event(Map<String, Object?> fields) {
    _counted(() {
      try {
        connection.send(MuxMessage(CliType.event, fields: fields));
      } on Object catch (e) {
        host._log('cli event not sent: ${e.runtimeType}');
      }
    });
    _eventEnds.add(_base + _sent);
    _afterSend();
  }

  void _unsubscribe() {
    final sub = events;
    if (sub == null) return;
    events = null;
    _kinds = null;
    _dropped = 0;
    host._listeners--;
    unawaited(sub.cancel());
  }

  void dispose() {
    _closed = true;
    unawaited(_sub.cancel());
    _unsubscribe();
  }
}
