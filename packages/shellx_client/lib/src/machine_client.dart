import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_tab.dart';
import 'client_types.dart';

final class _PendingOpen {
  _PendingOpen(this.cols, this.rows);
  final int cols;
  final int rows;
  final completer = Completer<ClientTab>();
}

/// The phone's connection to one pinned machine: IK handshake, request /
/// response over the encrypted channel, and the machine's tabs.
///
/// Created by [ClientService.machine]; frames for this agent are routed to
/// it by the service.
final class MachineClient {
  @internal
  MachineClient({
    required this.agentId,
    required RelayConnection relay,
    required String deviceId,
    required NoiseKeyPair identity,
    required Hs1Payload hello,
    required Duration timeout,
    required Uint8List? Function() pinnedKey,
    required Future<void> Function() forgetPin,
  }) : _relay = relay,
       _deviceId = deviceId,
       _identity = identity,
       _hello = hello,
       _timeout = timeout,
       _pinnedKey = pinnedKey,
       _forgetPin = forgetPin;

  final String agentId;
  final RelayConnection _relay;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final Hs1Payload _hello;
  final Duration _timeout;
  final Uint8List? Function() _pinnedKey;
  final Future<void> Function() _forgetPin;

  MachineConnectionState _state = const MachineIdle();
  final _states = StreamController<MachineConnectionState>.broadcast();
  Future<void>? _connecting;
  ({ChannelId channel, Completer<Uint8List?> reply})? _handshake;
  ChannelId? _channelId;
  SecureChannel? _secure;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  final _tabs = <int, ClientTab>{};
  final _pendingOpens = <_PendingOpen>[];
  final _pendingLists = <Completer<List<SessionInfo>>>[];

  /// Per session id, in the order the `session.attach` messages were sent.
  final _pendingAttaches = <int, List<Completer<void>>>{};
  var _known = <int, SessionInfo>{};

  /// Bumped by every channel loss: a handshake that saw one while in
  /// flight must not install its channel.
  int _losses = 0;

  MachineConnectionState get state => _state;

  Stream<MachineConnectionState> get states => _states.stream;

  List<ClientTab> get tabs => List.unmodifiable(_tabs.values);

  /// IK handshake with the pinned key. Throws [MachineConnectionException]
  /// and moves to [MachineFailed] on failure; no-op when already ready.
  Future<void> connect() {
    if (_state is MachineReady) return Future.value();
    return _connecting ??= _handshakeNow().whenComplete(
      () => _connecting = null,
    );
  }

  Future<List<SessionInfo>> listSessions() async {
    await connect();
    final completer = Completer<List<SessionInfo>>();
    _pendingLists.add(completer);
    return _request(
      completer,
      const SessionList(),
      () => _pendingLists.remove(completer),
    );
  }

  /// Opens a new session. Throws [AppErrorException] (`session_limit`,
  /// `spawn_failed`) or [MachineConnectionException].
  Future<ClientTab> openSession({required int cols, required int rows}) async {
    await connect();
    final pending = _PendingOpen(cols, rows);
    _pendingOpens.add(pending);
    return _request(
      pending.completer,
      SessionOpen(cols: cols, rows: rows),
      () => _pendingOpens.remove(pending),
    );
  }

  /// Attaches to an existing session (from [listSessions]) or re-attaches an
  /// existing tab. Throws [AppErrorException] with `session_not_found` when
  /// the session no longer exists.
  Future<ClientTab> attach(
    int id, {
    required int cols,
    required int rows,
  }) async {
    await connect();
    var tab = _tabs[id];
    var isNew = false;
    if (tab == null) {
      final info =
          _known[id] ??
          (await listSessions()).where((s) => s.id == id).firstOrNull;
      if (info == null) {
        throw AppErrorException(
          AppErrorCode.sessionNotFound,
          'Session $id not found',
        );
      }
      // Another attach may have created the tab while the list was loading.
      tab = _tabs[id];
      if (tab == null) {
        isNew = true;
        tab = ClientTab(
          id: id,
          index: info.index,
          shell: info.shell,
          cols: cols,
          rows: rows,
          sendAck: _sendAck,
        );
        _tabs[id] = tab;
      }
    }
    tab.updateSize(cols, rows);
    try {
      await _attach(tab);
    } catch (_) {
      if (isNew && identical(_tabs[id], tab)) {
        _tabs.remove(id);
        tab.dispose();
      }
      rethrow;
    }
    return tab;
  }

