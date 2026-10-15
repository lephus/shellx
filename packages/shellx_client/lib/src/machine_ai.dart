import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random, min;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';

/// A request of the AI session failed on the computer (`ai.result` with
/// [code]: `stale`, `refused`, `queue_full`, `too_large`, `busy`,
/// `not_found`, `unavailable`, `on_computer`, and since V2-2b `no_images`,
/// `confirm`, `busy_turn`, `not_ready`, `undo_off`, `too_big`, or a newer
/// word). It also ends a request that was in flight when the computer closed
/// the session (`not_found` for a tab that closed, `unavailable` when the
/// window quit): no `ai.result` comes then. `unsupported` (V2-2b R15): this
/// phone did not send it, the computer cannot take it. [body]: what the
/// computer said with the code (V2-2b B4, a `confirm`'s files, say), when it
/// was a JSON object; never in [toString].
final class AiRequestException implements Exception {
  const AiRequestException(this.code, {this.body});
  final String code;
  final Map<String, Object?>? body;

  @override
  String toString() => 'AiRequestException($code)';
}

enum AiLinkState {
  /// Waiting for the snapshot (first attach, or after a channel loss).
  attaching,
  live,

  /// The computer closed it ([AiSessionLink.closedReason]) or it was
  /// detached. Final, but for `unavailable` (no window served AI then): the
  /// link attaches once more, and is [attaching] again, when the next
  /// listing says AI is available.
  closed,
}

/// Re-attaches in a row after a body that could not be taken, before the
/// link gives up: a desktop that keeps sending one must not make a loop.
const int _maxReattach = 3;

