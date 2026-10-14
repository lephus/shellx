import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';

/// A request of the AI session failed on the computer (`ai.result` with
/// [code]: `stale`, `refused`, `queue_full`, `too_large`, `busy`,
/// `not_found`, `unavailable`, or a newer word). It also ends a request that
/// was in flight when the computer closed the session (`not_found` for a tab
/// that closed, `unavailable` when the window quit): no `ai.result` comes
/// then.
final class AiRequestException implements Exception {
  const AiRequestException(this.code);
  final String code;

  @override
  String toString() => 'AiRequestException($code)';
}

enum AiLinkState {
  /// Waiting for the snapshot (first attach, or after a channel loss).
  attaching,
  live,

  /// The computer closed it ([AiSessionLink.closedReason]) or it was
  /// detached.
  closed,
}

/// Re-attaches in a row after a body that could not be taken, before the
/// link gives up: a desktop that keeps sending one must not make a loop.
const int _maxReattach = 3;

/// This phone's mirror of one AI session (V2-2 D5). Kept across channel
/// losses: on a new channel it re-attaches with what it holds, so only
/// what changed comes back.
final class AiSessionLink {
  AiSessionLink._(this.sid, this._owner);

  final String sid;
  final MachineAi _owner;
  final mirror = AiMirror();
  final _changes = StreamController<void>.broadcast(sync: true);
  AiLinkState _state = AiLinkState.attaching;
  String? _closedReason;
  var _awaitingSnapshot = true;

  /// The `seq` of the last body received on this channel; 0: none yet. It is
  /// what an ack carries, whatever its number: a snapshot goes on from the
  /// numbers before it (also after a re-attach), and on a new channel the
  /// desktop counts anew, so nothing here assumes a snapshot is number 1.
  var _lastSeq = 0;

  /// Bodies in a row that could not be taken.
  var _failures = 0;
  Timer? _ack;
  var _notifying = false;
  var _notifyAgain = false;
  var _disposed = false;

  AiLinkState get state => _state;

  /// `gone` (the tab closed), `desktop_closed`, `unavailable`, `detached`,
  /// `unreadable` (the computer keeps sending what this version cannot
  /// read), or a newer desktop's word.
  String? get closedReason => _closedReason;

  /// After every change of [mirror] or [state].
  Stream<void> get changes => _changes.stream;

  /// Stops mirroring (the screen left).
  void detach() => _owner._detach(this);

  /// "Tải thêm": the page before the held window. A page can be short (the
  /// computer sends what its window allows): [AiMirror.hasEarlier] stays
  /// true until index 0, and the next call asks for the next page.
  void loadEarlier() {
    if (_state != AiLinkState.live || !mirror.hasEarlier) return;
    _owner._send([AiEarlier(sid: sid, before: mirror.from)]);
  }

  void _set(AiLinkState state, [String? reason]) {
    _state = state;
    if (reason != null) _closedReason = reason;
    _notify();
  }

  /// Tells the listeners. A listener that reaches back (detach, say) from its
  /// callback cannot fire the stream inside itself: its change is told once
  /// the round is over.
  void _notify() {
    if (_disposed) return;
    if (_notifying) {
      _notifyAgain = true;
      return;
    }
    _notifying = true;
    try {
      do {
        _notifyAgain = false;
        _changes.add(null);
      } while (_notifyAgain);
    } finally {
      _notifying = false;
    }
    if (_disposed) unawaited(_changes.close());
  }

  void _body(int seq, Uint8List body, {required bool snapshot}) {
    if (_state == AiLinkState.closed) return;
    _lastSeq = seq;
    _scheduleAck();
    if (snapshot) {
      _awaitingSnapshot = false;
    } else if (_awaitingSnapshot) {
      return; // made for what the phone held before its re-attach
    }
    if (!_apply(body, snapshot: snapshot)) {
      _unreadable();
      return;
    }
    _failures = 0;
    if (_state != AiLinkState.live) _state = AiLinkState.live;
    _notify();
  }

  /// False when [body] cannot be taken: not JSON, a gap in what the phone
  /// holds, or something the mirror throws on (a time no clock can show).
  /// The last is a body like the others that cannot be read: it must not
  /// end the batch it came in (terminals follow), nor the channel.
  bool _apply(Uint8List body, {required bool snapshot}) {
    final decoded = decodeBody(body);
    if (decoded == null) return false;
    try {
      return mirror.apply(decoded, snapshot: snapshot);
    } on Object {
      return false;
    }
  }

  /// A gap or a body that could not be read: start again from what the phone
  /// holds. After [_maxReattach] tries in a row the link ends, and the
  /// computer is told to stop.
  void _unreadable() {
    _awaitingSnapshot = true;
    if (++_failures > _maxReattach) {
      _owner._send([AiDetach(sid: sid)]);
      _set(AiLinkState.closed, 'unreadable');
      return;
    }
    _owner._attachNow(this);
  }