  /// Sends keystrokes; data larger than 16 KiB is split into several
  /// `input` messages. Dropped while the channel is down.
  void input(int id, Uint8List data) {
    final tab = _tabs[id];
    if (tab == null || !tab.isAttached || _secure == null) return;
    for (var offset = 0; offset < data.length; offset += kMaxOutputChunk) {
      final end = min(offset + kMaxOutputChunk, data.length);
      _send([InputMessage(id: id, data: data.sublist(offset, end))]);
    }
  }

  /// Ignored when [cols] or [rows] is below 1 (keyboard animating, rotation).
  void resize(int id, int cols, int rows) {
    if (cols < 1 || rows < 1) return;
    final tab = _tabs[id];
    if (tab == null) return;
    tab.updateSize(cols, rows);
    if (!tab.isAttached || _secure == null) return;
    _send([ResizeMessage(id: id, cols: cols, rows: rows)]);
  }

  /// Removes the tab. An attached tab also closes its session on the agent;
  /// a detached or ended tab is only removed locally.
  Future<void> closeTab(int id) async {
    final tab = _tabs.remove(id);
    if (tab == null) return;
    final wasAttached = tab.isAttached;
    tab.dispose();
    if (wasAttached && _send([SessionClose(id: id)])) await _outbox;
  }

  /// Routed here by [ClientService]: DATA from this agent, ERROR and
  /// PRESENCE about it.
  @internal
  void handleFrame(RelayFrame frame) {
    _inbox = _inbox.then((_) => _onFrame(frame)).catchError((Object _) {});
  }

  /// The phone's relay connection dropped: the channel is gone.
  @internal
  void relayLost() {
    _inbox = _inbox.then((_) => _channelLost()).catchError((Object _) {});
  }

  /// Unpaired: forget the channel and every tab without touching sessions.
  @internal
  void shutdown() {
    _channelLost();
    for (final tab in _tabs.values) {
      tab.dispose();
    }
    _tabs.clear();
  }

  Future<void> _handshakeNow() async {
    final key = _pinnedKey();
    if (key == null || key.length != 32) {
      await _forgetPinQuietly(); // An unusable pin is as good as none.
      _fail(MachineConnectionFailure.untrusted);
    }
    _setState(const MachineConnecting());
    final handshake = NoiseHandshake.initiator(
      pattern: NoisePattern.ik,
      localStatic: _identity,
      remoteStatic: key,
      prologue: buildPrologue(
        agentDeviceId: agentId,
        mobileDeviceId: _deviceId,
      ),
    );
    final hello = await handshake.writeMessage(_hello.encode());
    final channel = ChannelId.random();
    final reply = Completer<Uint8List?>();
    final losses = _losses;
    _handshake = (channel: channel, reply: reply);
    final sent = _relay.send(
      DataFrame(
        peer: agentId,
        channel: channel,
        payload: ChannelPayload(PayloadKind.hs1Ik, hello).encode(),
      ),
    );
    Uint8List? message;
    try {
      if (!sent) _fail(MachineConnectionFailure.timeout);
      message = await reply.future.timeout(_timeout);
    } on TimeoutException {
      _fail(MachineConnectionFailure.timeout);
    } finally {
      _handshake = null;
    }
    // Null: ERROR peer_offline, or the agent or the relay went away.
    if (message == null) _failLost();
    final Hs2Payload answer;
    try {
      answer = Hs2Payload.decode(await handshake.readMessage(message));
    } on FormatException {
      _fail(MachineConnectionFailure.protocolUnsupported);
    } catch (_) {
      _fail(MachineConnectionFailure.timeout); // Undecryptable: like no answer.
    }
    if (answer.proto != kAppProtocolVersion ||
        answer.status == HandshakeStatus.protoUnsupported) {
      _fail(MachineConnectionFailure.protocolUnsupported);
    }
    if (answer.status != HandshakeStatus.ok) {
      await _forgetPinQuietly(); // Spec §12: untrusted → drop the pinned key.
      _fail(MachineConnectionFailure.untrusted);
    }
    if (losses != _losses) _failLost(); // Lost after HS2 arrived.
    _channelId = channel;
    _secure = SecureChannel(handshake.split());
    _setState(const MachineReady());
  }