/// V2-2b B16: how many times a full item that changes while it loads starts
/// again, and the most slices one may have (2 MiB of the worst escaping is
/// about 350).
const int _itemRestarts = 3;
const int _maxItemParts = 512;

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

  /// The `seq` of the last body taken on this channel (one skipped while
  /// awaiting a snapshot does not count); 0: none yet. It is what an ack
  /// carries, whatever its number: a snapshot goes on from the numbers before
  /// it (also after a re-attach), and on a new channel the desktop counts
  /// anew, so nothing here assumes a snapshot is number 1.
  var _lastSeq = 0;

  /// Bodies in a row that could not be taken.
  var _failures = 0;

  /// The computer answered `unavailable` (no window served AI: a background
  /// service that came back before the window did, say): the next listing
  /// that says AI is available attaches once more.
  var _retry = false;

  /// That one more attach was made since the link was last live: another
  /// `unavailable` closes it for good, never a loop.
  var _retried = false;
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
    // Made for what the phone held before its re-attach: not applied, and not
    // acked either. Through the background service it can even be a body of
    // the previous channel's subscription that crossed `ai.gone`: its seq
    // would clear the window of the subscription that answers this attach.
    if (!snapshot && _awaitingSnapshot) return;
    _lastSeq = seq;
    _scheduleAck();
    if (snapshot) _awaitingSnapshot = false;
    if (!_apply(body, snapshot: snapshot)) {
      _unreadable();
      return;
    }
    _failures = 0;
    _retried = false;
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
  int? _protocol;
  AiListing? _listing;
  final _listings = StreamController<AiListing>.broadcast(sync: true);
  var _watching = false;
  var _disposed = false;
  final _links = <String, AiSessionLink>{};
  final _pending = <int, _Pending>{};
  var _nextRid = 1;

  /// V2-2b B12, R17, F33: the number of the next image this phone uploads.
  /// It starts at a number of this run's own (random, in [1, 2^30)) and goes
  /// on by one: an app started again within the 2 minutes the computer keeps
  /// an image, before it saw the old channel go, would otherwise begin at the
  /// same number, and the computer — which keeps an image already whole as it
  /// came — would answer the new parts ok and send the previous run's image
  /// with the prompt.
  var _nextBlob = Random.secure().nextInt((1 << 30) - 1) + 1;

  /// V2-2b F32: the channels lost so far. An upload that began before one is
  /// over: the computer dropped its parts when the phone left, and nothing is
  /// uploaded on a new channel by itself (R23).
  var _lostChannels = 0;

  /// Image parts in flight at once (V2-2b B12).
  static const int _partsInFlight = 4;

  /// A listing is watched or a mirror is open (or waits for AI to be
  /// available again): a lost channel must come back even without a
  /// terminal tab.
  bool get wantsChannel =>
      _watching ||
      _links.values.any((l) => l.state != AiLinkState.closed || l._retry);

  /// Whether the computer has AI sessions for phones (`ai` in
  /// `session.list.result`); null before the first desktop list.
  bool? get supported => _supported;

  /// V2-2b B1: the `ai` protocol the computer's relay process reported in
  /// its last `session.list.result` — 1: V2-2a (or a V2-2b window behind a
  /// V2-2a background service, which drops what it cannot read); 2: V2-2b.
  /// Null before the first desktop list, or from a computer without AI for
  /// phones.
  int? get protocol => _protocol;

  /// V2-2b B1 (R3): whether this phone may use [feature] (an `AiFeature`
  /// word) now: the computer's relay process speaks `ai` 2 or more, so
  /// whatever lies between the phone and the window passes V2-2b messages
  /// on, and the window's last listing names it. With either missing, the
  /// feature's buttons do not show and its requests fail at once (R15).
  bool can(String feature) =>
      (_protocol ?? 0) >= 2 && (_listing?.features.contains(feature) ?? false);

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

  /// The inverse of [watch], and it does nothing when nothing is watched: the
  /// list is no longer wanted, so a lost channel is not brought back for it
  /// and a new one does not ask for it (an open mirror still wants the
  /// channel). The computer keeps sending the changes of the list until the
  /// channel ends (it cannot be asked to stop); they are still read.
  void unwatch() => _watching = false;

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

  /// Sends [text] to [sid] (queued there while a turn runs), with the images
  /// this phone uploaded ([blobs], V2-2b B12): at most [kAiImagesMax], sent
  /// only to a computer that takes them (B1).
  Future<void> prompt(String sid, String text, {List<int> blobs = const []}) {
    if (utf8Length(text) > kAiMaxPromptBytes || blobs.length > kAiImagesMax) {
      return Future.error(const AiRequestException('too_large'));
    }
    AiMessage make(int rid) =>
        AiPrompt(sid: sid, rid: rid, text: text, blobs: blobs);
    return blobs.isEmpty
        ? _request(sid, make)
        : _feature(AiFeature.blob, sid, make);
  }

  /// V2-2b B12, R17, F33: a number for the next image this phone uploads:
  /// never the same twice for this machine, and not the numbers an earlier
  /// run of the app used (the first is random, the rest follow it).
  int newBlobId() => _nextBlob++;

  /// V2-2b B12: uploads image [blob] — [bytes] of type [mime] — in parts of
  /// at most [kAiMaxBlobPartBytes], at most four in flight; [onProgress]
  /// after each part the computer took. A part the computer is too busy for
  /// goes again after a moment, three times at most. Throws like every
  /// request. The upload is over (F32) when a part failed — nothing more is
  /// sent, also by the parts waiting to ask again — and when a channel is
  /// lost, even while every part waits: it fails with
  /// [MachineConnectionException] and sends nothing on the new channel. The
  /// caller uploads the image again, on the user's next Send (never the prompt
  /// by itself, V2-2 D13, R23).
  Future<void> uploadImage(
    int blob,
    String mime,
    Uint8List bytes, {
    void Function(int sent, int parts)? onProgress,
  }) async {
    if (!can(AiFeature.blob)) throw const AiRequestException('unsupported');
    if (bytes.isEmpty || bytes.length > kAiImageMaxBytes) {
      throw const AiRequestException('too_large');
    }
    final parts =
        (bytes.length + kAiMaxBlobPartBytes - 1) ~/ kAiMaxBlobPartBytes;
    final lost = _lostChannels;
    var next = 0;
    var sent = 0;
    var failed = false;

    /// F32: whether the upload goes on, asked before every part and after
    /// every wait to ask again. False once a part failed; and it throws once
    /// a channel was lost since the upload began (the computer dropped every
    /// part when the phone left: a part sent now would begin an image that
    /// is never whole).
    bool goesOn() {
      if (_lostChannels != lost) {
        throw const MachineConnectionException(
          MachineConnectionFailure.agentOffline,
        );
      }
      return !failed;
    }

    Future<void> worker() async {
      while (next < parts) {
        try {
          if (!goesOn()) return;
          final part = next++;
          final from = part * kAiMaxBlobPartBytes;
          final data = bytes.sublist(
            from,
            min(from + kAiMaxBlobPartBytes, bytes.length),
          );
          final taken = await _blobPart(
            blob,
            part,
            parts,
            part == 0 ? mime : null,
            data,
            goesOn,
          );
          if (!taken) return;
        } on Object {
          failed = true;
          rethrow;
        }
        onProgress?.call(++sent, parts);
      }
    }

    await Future.wait([
      for (var i = 0; i < min(_partsInFlight, parts); i++) worker(),
    ]);
  }

  /// One part of an upload; `busy` waits and asks again, three times at most.
  /// After each wait [goesOn] (F32) decides whether the part is still wanted:
  /// it throws, or says no — then nothing is sent, and the answer is false.
  /// True: the computer took the part.
  Future<bool> _blobPart(
    int blob,
    int part,
    int parts,
    String? mime,
    Uint8List data,
    bool Function() goesOn,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _feature(
          AiFeature.blob,
          null,
          (rid) => AiBlob(
            rid: rid,
            blob: blob,
            part: part,
            parts: parts,
            mime: mime,
            data: data,
          ),
        );
        return true;
      } on AiRequestException catch (e) {
        if (e.code != 'busy' || attempt >= 3) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!goesOn()) return false;
      }
    }
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

  /// V2-2b B17: a page of the earlier sessions of [sid]'s agent in its folder
  /// ([cursor]: the next page). Throws [AiRequestException]: `not_ready`
  /// while the agent does not run, `unsupported` when the computer cannot.
  Future<AiHistoryPage> history(String sid, {String? cursor}) async {
    final result = await _feature(
      AiFeature.history,
      sid,
      (rid) => AiHistory(sid: sid, rid: rid, cursor: cursor),
    );
    return AiHistoryPage.fromJson(decodeBody(result.body) ?? const {});
  }

  /// V2-2b B17: reopens the agent's earlier session [acp] in a new AI tab of
  /// [agent] in [folder] (a listing key: the folder of the session the
  /// history came from); the new session's sid.
  Future<String> resume(String agent, String folder, String acp) async {
    final result = await _feature(
      AiFeature.history,
      null,
      (rid) => AiOpen(rid: rid, agent: agent, folder: folder, resume: acp),
    );
    final sid = result.sid;
    if (sid == null) throw const AiRequestException('refused');
    return sid;
  }

  /// V2-2b B18: runs session [sid], a tab without a folder, in [folder] (a
  /// key from the listing); the session then starts on the computer.
  Future<void> chooseFolder(String sid, String folder) => _feature(
    AiFeature.folder,
    sid,
    (rid) => AiFolder(sid: sid, rid: rid, folder: folder),
  );

  /// V2-2b B11: the mode, model and thinking choices of [sid] this phone may
  /// make. Throws [AiRequestException] (`unsupported` at once, sending
  /// nothing, when the computer cannot: R15) or [MachineConnectionException].
  Future<AiConfigView> config(String sid) async {
    final result = await _feature(
      AiFeature.config,
      sid,
      (rid) => AiConfigGet(sid: sid, rid: rid),
    );
    return AiConfigView.fromJson(decodeBody(result.body) ?? const {});
  }

  /// V2-2b B11: sets option [id] of [sid] to [value] (a choice's value, or a
  /// bool for a switch). One explicit tap, one request: never sent again.
  Future<void> setConfig(String sid, String id, Object value) => _feature(
    AiFeature.config,
    sid,
    (rid) => AiConfigSet(
      sid: sid,
      rid: rid,
      body: encodeBody({'id': id, 'value': value}),
    ),
  );

  /// V2-2b B11: sets the mode of [sid] for an agent with only modes.
  Future<void> setMode(String sid, String modeId) => _feature(
    AiFeature.config,
    sid,
    (rid) =>
        AiConfigSet(sid: sid, rid: rid, body: encodeBody({'mode': modeId})),
  );

  /// V2-2b B16: item [index] of [sid] in full, loaded one slice at a time:
  /// one request in flight, so the channel and the budget stay free for
  /// everything else. [onPart] is told after each slice (1-based); an error
  /// it throws ends the load (the page that asked is gone). When the item
  /// changes on the computer while it loads (a command still running), the
  /// load starts again from the first slice, at most [_itemRestarts] times,
  /// then fails `changing`. Throws [AiRequestException] (`too_big`: read it on
  /// the computer; `unsupported`, R15) or [MachineConnectionException].
  Future<AiFullView> fullItem(
    String sid,
    int index, {
    void Function(int part, int parts)? onPart,
  }) async {
    for (var round = 0; round <= _itemRestarts; round++) {
      final text = StringBuffer();
      int? rev;
      var parts = 1;
      var changed = false;
      for (var part = 0; part < parts; part++) {
        final result = await _feature(
          AiFeature.item,
          sid,
          (rid) => AiItemPart(sid: sid, rid: rid, index: index, part: part),
        );
        final body = decodeBody(result.body);
        final r = body == null ? null : jInt(body, 'r');
        final n = body == null ? null : jInt(body, 'parts');
        final slice = body == null ? null : jString(body, 'text');
        // What no hub sends: a body that cannot be read, or more slices than
        // any item may have.
        if (r == null || n == null || n < 1 || n > _maxItemParts) {
          throw const AiRequestException('refused');
        }
        if (slice == null || jInt(body!, 'part') != part) {
          throw const AiRequestException('refused');
        }
        if (rev != null && r != rev) {
          changed = true;
          break;
        }
        rev = r;
        parts = n;
        text.write(slice);
        onPart?.call(part + 1, parts);
      }
      if (changed) continue;
      Object? json;
      try {
        json = jsonDecode(text.toString());
      } on FormatException {
        json = null;
      }
      final view = json is Map<String, Object?>
          ? AiFullView.fromJson(json)
          : null;
      if (view == null) throw const AiRequestException('refused');
      return view;
    }
    throw const AiRequestException('changing');
  }

  // -------------------------------------------------- from MachineClient --

  /// The answer to a `session.list {desktop: true}`: the only kind that says
  /// whether the computer has AI (another list never carries the key).
  @internal
  void noteListResult(SessionListResult result) {
    final ai = result.ai;
    _supported = ai != null && ai >= 1;
    _protocol = ai;
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
        if (available) _attachAgain();
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
        final link = _links[sid];
        if (link == null) break;
        // No window served AI (a background service that came back before
        // the window, say): the page attaches once more when the list says
        // one does, and asks for the list to hear it.
        if (reason == 'unavailable' && !link._retried) {
          link._retry = true;
          if (!_watching) _send([const AiList()]);
        }
        link._set(AiLinkState.closed, reason);
      case AiResult(:final rid):
        _pending.remove(rid)?.done.complete(message);
      default:
        break; // phone → desktop types never come from the desktop
    }
  }

  /// A new channel: the listing and every open mirror resume on it; a page
  /// that waits for AI to be available asks for the listing too.
  @internal
  void channelReady() {
    if (_disposed) return;
    if (_watching || _links.values.any((l) => l._retry)) {
      _send([const AiList()]);
    }
    for (final link in [..._links.values]) {
      if (link.state != AiLinkState.closed) _attachNow(link);
    }
  }

  /// The channel is gone: requests in flight fail (and are never sent again,
  /// the user sees the new state and asks again), mirrors wait for the next
  /// channel, and an image upload that began before is over (F32), also one
  /// whose parts are all waiting to ask again.
  @internal
  void channelLost() {
    _lostChannels++;
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
    link._retry = false;
    if (identical(_links[link.sid], link)) {
      _links.remove(link.sid);
      if (link.state != AiLinkState.closed) {
        _send([AiDetach(sid: link.sid)]);
        link._set(AiLinkState.closed, 'detached');
      }
    }
    link._dispose();
  }

  /// A window serves AI again (M10): each page closed `unavailable` attaches
  /// once more. The computer answers: a snapshot, or `gone` when the session
  /// is not there any more (another run of the window).
  void _attachAgain() {
    for (final link in [..._links.values]) {
      if (!link._retry) continue;
      link
        .._retry = false
        .._retried = true
        .._closedReason = null;
      _attachNow(link);
      link._set(AiLinkState.attaching);
    }
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
    if (!result.ok) {
      throw AiRequestException(
        result.code ?? 'refused',
        body: decodeBody(result.body),
      );
    }
    return result;
  }

  /// A V2-2b request of [feature] (R15): when the computer cannot take it
  /// ([can] is false) it fails at once with `unsupported`, sending nothing;
  /// else it goes like every request, and its [AiResult] (with its
  /// [AiResult.body]) is the caller's to read.
  // The first feature's request (V2-2b Task 10) is its first caller.
  Future<AiResult> _feature(
    String feature,
    String? sid,
    AiMessage Function(int rid) make,
  ) {
    if (!can(feature)) {
      return Future.error(const AiRequestException('unsupported'));
    }
    return _request(sid, make);
  }
}