  /// One ack per 50 ms at most: each `_send` is a relay frame.
  void _scheduleAck() {
    _ack ??= Timer(const Duration(milliseconds: 50), () {
      _ack = null;
      final seq = _lastSeq;
      if (seq > 0 && _state != AiLinkState.closed) {
        _owner._send([AiAck(sid: sid, seq: seq)]);
      }
    });
  }

  /// The channel is gone: what arrived on it is not acked on the next one (an
  /// ack of the old numbers would clear the window of a subscription it never
  /// saw), and the mirror waits for a new snapshot.
  void _lost() {
    _ack?.cancel();
    _ack = null;
    _lastSeq = 0;
    _failures = 0;
    _awaitingSnapshot = true;
    if (_state == AiLinkState.live) _set(AiLinkState.attaching);
  }

  void _dispose() {
    _ack?.cancel();
    _ack = null;
    _disposed = true;
    if (!_notifying) unawaited(_changes.close());
  }
}

/// A request sent and not answered yet: [sid] is the session it is about
/// (null for `ai.open`).
final class _Pending {
  _Pending(this.sid);
  final String? sid;
  final done = Completer<AiResult>();
}

/// The AI sessions of one machine (V2-2): its listing and the sessions
/// this phone mirrors. Part of [MachineClient]; every request connects
/// first and fails like the client's own requests.
final class MachineAi {
  @internal
  MachineAi({
    required bool Function(List<AppMessage> messages) send,
    required Future<void> Function() connect,
    required Duration timeout,
  }) : _sendRaw = send,
       _connect = connect,
       _timeout = timeout;

  final bool Function(List<AppMessage>) _sendRaw;
  final Future<void> Function() _connect;
  final Duration _timeout;
  bool? _supported;
  AiListing? _listing;
  final _listings = StreamController<AiListing>.broadcast(sync: true);
  var _watching = false;
  var _disposed = false;
  final _links = <String, AiSessionLink>{};
  final _pending = <int, _Pending>{};
  var _nextRid = 1;

  /// A listing is watched or a mirror is open: a lost channel must come
  /// back even without a terminal tab.
  bool get wantsChannel =>
      _watching || _links.values.any((l) => l.state != AiLinkState.closed);

  /// Whether the computer has AI sessions for phones (`ai` in
  /// `session.list.result`); null before the first desktop list.
  bool? get supported => _supported;

  /// The last listing; null before the first one.
  AiListing? get listing => _listing;

  /// Every listing as it comes (the first answer, then each change).
  Stream<AiListing> get listings => _listings.stream;

  /// Keeps the listing current: asks now (connecting first when there is
  /// no channel) and again on every new channel.
  Future<void> watch() async {
    _watching = true;
    if (!_send([const AiList()])) await _connect(); // channelReady asks
  }

  /// Mirrors session [sid] (the same link while it stays open).
  AiSessionLink attach(String sid) {
    final existing = _links[sid];
    if (existing != null && existing.state != AiLinkState.closed) {
      return existing;
    }
    final link = AiSessionLink._(sid, this);
    _links[sid] = link;
    // Without a channel, the next one attaches it (channelReady).
    if (!_attachNow(link)) {
      unawaited(_connect().catchError((Object _) {}));
    }
    return link;
  }

  Future<void> prompt(String sid, String text) {
    if (utf8Length(text) > kAiMaxPromptBytes) {
      return Future.error(const AiRequestException('too_large'));
    }
    return _request(sid, (rid) => AiPrompt(sid: sid, rid: rid, text: text));
  }

  Future<void> answerPermission(String sid, int permission, String option) =>
      _request(
        sid,
        (rid) => AiAnswer(
          sid: sid,
          rid: rid,
          permission: permission,
          option: option,
        ),
      );

  Future<void> answerAsk(
    String sid,
    int ask,
    ElicitationResponse response,
  ) async {
    final body = switch (response) {
      ElicitAccept(:final content) => encodeBody(content ?? const {}),
      _ => null,
    };
    // A message over its limit would make the channel drop (the computer
    // refuses it too): the form's values are the user's, their size is not
    // ours to know.
    if (body != null && body.length > kAiMaxBodyBytes) {
      throw const AiRequestException('too_large');
    }
    await _request(
      sid,
      (rid) => AiAnswer(
        sid: sid,
        rid: rid,
        ask: ask,
        action: switch (response) {
          ElicitAccept() => 'accept',
          ElicitDecline() => 'decline',
          ElicitCancel() => 'cancel',
        },
        body: body,
      ),
    );
  }

  Future<void> cancel(String sid) =>
      _request(sid, (rid) => AiCancel(sid: sid, rid: rid));

  Future<void> forceStop(String sid) =>
      _request(sid, (rid) => AiForceStop(sid: sid, rid: rid));

  Future<void> unqueue(String sid, int queued) =>
      _request(sid, (rid) => AiUnqueue(sid: sid, rid: rid, queued: queued));

