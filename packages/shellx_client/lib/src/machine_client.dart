import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_tab.dart';
import 'client_types.dart';

/// A `session.open` waiting for its answer. `session.open` has no request
/// id: the agent answers requests in order, so answers are matched to the
/// oldest entry.
final class _PendingOpen {
  _PendingOpen(this.cols, this.rows);
  final int cols;
  final int rows;
  final completer = Completer<ClientTab>();

  /// Timed out: nobody waits any more, but the entry keeps its place so a
  /// late answer is not taken for a newer open's.
  bool abandoned = false;
}

/// A `session.list` waiting for its answer (matched in order, like opens).
final class _PendingList {
  _PendingList({this.retires = const [], this.abandoned = false});
  final completer = Completer<List<SessionInfo>>();

  /// Abandoned opens this list was sent after: the agent answers in order,
  /// so one still unanswered when this list's answer arrives never will be.
  final List<_PendingOpen> retires;

  /// Nobody waits for the answer (timed out, or sent only to retire opens).
  bool abandoned;
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
    required Future<void>? Function() pairing,
  }) : _relay = relay,
       _deviceId = deviceId,
       _identity = identity,
       _hello = hello,
       _timeout = timeout,
       _pinnedKey = pinnedKey,
       _forgetPin = forgetPin,
       _pairing = pairing;

  final String agentId;
  final RelayConnection _relay;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final Hs1Payload _hello;
  final Duration _timeout;
  final Uint8List? Function() _pinnedKey;
  final Future<void> Function() _forgetPin;

  /// While the phone is pairing with this agent: completes when that is
  /// over (see [ClientService.pair]); null otherwise.
  final Future<void>? Function() _pairing;

  MachineConnectionState _state = const MachineIdle();
  final _states = StreamController<MachineConnectionState>.broadcast();
  Future<void>? _connecting;
  ({ChannelId channel, Completer<Uint8List?> reply})? _handshake;
  ChannelId? _channelId;
  SecureChannel? _secure;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  /// A resume is running; [_resumeAgain] asks it for one more pass.
  bool _resuming = false;
  bool _resumeAgain = false;

  final _tabs = <int, ClientTab>{};

  /// Tabs opened or (re-)attached on the current channel; cleared when it
  /// is lost. An attached tab missing here is stale: the agent does not
  /// send it anything until it is re-attached.
  final _attachedHere = <ClientTab>{};

  /// Sessions whose attached tab was closed while there was no channel:
  /// their `session.close` goes out first thing on the next channel.
  final _pendingCloses = <int>{};
  final _pendingOpens = <_PendingOpen>[];
  final _pendingLists = <_PendingList>[];

  /// Per session id, in the order the `session.attach` messages were sent.
  final _pendingAttaches = <int, List<Completer<void>>>{};
  var _known = <int, SessionInfo>{};

  /// Bumped by every channel loss: a handshake that saw one while in
  /// flight must not install its channel.
  int _losses = 0;

  /// Bumped by [dropChannel] when there is no live channel: a handshake
  /// whose HS1 went out before must not install its channel either (the
  /// agent may have replaced it), and starts over on a new channel id.
  int _drops = 0;

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
    final pending = _PendingList();
    _pendingLists.add(pending);
    return _request(
      pending.completer,
      const SessionList(),
      () => _pendingLists.remove(pending),
      abandon: () => pending.abandoned = true,
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
      abandon: () => _abandonOpen(pending),
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
        _attachedHere.remove(tab);
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

  /// Removes the tab. An attached tab also closes its session on the agent:
  /// at once, or with no channel on the next one (asked for now when the
  /// relay is up, else when it is back). A detached or ended tab is only
  /// removed locally.
  Future<void> closeTab(int id) async {
    final tab = _tabs.remove(id);
    if (tab == null) return;
    _attachedHere.remove(tab);
    final wasAttached = tab.isAttached;
    tab.dispose();
    if (!wasAttached) return;
    if (_send([SessionClose(id: id)])) {
      await _outbox;
      return;
    }
    // Otherwise the session would run unattached until closed from the
    // tray, counting toward the agent's session limit.
    _pendingCloses.add(id);
    if (_relay.state == RelayConnectionState.connected) unawaited(_resume());
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

  /// The phone's relay connection is back: re-handshake and re-attach.
  @internal
  void relayConnected() {
    _inbox = _inbox.then((_) => unawaited(_resume())).catchError((Object _) {});
  }

  /// The agent may no longer hold this phone's channel (a `pairing_removed`
  /// event, or a pairing handshake may have replaced it). After the frames
  /// received before this call, a live channel is dropped, and a handshake
  /// in flight starts over on a new channel id instead of installing its
  /// channel; then the open tabs resume, so the agent is asked again at
  /// once. The pin and the tabs stay, as on any channel loss. The returned
  /// future completes once the drop is done.
  @internal
  Future<void> dropChannel() {
    return _inbox = _inbox
        .then((_) {
          if (_secure != null) {
            _channelLost();
          } else {
            _drops++;
          }
          unawaited(_resume());
        })
        .catchError((Object _) {});
  }

  /// Unpaired: forget the channel and every tab without touching sessions.
  @internal
  void shutdown() {
    _channelLost();
    _pendingCloses.clear();
    for (final tab in _tabs.values) {
      tab.dispose();
    }
    _tabs.clear();
  }

  /// Never leaves the state at [MachineConnecting]: an unexpected error
  /// fails the handshake with `timeout`, like an answer that never comes.
  /// A handshake voided by [dropChannel], or that waited for a pairing,
  /// starts over; each restart needs a new drop or pairing, so this cannot
  /// spin.
  Future<void> _handshakeNow() async {
    final losses = _losses; // A loss from here on voids this attempt.
    try {
      while (!await _handshakeSteps(losses)) {}
    } on MachineConnectionException {
      rethrow;
    } catch (_) {
      _fail(MachineConnectionFailure.timeout);
    }
  }

  /// One IK handshake on a new channel id: true once its channel is
  /// installed, false when it must start over.
  Future<bool> _handshakeSteps(int losses) async {
    if (losses != _losses) _failLost(); // Lost while waiting for a pairing.
    final key = _pinnedKey();
    if (key == null || key.length != 32) {
      await _untrusted(); // An unusable pin is as good as none.
    }
    // Throws FormatException for a malformed id: before MachineConnecting.
    final prologue = buildPrologue(
      agentDeviceId: agentId,
      mobileDeviceId: _deviceId,
    );
    if (_state is! MachineConnecting) _setState(const MachineConnecting());
    final handshake = NoiseHandshake.initiator(
      pattern: NoisePattern.ik,
      localStatic: _identity,
      remoteStatic: key,
      prologue: prologue,
    );
    final hello = await handshake.writeMessage(_hello.encode());
    // Never while pairing with this agent: between the pairing's HS1 and
    // pair.confirm this HS1 would replace the pairing channel on the agent,
    // which would then ignore the confirm. Once the pairing is over, start
    // again: it may have changed the pin, or the machine may be gone.
    final pairing = _pairing();
    if (pairing != null) {
      await pairing;
      return false;
    }
    final channel = ChannelId.random();
    final reply = Completer<Uint8List?>();
    _handshake = (channel: channel, reply: reply);
    final drops = _drops; // A drop from here on voids this channel.
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
      await _untrusted(); // Spec §12: untrusted → drop the pinned key.
    }
    if (losses != _losses) _failLost(); // Lost while in flight.
    if (drops != _drops) return false; // The agent may have replaced it.
    _channelId = channel;
    _secure = SecureChannel(handshake.split());
    _sendPendingCloses();
    _setState(const MachineReady());
    // Whoever asked for this channel, stale tabs re-attach on it.
    unawaited(_resume());
    return true;
  }

  /// The agent does not trust this phone (or there is no usable pin):
  /// forget the pin and end every attached tab, which can never re-attach,
  /// so later reconnects and PRESENCE leave this machine alone.
  Future<Never> _untrusted() async {
    await _forgetPinQuietly();
    for (final tab in _tabs.values.where((t) => t.isAttached).toList()) {
      tab.handleError(
        AppErrorCode.sessionNotFound,
        'This machine no longer trusts this phone',
      );
    }
    _fail(MachineConnectionFailure.untrusted);
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
          // Spec §6.3: any decrypt error drops the channel — if still ours.
          if (identical(secure, _secure)) {
            _channelLost();
            unawaited(_resume());
          }
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
        if (online) {
          // The hub announces a device only when it connects, and an agent
          // that (re)connects has dropped every channel: a live channel is
          // stale even without an offline first (its socket was replaced).
          if (_secure != null) _channelLost();
          unawaited(_resume()); // Never awaited here: it waits for HS2.
        } else {
          _channelLost();
        }
      case EventFrame():
        break;
    }
  }

  void _dispatch(AppMessage message) {
    switch (message) {
      case SessionListResult(:final sessions):
        _known = {for (final s in sessions) s.id: s};
        if (_pendingLists.isEmpty) return;
        final pending = _pendingLists.removeAt(0);
        pending.retires.forEach(_pendingOpens.remove);
        if (!pending.abandoned) pending.completer.complete(sessions);
      case SessionOpened(:final id, :final index, :final shell):
        final pending = _pendingOpens.isEmpty
            ? null
            : _pendingOpens.removeAt(0);
        if (pending == null || pending.abandoned) {
          // Nobody waits for this session (its open timed out): close it
          // instead of leaving it attached to this phone, where it would
          // stall its send window and count toward the session limit.
          _send([SessionClose(id: id)]);
          return;
        }
        final tab = ClientTab(
          id: id,
          index: index,
          shell: shell,
          cols: pending.cols,
          rows: pending.rows,
          sendAck: _sendAck,
        );
        _tabs[id] = tab;
        _attachedHere.add(tab);
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
          // session_limit or spawn_failed: the answer to the oldest open.
          if (_pendingOpens.isEmpty) return;
          final pending = _pendingOpens.removeAt(0);
          if (!pending.abandoned) pending.completer.completeError(error);
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
    if (_secure != null) _attachedHere.add(tab); // Sent on this channel.
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
  /// `timeout` after the handshake timeout (calling [abandon] instead of
  /// [forget] when given: the reply may still come) and with `agentOffline`
  /// when there is no channel (or it is lost before the reply).
  Future<T> _request<T>(
    Completer<T> completer,
    AppMessage message,
    void Function() forget, {
    void Function()? abandon,
  }) {
    if (!_send([message])) {
      forget();
      return Future.error(
        const MachineConnectionException(MachineConnectionFailure.agentOffline),
      );
    }
    return completer.future.timeout(
      _timeout,
      onTimeout: () {
        (abandon ?? forget)();
        throw const MachineConnectionException(
          MachineConnectionFailure.timeout,
        );
      },
    );
  }

  /// [open] timed out on a live channel (a loss would have failed it
  /// first). Its entry stays, so its answer, if it comes, is closed rather
  /// than taken for a newer open's. The agent sends none when the host
  /// closed every session while the shell was starting, so a
  /// `session.list` goes out now: once it is answered, every earlier
  /// request has been, and the entry is dropped.
  void _abandonOpen(_PendingOpen open) {
    open.abandoned = true;
    final barrier = _PendingList(retires: [open], abandoned: true);
    _pendingLists.add(barrier);
    if (!_send([const SessionList()])) {
      _pendingLists.remove(barrier);
      _pendingOpens.remove(open);
    }
  }

  /// Re-handshake and re-attach every stale tab (still attached, i.e. not
  /// taken over, exited or ended, but not on the current channel) with
  /// `last_seq = received`, one at a time; a pending `session.close` also
  /// needs the handshake (it is sent on install). A call while a resume
  /// runs (the channel was lost again during its attaches) makes that
  /// resume do one more pass. Only ever triggered by an event (relay back,
  /// PRESENCE online, decrypt error, a dropped channel, a new channel
  /// installed by anyone, a tab closed with no channel), so an agent that
  /// stays offline costs one handshake per event.
  Future<void> _resume() async {
    if (_resuming) {
      _resumeAgain = true;
      return;
    }
    _resuming = true;
    try {
      do {
        _resumeAgain = false;
        await _resumeOnce();
      } while (_resumeAgain);
    } finally {
      _resuming = false;
    }
  }

  Future<void> _resumeOnce() async {
    if (_pinnedKey() == null) return; // Untrusted or unpaired: nothing to do.
    if (!_tabs.values.any(_isStale) && _pendingCloses.isEmpty) return;
    try {
      await connect(); // Joins a handshake the app already started.
      // Tabs opened or attached on this channel since are not stale.
      for (final tab in _tabs.values.where(_isStale).toList()) {
        if (!_isStale(tab) || !identical(_tabs[tab.id], tab)) continue;
        try {
          await _attach(tab);
        } on AppErrorException {
          // The tab already received TabError (session_not_found).
        } on MachineConnectionException {
          if (_secure == null) rethrow; // The channel is gone: pass over.
          // A slow answer on a live channel: the agent has the attach (it
          // answers after replaying up to 256 KiB); go on with the next.
        }
      }
    } on MachineConnectionException {
      // MachineFailed, or the channel was lost again: the next event (or
      // the pass that loss asked for) retries.
    }
  }

  /// Attached as far as the phone knows, but not on the current channel.
  bool _isStale(ClientTab tab) =>
      tab.isAttached && !_attachedHere.contains(tab);

  /// On a new channel: `session.close` for the tabs closed while there was
  /// none, before anything else is sent on it.
  void _sendPendingCloses() {
    if (_pendingCloses.isEmpty) return;
    _send([for (final id in _pendingCloses) SessionClose(id: id)]);
    _pendingCloses.clear();
  }

  void _channelLost() {
    _losses++;
    _attachedHere.clear();
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
      if (!pending.abandoned) pending.completer.completeError(lost);
    }
    for (final pending in lists) {
      if (!pending.abandoned) pending.completer.completeError(lost);
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