  Future<void> _forgetPinQuietly() async {
    try {
      await _forgetPin();
    } catch (_) {
      // The pin is already gone from memory; storage errors change nothing.
    }
  }

  Never _fail(MachineConnectionFailure failure) {
    _setState(MachineFailed(failure));
    throw MachineConnectionException(failure);
  }

  /// The handshake lost its way to the agent: `timeout` when the relay is
  /// not connected (as when HS1 cannot be sent), else `agentOffline`.
  Never _failLost() => _fail(
    _relay.state == RelayConnectionState.connected
        ? MachineConnectionFailure.agentOffline
        : MachineConnectionFailure.timeout,
  );

  Future<void> _onFrame(RelayFrame frame) async {
    switch (frame) {
      case DataFrame(:final channel, :final payload):
        final ChannelPayload decoded;
        try {
          decoded = ChannelPayload.decode(payload);
        } on FrameFormatException {
          return;
        }
        if (decoded.kind == PayloadKind.hs2) {
          final pending = _handshake;
          if (pending != null &&
              pending.channel == channel &&
              !pending.reply.isCompleted) {
            pending.reply.complete(decoded.noiseMessage);
          }
          return;
        }
        final secure = _secure;
        if (decoded.kind != PayloadKind.transport ||
            secure == null ||
            channel != _channelId) {
          return;
        }
        final List<AppMessage> messages;
        try {
          messages = await secure.open(decoded.noiseMessage);
        } catch (_) {
          _channelLost(); // Spec §6.3: any decrypt error drops the channel.
          return;
        }
        if (!identical(secure, _secure)) return;
        messages.forEach(_dispatch);
      case ErrorFrame(:final code, :final channel):
        if (code != RelayErrorCode.peerOffline) return;
        final pending = _handshake;
        if (pending != null &&
            pending.channel == channel &&
            !pending.reply.isCompleted) {
          pending.reply.complete(null);
        } else if (channel == _channelId) {
          _channelLost();
        }
      case PresenceFrame(:final online):
        if (!online) _channelLost();
      case EventFrame():
        break;
    }
  }

  void _dispatch(AppMessage message) {
    switch (message) {
      case SessionListResult(:final sessions):
        _known = {for (final s in sessions) s.id: s};
        if (_pendingLists.isNotEmpty) {
          _pendingLists.removeAt(0).complete(sessions);
        }
      case SessionOpened(:final id, :final index, :final shell):
        if (_pendingOpens.isEmpty) return;
        final pending = _pendingOpens.removeAt(0);
        final tab = ClientTab(
          id: id,
          index: index,
          shell: shell,
          cols: pending.cols,
          rows: pending.rows,
          sendAck: _sendAck,
        );
        _tabs[id] = tab;
        pending.completer.complete(tab);
      case SessionAttached(:final id):
        _takeAttach(id)?.complete();
      case SessionReset(:final id):
        _tabs[id]?.handleReset();
      case OutputMessage(:final id, :final seq, :final data):
        _tabs[id]?.handleOutput(seq, data);
      case SessionExited(:final id, :final exitCode):
        _tabs[id]?.handleExited(exitCode);
      case SessionDetached(:final id, :final reason):
        _tabs[id]?.handleDetached(reason);
      case ErrorMessage(:final code, :final message, :final id):
        final error = AppErrorException(code, message);
        if (id == null) {
          if (_pendingOpens.isNotEmpty) {
            _pendingOpens.removeAt(0).completer.completeError(error);
          }
          return;
        }
        _takeAttach(id)?.completeError(error);
        _tabs[id]?.handleError(code, message);
      default:
        break;
    }
  }