  /// A new session; its sid.
  Future<String> open(String agent, String folder) async {
    final result = await _request(
      null,
      (rid) => AiOpen(rid: rid, agent: agent, folder: folder),
    );
    final sid = result.sid;
    if (sid == null) throw const AiRequestException('refused');
    return sid;
  }

  // -------------------------------------------------- from MachineClient --

  /// The answer to a `session.list {desktop: true}`: the only kind that says
  /// whether the computer has AI (another list never carries the key).
  @internal
  void noteListResult(SessionListResult result) {
    final ai = result.ai;
    _supported = ai != null && ai >= 1;
  }

  @internal
  void handle(AiMessage message) {
    if (_disposed) return;
    switch (message) {
      case AiListResult(:final available, :final body):
        _supported = true;
        final json = decodeBody(body);
        final listing = json == null
            ? AiListing(available: available)
            : AiListing.fromJson(json, available: available);
        _listing = listing;
        // No window serves AI: whatever was asked of it gets no answer.
        if (!available) _failPending(const AiRequestException('unavailable'));
        _listings.add(listing);
      case AiSnapshot(:final sid, :final seq, :final body):
        _links[sid]?._body(seq, body, snapshot: true);
      case AiUpdate(:final sid, :final seq, :final body):
        _links[sid]?._body(seq, body, snapshot: false);
      case AiClosed(:final sid, :final reason):
        // A request in flight gets no `ai.result` now.
        _failPending(
          AiRequestException(reason == 'gone' ? 'not_found' : 'unavailable'),
          sid: sid,
        );
        _links[sid]?._set(AiLinkState.closed, reason);
      case AiResult(:final rid):
        _pending.remove(rid)?.done.complete(message);
      default:
        break; // phone → desktop types never come from the desktop
    }
  }

  /// A new channel: the listing and every open mirror resume on it.
  @internal
  void channelReady() {
    if (_disposed) return;
    if (_watching) _send([const AiList()]);
    for (final link in [..._links.values]) {
      if (link.state != AiLinkState.closed) _attachNow(link);
    }
  }

  /// The channel is gone: requests in flight fail (and are never sent again,
  /// the user sees the new state and asks again), mirrors wait for the next
  /// channel.
  @internal
  void channelLost() {
    for (final link in [..._links.values]) {
      link._lost();
    }
    _failPending(
      const MachineConnectionException(MachineConnectionFailure.agentOffline),
    );
  }

  @internal
  void dispose() {
    if (_disposed) return;
    channelLost();
    _disposed = true;
    for (final link in [..._links.values]) {
      link._dispose();
    }
    _links.clear();
    unawaited(_listings.close());
  }

  // ------------------------------------------------------------ private --

  /// False when there is no channel.
  bool _attachNow(AiSessionLink link) {
    link._awaitingSnapshot = true;
    return _send([AiAttach(sid: link.sid, body: _have(link))]);
  }

  /// What the phone holds of [link], for `ai.attach`; null when it holds
  /// nothing, or too much for a message (one item takes about 2 bytes: past
  /// the limit the session is read again from its end).
  Uint8List? _have(AiSessionLink link) {
    if (link.mirror.generation < 0) return null;
    final body = encodeBody(link.mirror.have.toJson());
    return body.length > kAiMaxBodyBytes ? null : body;
  }

  void _detach(AiSessionLink link) {
    if (identical(_links[link.sid], link)) {
      _links.remove(link.sid);
      if (link.state != AiLinkState.closed) {
        _send([AiDetach(sid: link.sid)]);
        link._set(AiLinkState.closed, 'detached');
      }
    }
    link._dispose();
  }

  bool _send(List<AppMessage> messages) => _sendRaw(messages);

  /// Fails the requests in flight about [sid] (all of them when null).
  void _failPending(Object error, {String? sid}) {
    final failed = [
      for (final e in _pending.entries)
        if (sid == null || e.value.sid == sid) e.key,
    ];
    for (final rid in failed) {
      _pending.remove(rid)?.done.completeError(error);
    }
  }

  /// Sends the request [make] makes and waits for its `ai.result`; [sid] is
  /// the session it is about, null for none.
  Future<AiResult> _request(
    String? sid,
    AiMessage Function(int rid) make,
  ) async {
    await _connect();
    final rid = _nextRid++;
    final pending = _Pending(sid);
    _pending[rid] = pending;
    if (!_send([make(rid)])) {
      _pending.remove(rid);
      throw const MachineConnectionException(
        MachineConnectionFailure.agentOffline,
      );
    }
    final result = await pending.done.future.timeout(
      _timeout,
      onTimeout: () {
        _pending.remove(rid);
        throw const MachineConnectionException(
          MachineConnectionFailure.timeout,
        );
      },
    );
    if (!result.ok) throw AiRequestException(result.code ?? 'refused');
    return result;
  }
}
