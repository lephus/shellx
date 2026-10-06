import 'dart:async';
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
/// `allowExternal()` ("Allow other terminals") is on when it connects, gets
/// the full API. Any other client is *limited*: it may send `api.version`
/// and a pane-less `cli.notify`; anything else is `forbidden` and closes
/// the connection.
///
/// D32: at most [maxClients] authenticated clients and four handshakes at
/// once; one connection's requests run in order; [maxListeners] event
/// subscribers. D24: each subscriber has at most 1000 events queued — the
/// count covers what the event loop has not handed to the transport yet; a
/// real socket's write buffer is the remaining back-pressure.
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
    this.maxListeners = 4,
    void Function(String message)? log,
  }) : _transport = transport,
       _file = endpointFile,
       _ui = ui,
       _enabled = enabled,
       _token = utf8.encode(token),
       _allowExternal = allowExternal,
       _log = log ?? ((_) {});

  final String address;
  final String appVersion;
  final int maxClients;
  final int maxListeners;
  final MuxTransport _transport;
  final MuxEndpointFile _file;
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

  Future<void> start() async {
    final r = Random.secure();
    _secret = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    _instance = List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _listener = await _transport.listen(address);
    _accept = _listener!.connections.listen((c) => unawaited(_onConnection(c)));
    _written = await _file.write(
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
    if (written != null) await _file.deleteIfOwned(written);
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
    if (_clients.length >= maxClients) {
      unawaited(_refuse(c, cliErrorMessage(null, MuxError.busy)));
      return;
    }
    final client = _Client(
      this,
      c,
      full: _isShellXShell(peer.token) || _externalAllowed(),
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

  /// Sends a connection-ending answer, then closes.
  Future<void> _refuse(MuxConnection c, MuxMessage answer) async {
    _send(c, answer);
    await _closeAfterSend(c);
  }

  /// Lets a frame just sent leave before the close: the memory transport
  /// drops frames still in flight when a side closes (sockets flush on
  /// close themselves).
  static Future<void> _closeAfterSend(MuxConnection c) async {
    await Future<void>.delayed(Duration.zero);
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
            'host': 'ui',
            'ui': true,
            'caps': kCliCaps,
          });
        case MuxType.daemonStatus:
          return cliResult(q, {'host': 'ui', 'clients': _clients.length});
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
          client.subscribe(
            kinds == null ? null : {...(kinds as List<Object?>).cast<String>()},
          );
          return cliResult(q);
      }
      if (m.type.startsWith('ui.')) {
        if (!_enabled()) return _disabled(q);
        return cliResult(
          q,
          await _ui.handle(m, cancelled: client.connection.done),
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

  static MuxMessage _disabled(int q) => cliErrorMessage(
    q,
    CliError.cliDisabled,
    'Command-line control is off in ShellX (tray → Command line)',
  );

  Future<MuxMessage> _notify(MuxMessage m) async {
    final rawBody = m.fields['body'];
    final rawTitle = m.fields['title'];
    final pane = m.fields['pane'];
    if (rawBody is! String || rawBody.trim().isEmpty) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'notify needs text');
    }
    if (rawTitle != null && rawTitle is! String) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'title must be text');
    }
    if (pane != null && pane is! int) {
      return cliErrorMessage(m.q, MuxError.badRequest, 'pane must be a number');
    }
    final body = _clip(_stripControls(rawBody), 1024);
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
    required this.full,
    required List<MuxMessage> early,
  }) {
    // Read with `auth`, before this listener: first, in order.
    early.forEach(_enqueue);
    _sub = connection.messages.listen(_enqueue);
  }

  final CliHost host;
  final MuxConnection connection;

  /// A ShellX shell (token) or "Allow other terminals": the whole API.
  final bool full;
  late final StreamSubscription<MuxMessage> _sub;
  Future<void> _chain = Future.value();
  StreamSubscription<Map<String, Object?>>? events;
  bool _closed = false;
  int _queued = 0;
  int _dropped = 0;

  void _enqueue(MuxMessage m) {
    // D32: requests on one connection run in order.
    _chain = _chain.then((_) async {
      if (_closed) return;
      if (!full && !CliHost._limitedMayAsk(m)) {
        _closed = true;
        await host._refuse(
          connection,
          cliErrorMessage(m.q, CliError.forbidden, CliHost._notAShellXShell),
        );
        return;
      }
      final answer = await host._answer(m, this);
      if (!_closed) host._send(connection, answer);
    });
  }

  void subscribe(Set<String>? kinds) {
    if (events != null) return;
    host._listeners++;
    events = host._ui.events().listen((e) {
      if (_closed) return;
      if (kinds != null && !kinds.contains(e['kind'])) return;
      if (_queued >= 1000) {
        _dropped++;
        return;
      }
      if (_dropped > 0) {
        _event({'kind': 'overflow', 'dropped': _dropped});
        _dropped = 0;
      }
      _queued++;
      _event(e);
      scheduleMicrotask(() => _queued--);
    });
  }

  /// An event the wire refuses is dropped (never throws into the UI).
  void _event(Map<String, Object?> fields) {
    try {
      connection.send(MuxMessage(CliType.event, fields: fields));
    } on Object catch (e) {
      host._log('cli event not sent: ${e.runtimeType}');
    }
  }

  void dispose() {
    _closed = true;
    unawaited(_sub.cancel());
    if (events != null) {
      host._listeners--;
      unawaited(events!.cancel());
    }
  }
}