  Future<void> _attach(ClientTab tab) {
    tab.beginAttach();
    final done = Completer<void>();
    final id = tab.id;
    (_pendingAttaches[id] ??= []).add(done);
    return _request(
      done,
      SessionAttach(
        id: id,
        cols: tab.cols,
        rows: tab.rows,
        lastSeq: tab.received,
      ),
      () {
        final queue = _pendingAttaches[id];
        if (queue != null && queue.remove(done) && queue.isEmpty) {
          _pendingAttaches.remove(id);
        }
      },
    );
  }

  /// The oldest pending attach of session [id], removed from its queue.
  Completer<void>? _takeAttach(int id) {
    final queue = _pendingAttaches[id];
    if (queue == null) return null;
    final first = queue.removeAt(0);
    if (queue.isEmpty) _pendingAttaches.remove(id);
    return first;
  }

  /// Sends [message] and waits for its reply on [completer], already queued
  /// by the caller; [forget] removes it from that queue again. Fails with
  /// `timeout` after the handshake timeout and with `agentOffline` when
  /// there is no channel (or it is lost before the reply).
  Future<T> _request<T>(
    Completer<T> completer,
    AppMessage message,
    void Function() forget,
  ) {
    if (!_send([message])) {
      forget();
      return Future.error(
        const MachineConnectionException(MachineConnectionFailure.agentOffline),
      );
    }
    return completer.future.timeout(
      _timeout,
      onTimeout: () {
        forget();
        throw const MachineConnectionException(
          MachineConnectionFailure.timeout,
        );
      },
    );
  }

  void _channelLost() {
    _losses++;
    final handshake = _handshake;
    if (handshake != null && !handshake.reply.isCompleted) {
      handshake.reply.complete(null); // Fails the handshake now.
    }
    _secure = null;
    _channelId = null;
    const lost = MachineConnectionException(
      MachineConnectionFailure.agentOffline,
    );
    final opens = List.of(_pendingOpens);
    final lists = List.of(_pendingLists);
    final attaches = [for (final queue in _pendingAttaches.values) ...queue];
    _pendingOpens.clear();
    _pendingLists.clear();
    _pendingAttaches.clear();
    for (final pending in opens) {
      pending.completer.completeError(lost);
    }
    for (final pending in lists) {
      pending.completeError(lost);
    }
    for (final pending in attaches) {
      pending.completeError(lost);
    }
    if (_state is MachineReady) _setState(const MachineIdle());
  }

  void _sendAck(AckMessage ack) => _send([ack]);

  /// Seals and sends [messages] after everything sent before; false (nothing
  /// queued) when there is no channel. A batch that cannot be sealed or sent
  /// drops the channel: its nonce is spent, so the agent could not decrypt
  /// anything that follows it.
  bool _send(List<AppMessage> messages) {
    final secure = _secure;
    final channel = _channelId;
    if (secure == null || channel == null) return false;
    _outbox = _outbox
        .then((_) async {
          final payload = await secure.seal(messages);
          if (!identical(secure, _secure)) return;
          final sent = _relay.send(
            DataFrame(peer: agentId, channel: channel, payload: payload),
          );
          if (!sent) _channelLost();
        })
        .catchError((Object _) {
          if (identical(secure, _secure)) _channelLost();
        });
    return true;
  }

  void _setState(MachineConnectionState state) {
    _state = state;
    _states.add(state);
  }
}
