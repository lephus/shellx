import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';
import 'ai_endpoint.dart';

/// One AI session of the window, as the hub needs it (V2-2 D2).
final class AiSessionEntry with Redacted {
  const AiSessionEntry({
    required this.paneId,
    required this.agentId,
    required this.agentName,
    required this.title,
    this.cwd,
    this.acpSessionId,
    this.state,
    this.unavailable,
  });

  /// The AI pane (V2-1 D3); the hub's session id is made from it.
  final int paneId;
  final String agentId;
  final String agentName;
  final String title;
  final String? cwd;
  final String? acpSessionId;

  /// The runtime's state; null while no runtime was made (a restored tab
  /// not shown yet) or when it cannot run ([unavailable]).
  final AiSessionState? state;

  /// [AiRemoteState.noFolder] or [AiRemoteState.agentOff]; null otherwise.
  final AiRemoteState? unavailable;
}

/// What a phone may do to a running session (V2-1a `AiRuntime`).
abstract interface class AiControl {
  AiSessionState get state;

  /// Sends or queues (V2-1 D16); false when it cannot be taken.
  Future<bool> send(List<ContentBlock> prompt);
  void cancel();
  Future<void> forceStop();

  /// Throws [AiRefused] for an answer the window takes only on the computer.
  void answerPermission(int id, String optionId);

  /// Throws [AiRefused] for an answer the window takes only on the computer.
  void answerAsk(int id, ElicitationResponse response);
}

/// An [AiControl] will not do what a phone asks, for a reason of the
/// window's own: the phone's `ai.result` carries [code] (V2-2 D7). The
/// desktop refuses this way an answer it gives only on the computer, after a
/// question there: `on_computer` (an option that turns on a mode acting
/// without asking, V2-1 R6, V2-2 D13).
final class AiRefused implements Exception {
  const AiRefused(this.code);

  /// An `ai.result` code: a short snake_case word.
  final String code;

  @override
  String toString() => 'AiRefused($code)';
}

/// The window, as the hub sees it (V2-2 D2). The desktop app implements
/// it over its tabs and runtimes; tests over plain states.
abstract interface class AiSessionSource {
  /// Fires when [sessions], [agents] or [folders] may have changed (a tab
  /// opened or closed, a runtime made, a folder chosen).
  Stream<void> get changes;

  /// The AI sessions, in sidebar order.
  List<AiSessionEntry> get sessions;

  /// The agents a phone may start, and where.
  List<AiAgentChoice> get agents;
  List<AiFolderChoice> get folders;
  String? get defaultAgent;

  /// The runtime of AI pane [paneId], made on first use; with [start] its
  /// agent starts if it has not (a phone wants to see the session). Null
  /// when it cannot run.
  AiControl? control(int paneId, {bool start = false});

  /// A new AI tab with agent [agentId] in folder [folderKey] (from
  /// [folders]), not selected, its agent started; its pane id, or null
  /// when either is not offered.
  Future<int?> open(String agentId, String folderKey);

  /// The user is looking at pane [paneId] on the computer now (window
  /// focused, pane focused): no push for its request (V2-2 D11) until the
  /// request has waited [AiPhoneHub.overdueAfter] — a computer left in front
  /// of an empty chair keeps its focus.
  bool seenOnDesktop(int paneId);

  /// A4's long-command threshold: a turn at least this long that ends
  /// unseen is pushed as done; null: off.
  Duration? get doneThreshold;
}

enum AiPushKind { needsInput, done }

/// A push the hub asks for (V2-2 D11); worded by the agent side's
/// `AgentNotifications.aiNotice`.
final class AiPush with Redacted {
  const AiPush({
    required this.kind,
    required this.agentName,
    required this.sid,
    this.detail,
    this.question = false,
    this.turn,
    this.elapsed,
  });

  final AiPushKind kind;
  final String agentName;
  final String sid;

  /// The permission the agent waits for ("Sửa src/main.ts"), in clear
  /// through the push service like a command line (N3).
  final String? detail;

  /// The agent waits for the answer to a question: the push says only that
  /// it asks. Its words are the agent's own and may quote a file, so they
  /// never leave the encrypted channel (as ruled after review, M2).
  final bool question;
  final int? turn;
  final Duration? elapsed;

  /// For `ai.push` (window → background service). `question` is a later
  /// key: an older service skips it and, with no detail, says only "needs
  /// your answer".
  Map<String, Object?> toFields() => {
    'kind': kind.name,
    'name': agentName,
    'sid': sid,
    'detail': ?detail,
    if (question) 'question': true,
    'turn': ?turn,
    if (elapsed != null) 'ms': elapsed!.inMilliseconds,
  };

  static AiPush? fromFields(Map<String, Object?> f) {
    final kind = AiPushKind.values
        .where((k) => k.name == f['kind'])
        .firstOrNull;
    final name = f['name'];
    final sid = f['sid'];
    if (kind == null || name is! String || sid is! String) return null;
    final detail = f['detail'];
    final turn = f['turn'];
    final ms = f['ms'];
    return AiPush(
      kind: kind,
      agentName: name,
      sid: sid,
      detail: detail is String ? detail : null,
      question: f['question'] == true,
      turn: turn is int ? turn : null,
      elapsed: ms is int ? Duration(milliseconds: ms) : null,
    );
  }
}

typedef AiPushSink = void Function(AiPush push);

final class _Phone {
  bool listing = false;
  String? sentListing;
  final subs = <String, AiSubscription>{};

  /// "Load earlier" asked while the window was full: where to page from,
  /// per session. The next ack that opens the window answers it.
  final earlier = <String, int>{};

  /// Sessions this phone was told cannot run now (no folder, their agent
  /// off): a runtime that comes brings them live again.
  final parked = <String>{};

  /// The `seq` of the last mirror message sent for a session by a
  /// subscription that is gone (or by the "cannot run" snapshot): the next
  /// subscription goes on from it, so `seq` never goes back and a late ack of
  /// the old one clears nothing of the new one.
  final seqs = <String, int>{};
  double tokens = _AiBudget.burst;
  DateTime refilled = DateTime.fromMillisecondsSinceEpoch(0);
}

abstract final class _AiBudget {
  /// Requests a phone may make at once, and per second after that.
  static const double burst = 60;
  static const double perSecond = 30;
}

/// A session id the hub made is far shorter than this.
const int _maxSidLength = 256;

/// One list of a listing, with the JSON bytes of each entry, that can lose
/// its last entry (a listing too big for one message is cut this way).
final class _Cut<T> {
  _Cut(List<T> list, Map<String, Object?> Function(T) toJson)
    : entries = [...list],
      sizes = [for (final e in list) utf8Length(jsonEncode(toJson(e)))] {
    bytes = sizes.fold(0, (a, b) => a + b);
  }

  final List<T> entries;
  final List<int> sizes;
  late int bytes;

  /// Drops the last entry; the bytes that go with it, its comma included.
  int dropLast() {
    entries.removeLast();
    final entry = sizes.removeLast();
    bytes -= entry;
    return entry + (entries.isEmpty ? 0 : 1);
  }
}

final class _Watch {
  _Watch(this.state, this.listener, this.items);
  final AiSessionState state;
  final void Function() listener;
  int items;

  /// The request the session waits for now, the one its header shows: a
  /// permission's or a question's id (one counter, never used again).
  int? attention;

  /// Requests a "needs you" push went for, while they wait: never twice.
  final pushed = <int>{};

  /// The phones that mirror the session had [AiPhoneHub.ackGrace] to
  /// acknowledge [attention] (from when it came, or when the last of them
  /// attached): one that has not does not count as showing it.
  var graceOver = false;
  Timer? grace;

  /// [attention] has waited [AiPhoneHub.overdueAfter]: the window showing
  /// the session no longer holds its push back.
  var overdue = false;
  Timer? overdueTimer;

  /// When the last "needs you" push went; a done push does not count.
  DateTime? needsPushedAt;

  void stop() {
    grace?.cancel();
    grace = null;
    overdueTimer?.cancel();
    overdueTimer = null;
  }
}

/// The window's side of AI on phones (V2-2 D1, D2, D5, D11): lists the AI
/// sessions, mirrors the ones a phone attaches (at most one update per
/// [flushEvery] each, within each phone's window), runs the phone's
/// requests — only explicit ones, checked against what is pending now —
/// and asks for a push when a session needs the user and nobody shows the
/// request: no phone that mirrors the session took it, and the window does
/// not show it (or the request has waited a minute). Never logs anything a
/// session holds.
final class AiPhoneHub implements AiEndpoint {
  AiPhoneHub({
    required AiSessionSource source,
    AiPushSink? push,
    DateTime Function()? now,
    String? epoch,
    this.flushEvery = const Duration(milliseconds: 100),
    this.listEvery = const Duration(milliseconds: 250),
    this.pushEvery = const Duration(seconds: 30),
    this.ackGrace = const Duration(seconds: 10),
    this.overdueAfter = const Duration(seconds: 60),
  }) : _source = source,
       _push = push,
       _now = now ?? DateTime.now,
       epoch = epoch ?? _newEpoch() {
    _changes = source.changes.listen((_) => _rescan(), onError: (Object _) {});
    _rescan();
  }

  final AiSessionSource _source;
  final AiPushSink? _push;
  final DateTime Function() _now;

  /// Starts every session id of this hub: ids of another run are unknown.
  final String epoch;
  final Duration flushEvery;
  final Duration listEvery;

  /// At most one "needs you" push per session in this time.
  final Duration pushEvery;

  /// How long a phone that mirrors a session may take to acknowledge a new
  /// request before it does not count as showing it: its socket may have
  /// died without a word (a lift, a pocket), which the relay notices only
  /// minutes later, and the push must not wait for that.
  final Duration ackGrace;

  /// A request still unanswered this long after it came is pushed even while
  /// the window shows its session (V2-2 D11, as ruled after review): someone
  /// at the screen answers within a minute, and a computer left in front of
  /// an empty chair keeps its focus.
  final Duration overdueAfter;

  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final _phones = <String, _Phone>{};
  final _watched = <int, _Watch>{};
  final _generations = Expando<int>();
  var _nextGeneration = 1;
  final _flushTimers = <String, Timer>{};
  final _lastFlush = <String, DateTime>{};
  Timer? _listTimer;
  late final StreamSubscription<void> _changes;
  var _disposed = false;

  static String _newEpoch() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// The session id of AI pane [paneId] for phones.
  String sidOf(int paneId) => '$epoch.$paneId';

  int? _paneOf(String sid) {
    final dot = sid.lastIndexOf('.');
    if (dot <= 0 || sid.substring(0, dot) != epoch) return null;
    final paneId = int.tryParse(sid.substring(dot + 1));
    // One name per session: "7", never "07", "+7" or "0x7".
    return paneId == null || sidOf(paneId) != sid ? null : paneId;
  }

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    if (_disposed) return;
    final phone = _phones.putIfAbsent(mobileId, _Phone.new);
    if (message is! AiAck && message is! AiDetach && !_take(phone)) {
      final rid = _ridOf(message);
      if (rid != null) {
        _send(mobileId, AiResult(rid: rid, ok: false, code: 'busy'));
      }
      return;
    }
    switch (message) {
      case AiList():
        phone.listing = true;
        phone.sentListing = null;
        _sendListing(mobileId, phone);
      case AiAttach(:final sid, :final body):
        _attach(mobileId, phone, sid, AiHave.fromJson(decodeBody(body)));
      case AiDetach(:final sid):
        _leave(phone, sid);
      case AiAck(:final sid, :final seq):
        final sub = phone.subs[sid];
        if (sub == null) return;
        sub.ack(seq);
        _sendEarlier(mobileId, phone, sid);
        if (sub.dirty && sub.canSend) _scheduleFlush(sid);
      case AiEarlier(:final sid, :final before):
        if (!phone.subs.containsKey(sid)) return;
        phone.earlier[sid] = before;
        _sendEarlier(mobileId, phone, sid);
      case AiPrompt(:final sid, :final rid, :final text):
        unawaited(_prompt(mobileId, phone, sid, rid, text));
      case AiAnswer():
        _answer(mobileId, message);
      case AiCancel(:final sid, :final rid):
        _command(mobileId, sid, rid, (c) {
          if (c.state.turn == null) return 'stale';
          c.cancel();
          return null;
        });
      case AiForceStop(:final sid, :final rid):
        _command(mobileId, sid, rid, (c) {
          if (c.state.turn?.canForceStop != true) return 'refused';
          // Started; how it ends shows in the session, not in an error that
          // would escape here.
          unawaited(c.forceStop().catchError((Object _) {}));
          return null;
        });
      case AiUnqueue(:final sid, :final rid, :final queued):
        _command(mobileId, sid, rid, (c) {
          if (!c.state.queue.any((q) => q.id == queued)) return 'stale';
          c.state.removeQueued(queued);
          return null;
        });
      case AiOpen(:final rid, :final agent, :final folder):
        unawaited(_open(mobileId, phone, rid, agent, folder));
      case AiListResult() ||
          AiSnapshot() ||
          AiUpdate() ||
          AiClosed() ||
          AiResult():
        break; // desktop → phone types are never taken from a phone
    }
  }

  /// Forgets the phone: its mirrors, its listing, its budget. The router may
  /// say it more than once; nothing is sent to a phone that is not known. A
  /// request one of its mirrors showed may be shown by nobody now: it is
  /// looked at again (V2-2 D11).
  @override
  void phoneGone(String mobileId) {
    final phone = _phones.remove(mobileId);
    if (phone != null) _lookAgain(phone.subs.keys);
  }

  @override
  void allPhonesGone() {
    final sids = [for (final p in _phones.values) ...p.subs.keys];
    _phones.clear();
    _lookAgain(sids);
  }

  /// Stops listening; the window is going. Every phone hears it first, as
  /// from a background service whose window quit (V2-2 D1): a phone that
  /// lists gets `available: false`, every session it mirrors or waits for
  /// `ai.closed {desktop_closed}`. Then nothing more is sent.
  void dispose() {
    if (_disposed) return;
    for (final MapEntry(key: mobileId, value: phone) in [..._phones.entries]) {
      if (phone.listing) {
        _send(
          mobileId,
          AiListResult(available: false, body: emptyAiListingBody),
        );
      }
      for (final sid in {...phone.subs.keys, ...phone.parked}) {
        _send(mobileId, AiClosed(sid: sid, reason: 'desktop_closed'));
      }
    }
    _disposed = true;
    unawaited(_changes.cancel());
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    _flushTimers.clear();
    _listTimer?.cancel();
    for (final w in _watched.values) {
      w.state.removeListener(w.listener);
      w.stop();
    }
    _watched.clear();
    _phones.clear();
  }

  // ------------------------------------------------------------ sessions --

  void _rescan() {
    if (_disposed) return;
    final List<AiSessionEntry> entries;
    try {
      entries = _source.sessions;
    } on Object {
      return; // the window's code failed: the next change looks again
    }
    final live = <int>{};
    for (final e in entries) {
      final state = e.state;
      if (state == null) {
        // No runtime now. With a reason it cannot run (no folder, agent off);
        // without one another is on its way, and phones wait for it.
        if (e.unavailable != null) _park(e);
        continue;
      }
      live.add(e.paneId);
      final watch = _watched[e.paneId];
      if (watch != null && identical(watch.state, state)) continue;
      watch?.state.removeListener(watch.listener);
      watch?.stop();
      // A state this session did not have: the phones that mirror it (or
      // wait for it) start over on it — also after a gap with no state at all.
      _resubscribe(e.paneId, state);
      void listener() {
        try {
          _onState(e.paneId);
        } on Object {
          // Whatever the window's code does, this listener runs inside the
          // runtime's loop over its listeners: it must not throw into it.
        }
      }

      state.addListener(listener);
      final w = _watched[e.paneId] = _Watch(
        state,
        listener,
        state.timeline.items.length,
      );
      _attend(e.paneId, w, _requestOf(state));
    }
    for (final paneId in [..._watched.keys]) {
      if (live.contains(paneId)) continue;
      final w = _watched.remove(paneId)!;
      w.state.removeListener(w.listener);
      w.stop();
    }
    // Sessions that went away close on every phone that mirrors them or was
    // waiting for them, and leave no timer or clock behind.
    final present = {for (final e in entries) sidOf(e.paneId)};
    for (final MapEntry(key: mobileId, value: phone) in _phones.entries) {
      for (final sid in {...phone.subs.keys, ...phone.parked}) {
        if (present.contains(sid)) continue;
        _leave(phone, sid);
        _send(mobileId, AiClosed(sid: sid, reason: 'gone'));
      }
      // The counts of sessions that are gone, also a phone that had left.
      phone.seqs.removeWhere((sid, _) => !present.contains(sid));
    }
    for (final sid in [..._flushTimers.keys]) {
      if (!present.contains(sid)) _flushTimers.remove(sid)?.cancel();
    }
    _lastFlush.removeWhere((sid, _) => !present.contains(sid));
    _scheduleListing();
  }

  /// [phone] mirrors [sid] no more (nor waits for a page of it); the next
  /// subscription goes on from this one's `seq`.
  void _drop(_Phone phone, String sid) {
    final sub = phone.subs.remove(sid);
    if (sub != null) phone.seqs[sid] = sub.lastSeq;
    phone.earlier.remove(sid);
  }

  /// [phone] is done with [sid]: it left, or the session is gone.
  void _leave(_Phone phone, String sid) {
    _drop(phone, sid);
    phone.parked.remove(sid);
  }

  /// [phone]'s subscription to [sid] on [state], replacing any other, going
  /// on from its `seq`.
  AiSubscription _subscribe(_Phone phone, String sid, AiSessionState state) {
    _leave(phone, sid);
    return phone.subs[sid] = AiSubscription(
      state,
      generation: _generation(state),
      afterSeq: phone.seqs[sid] ?? 0,
    );
  }

  int _generation(AiSessionState state) =>
      _generations[state] ??= _nextGeneration++;

  /// The session got a state it did not have (a new runtime, or one after a
  /// gap): phones that mirror it, or were told it cannot run, start over.
  void _resubscribe(int paneId, AiSessionState state) {
    final sid = sidOf(paneId);
    for (final MapEntry(key: mobileId, value: phone) in _phones.entries) {
      final old = phone.subs[sid];
      if (old == null && !phone.parked.contains(sid)) continue;
      if (old != null && identical(old.state, state)) continue; // up to date
      final sub = _subscribe(phone, sid, state);
      _sendAll(mobileId, phone, sid, sub.attach(null));
    }
  }

  /// A session that cannot run now while phones mirror it: they are told why
  /// (no frozen mirror) and wait for a runtime to come back.
  void _park(AiSessionEntry entry) {
    final sid = sidOf(entry.paneId);
    for (final MapEntry(key: mobileId, value: phone) in _phones.entries) {
      if (!phone.subs.containsKey(sid)) continue;
      _drop(phone, sid);
      phone.parked.add(sid);
      _sendUnavailable(mobileId, phone, sid, entry);
    }
  }

  void _onState(int paneId) {
    final w = _watched[paneId];
    if (w == null) return;
    final sid = sidOf(paneId);
    _scheduleFlush(sid);
    _scheduleListing();
    final s = w.state;
    final request = _requestOf(s);
    if (request != w.attention) _attend(paneId, w, request);
    final items = s.timeline.items;
    for (var i = w.items; i < items.length; i++) {
      final item = items[i];
      if (item is! TurnEndItem || item.outcome == TurnOutcome.cancelled) {
        continue;
      }
      final threshold = _doneThreshold();
      if (threshold == null || item.elapsed < threshold) continue;
      _pushDone(paneId, w, item);
    }
    w.items = items.length;
  }

  /// The request [s] waits for, the one its header shows; null: none.
  static int? _requestOf(AiSessionState s) =>
      s.currentPermission?.id ?? s.currentAsk?.id;

  /// The session of pane [paneId] waits for [request] now, or for nothing.
  /// A new request is pushed at once when nobody shows it ([_lookAt]), and
  /// looked at again when the phones that mirror the session had their
  /// [ackGrace] to take it, and when it has waited [overdueAfter].
  void _attend(int paneId, _Watch w, int? request) {
    w
      ..attention = request
      ..stop()
      ..overdue = false;
    final s = w.state;
    // Answered or withdrawn: its id is never used again.
    w.pushed.retainWhere(
      (id) =>
          s.permissions.any((p) => p.id == id) || s.asks.any((a) => a.id == id),
    );
    if (request == null || _push == null || w.pushed.contains(request)) {
      return;
    }
    _startGrace(paneId, w);
    w.overdueTimer = Timer(overdueAfter, () {
      w
        ..overdueTimer = null
        ..overdue = true;
      if (identical(_watched[paneId], w)) _lookAt(paneId);
    });
    _lookAt(paneId);
  }

  void _startGrace(int paneId, _Watch w) {
    w.grace?.cancel();
    w
      ..graceOver = false
      ..grace = Timer(ackGrace, () {
        w
          ..grace = null
          ..graceOver = true;
        if (identical(_watched[paneId], w)) _lookAt(paneId, graceEnded: true);
      });
  }

  /// Phones stopped mirroring [sids]: a request they showed may be shown by
  /// nobody now.
  void _lookAgain(Iterable<String> sids) {
    for (final sid in {...sids}) {
      final paneId = _paneOf(sid);
      if (paneId != null) _lookAt(paneId);
    }
  }

  /// Pushes the request session [paneId] waits for when nobody shows it
  /// (V2-2 D11): no phone that mirrors the session shows it — took it
  /// (acknowledged a header that asks it), or may still take it within its
  /// [ackGrace] — and the window does not show it, or the request has
  /// waited [overdueAfter]. When the grace ends, only a phone that stayed
  /// silent makes it go: one that left the session by itself is no sign of
  /// a dead socket (the minute still comes). A phone that only lists still
  /// gets the push: the app shows it as an in-app banner while open. Never
  /// twice for one request, and at most one per [pushEvery] for a session.
  void _lookAt(int paneId, {bool graceEnded = false}) {
    final w = _watched[paneId];
    final push = _push;
    final request = w?.attention;
    if (_disposed ||
        w == null ||
        push == null ||
        request == null ||
        w.pushed.contains(request)) {
      return;
    }
    final sid = sidOf(paneId);
    var silent = false;
    for (final phone in _phones.values) {
      final sub = phone.subs[sid];
      if (sub == null) continue;
      if (!w.graceOver || sub.shown(request)) return; // a phone shows it
      silent = true;
    }
    if (graceEnded && !silent) return;
    if (!w.overdue && _seenOnDesktop(paneId)) return;
    // The limit is of "needs you" pushes among themselves: a done push just
    // before must not hide the question that follows it.
    final now = _now();
    final last = w.needsPushedAt;
    if (last != null) {
      // A clock set back says nothing of how long ago: do not hide it.
      final since = now.difference(last);
      if (!since.isNegative && since < pushEvery) return;
    }
    w
      ..needsPushedAt = now
      ..pushed.add(request);
    // A permission is named by its action title (N3); a question by nothing
    // of what it asks (M2).
    final permission = w.state.currentPermission;
    _sendPush(
      push,
      AiPush(
        kind: AiPushKind.needsInput,
        agentName: w.state.agentName,
        sid: sid,
        detail: permission == null ? null : clipText(permission.title, 240),
        question: permission == null,
      ),
    );
  }

  /// A long turn ended (V2-2 D11): pushed unless a phone has the session
  /// open or the window shows it.
  void _pushDone(int paneId, _Watch w, TurnEndItem item) {
    final push = _push;
    if (push == null) return;
    final sid = sidOf(paneId);
    if (_phones.values.any((p) => p.subs.containsKey(sid))) return;
    if (_seenOnDesktop(paneId)) return;
    _sendPush(
      push,
      AiPush(
        kind: AiPushKind.done,
        agentName: w.state.agentName,
        sid: sid,
        turn: item.turn,
        elapsed: item.elapsed,
      ),
    );
  }

  void _sendPush(AiPushSink push, AiPush message) {
    try {
      push(message);
    } on Object {
      // A push that cannot be sent is lost; this runs inside the runtime's
      // loop over its listeners (or a timer), which an error must not cut
      // short.
    }
  }

  /// Whether the user looks at the pane now. A window that cannot say is
  /// taken as not looking: a push too many beats one too few.
  bool _seenOnDesktop(int paneId) {
    try {
      return _source.seenOnDesktop(paneId);
    } on Object {
      return false;
    }
  }

  /// The "long turn" threshold; null (off) when the window cannot say.
  Duration? _doneThreshold() {
    try {
      return _source.doneThreshold;
    } on Object {
      return null;
    }
  }

  // ------------------------------------------------------------- listing --

  void _scheduleListing() {
    if (_listTimer != null || !_phones.values.any((p) => p.listing)) return;
    _listTimer = Timer(listEvery, () {
      _listTimer = null;
      for (final MapEntry(key: id, value: phone) in [..._phones.entries]) {
        if (phone.listing) _sendListing(id, phone);
      }
    });
  }

  void _sendListing(String mobileId, _Phone phone) {
    final String text;
    try {
      text = _listingText(
        AiListing(
          sessions: [
            for (final e in _source.sessions)
              AiSessionInfo(
                sid: sidOf(e.paneId),
                agentId: e.agentId,
                agentName: e.agentName,
                title: e.state?.label ?? e.title,
                state:
                    e.unavailable ??
                    (e.state == null
                        ? AiRemoteState.stopped
                        : aiRemoteStateOf(e.state!)),
                cwd: e.cwd,
                since: e.state?.turn?.startedAt.millisecondsSinceEpoch,
                waiting: e.state == null ? null : aiWaitingOf(e.state!),
                acpSessionId: e.state?.sessionId ?? e.acpSessionId,
              ),
          ],
          agents: _source.agents,
          folders: _source.folders,
          defaultAgent: _source.defaultAgent,
        ),
      );
    } on Object {
      return; // the window's code failed: the phone keeps its last list
    }
    if (text == phone.sentListing) return;
    phone.sentListing = text;
    _send(
      mobileId,
      AiListResult(
        available: true,
        body: Uint8List.fromList(utf8.encode(text)),
      ),
    );
  }

  /// [listing] as JSON within [kAiRecordBytes]: while it is too big the
  /// longest of sessions, folders and agents loses its last entry. A body
  /// over [kAiMaxBodyBytes] would make the channel drop; a shorter list is
  /// better than none.
  String _listingText(AiListing listing) {
    final whole = jsonEncode(listing.toJson());
    var size = utf8Length(whole);
    if (size <= kAiRecordBytes) return whole;
    final sessions = _Cut(listing.sessions, (s) => s.toJson());
    final folders = _Cut(listing.folders, (f) => f.toJson());
    final agents = _Cut(listing.agents, (a) => a.toJson());
    final parts = <_Cut<Object?>>[sessions, folders, agents];
    while (size > kAiRecordBytes) {
      final longest = parts.reduce((a, b) => b.bytes > a.bytes ? b : a);
      if (longest.entries.isEmpty) {
        return jsonEncode(const AiListing().toJson()); // nothing left to cut
      }
      size -= longest.dropLast();
    }
    return jsonEncode(
      AiListing(
        sessions: sessions.entries,
        agents: agents.entries,
        folders: folders.entries,
        defaultAgent: listing.defaultAgent,
      ).toJson(),
    );
  }

  // -------------------------------------------------------------- mirror --

  void _attach(String mobileId, _Phone phone, String sid, AiHave? have) {
    try {
      _attachSession(mobileId, phone, sid, have);
    } on Object {
      // The window's code failed (a runtime that cannot be made): the phone
      // is told the session is gone, and the attach is not left unanswered.
      _leave(phone, sid);
      _closed(mobileId, sid);
    }
  }

  /// `ai.closed {gone}`, unless the name is too long to be one of ours: the
  /// answer would be as big as the question.
  void _closed(String mobileId, String sid) {
    if (sid.length <= _maxSidLength) {
      _send(mobileId, AiClosed(sid: sid, reason: 'gone'));
    }
  }

  void _attachSession(String mobileId, _Phone phone, String sid, AiHave? have) {
    final paneId = _paneOf(sid);
    final entry = paneId == null
        ? null
        : _source.sessions.where((e) => e.paneId == paneId).firstOrNull;
    if (paneId == null || entry == null) {
      _leave(phone, sid);
      _closed(mobileId, sid);
      return;
    }
    final state = _source.control(paneId, start: true)?.state ?? entry.state;
    if (state == null) {
      // It cannot run: the phone shows why (set up on the computer) and
      // waits for a runtime to come.
      _leave(phone, sid);
      phone.parked.add(sid);
      _sendUnavailable(mobileId, phone, sid, entry);
      return;
    }
    var sub = phone.subs[sid];
    if (sub == null || !identical(sub.state, state)) {
      sub = _subscribe(phone, sid, state);
    }
    phone.parked.remove(sid);
    phone.earlier.remove(sid); // the phone starts from this snapshot
    _rescan(); // a runtime may just have been made
    if (!identical(phone.subs[sid], sub)) return; // the rescan ended it
    _sendAll(mobileId, phone, sid, sub.attach(have));
    // A request waits already: this phone gets its own time to take it (the
    // others keep theirs until then too).
    final w = _watched[paneId];
    if (w != null &&
        identical(w.state, state) &&
        w.attention != null &&
        !w.pushed.contains(w.attention) &&
        _push != null) {
      _startGrace(paneId, w);
    }
  }

  /// The snapshot of a session that cannot run: its header says why, without
  /// items. The names are the tab's and the folder's, cut like a listing's.
  /// Its `seq` goes on from what the phone was sent of the session.
  void _sendUnavailable(
    String mobileId,
    _Phone phone,
    String sid,
    AiSessionEntry entry,
  ) {
    final seq = (phone.seqs[sid] ?? 0) + 1;
    phone.seqs[sid] = seq;
    final cwd = entry.cwd;
    _send(
      mobileId,
      AiSnapshot(
        sid: sid,
        seq: seq,
        body: encodeBody({
          'v': kAiWireVersion,
          'g': 0,
          'from': 0,
          'n': 0,
          'reset': true,
          'head': {
            'phase': 'stopped',
            'agent': entry.agentId,
            'name': clipText(entry.agentName, 200),
            'title': clipText(entry.title, 400),
            'cwd': ?(cwd == null ? null : clipText(cwd, 600)),
            'unavailable': (entry.unavailable ?? AiRemoteState.noFolder).wire,
          },
          'items': const <Object?>[],
        }),
      ),
    );
  }

  /// Sends [out] as mirror messages of [sid]. A body over [kAiMaxBodyBytes]
  /// is never sent: it would drop the whole channel, terminals included. The
  /// phone is told the session is gone and mirrors it no more.
  void _sendAll(
    String mobileId,
    _Phone phone,
    String sid,
    List<AiOutgoing> out,
  ) {
    for (final o in out) {
      if (o.body.length > kAiMaxBodyBytes) {
        _drop(phone, sid);
        _send(mobileId, AiClosed(sid: sid, reason: 'gone'));
        return;
      }
      _send(
        mobileId,
        o.snapshot
            ? AiSnapshot(sid: sid, seq: o.seq, body: o.body)
            : AiUpdate(sid: sid, seq: o.seq, body: o.body),
      );
    }
  }

  /// The page of older items [phone] asked for, once the window has room.
  /// The subscription does not hold a page back by itself: without this
  /// check a phone could make the window overflow.
  void _sendEarlier(String mobileId, _Phone phone, String sid) {
    final before = phone.earlier[sid];
    final sub = phone.subs[sid];
    if (before == null || sub == null || !sub.canSend) return;
    phone.earlier.remove(sid);
    _sendAll(mobileId, phone, sid, sub.earlier(before));
  }

  void _scheduleFlush(String sid) {
    if (_flushTimers.containsKey(sid)) return;
    if (!_phones.values.any((p) => p.subs.containsKey(sid))) return;
    final last = _lastFlush[sid];
    var wait = last == null
        ? Duration.zero
        : flushEvery - _now().difference(last);
    // Within [0, flushEvery], even when the clock was set back.
    if (wait.isNegative) wait = Duration.zero;
    if (wait > flushEvery) wait = flushEvery;
    _flushTimers[sid] = Timer(wait, () {
      _flushTimers.remove(sid);
      _flush(sid);
    });
  }

  void _flush(String sid) {
    if (_disposed) return;
    _lastFlush[sid] = _now();
    for (final MapEntry(key: mobileId, value: phone) in [..._phones.entries]) {
      final sub = phone.subs[sid];
      if (sub == null || !sub.canSend) continue;
      _sendAll(mobileId, phone, sid, sub.delta());
    }
  }

  // ------------------------------------------------------------ requests --

  /// [run] answers a refusal code, or null when done.
  void _command(
    String mobileId,
    String sid,
    int rid,
    String? Function(AiControl control) run,
  ) {
    String? code;
    try {
      final control = _controlOf(sid);
      code = control == null ? 'not_found' : run(control);
    } on AiRefused catch (refusal) {
      code = refusal.code; // the window's own reason (V2-2 D7)
    } on Object {
      code = 'refused'; // the window's code failed: still one answer
    }
    _send(mobileId, AiResult(rid: rid, ok: code == null, code: code));
  }

  AiControl? _controlOf(String sid) {
    final paneId = _paneOf(sid);
    if (paneId == null) return null;
    if (!_source.sessions.any((e) => e.paneId == paneId)) return null;
    return _source.control(paneId);
  }

  /// The answer goes to [phone] only: if it is gone by then, or came back on
  /// a new channel, nothing is sent (a result belongs to the request that
  /// made it).
  Future<void> _prompt(
    String mobileId,
    _Phone phone,
    String sid,
    int rid,
    String text,
  ) async {
    String? code;
    try {
      final control = _controlOf(sid);
      if (control == null) {
        code = 'not_found';
      } else if (text.trim().isEmpty) {
        code = 'refused';
      } else if (utf8Length(text) > kAiMaxPromptBytes) {
        code = 'too_large';
      } else if (control.state.queue.length >= AiSessionState.maxQueue) {
        code = 'queue_full';
      } else if (!await control.send([TextBlock(text)])) {
        code = 'refused';
      }
    } on Object {
      code = 'refused'; // nothing escapes into the window's zone
    }
    _send(mobileId, AiResult(rid: rid, ok: code == null, code: code), phone);
  }

  void _answer(String mobileId, AiAnswer a) {
    _command(mobileId, a.sid, a.rid, (c) {
      final s = c.state;
      final permission = a.permission;
      if (permission != null) {
        final p = s.permissions.where((p) => p.id == permission).firstOrNull;
        if (p == null) return 'stale';
        final option = a.option;
        if (option == null ||
            !p.request.options.any((o) => o.optionId == option)) {
          return 'refused';
        }
        c.answerPermission(permission, option);
        return null;
      }
      final askId = a.ask;
      if (askId == null) return 'refused';
      final ask = s.asks.where((q) => q.id == askId).firstOrNull;
      if (ask == null) return 'stale';
      switch (a.action) {
        case 'decline':
          c.answerAsk(askId, const ElicitDecline());
        case 'cancel':
          c.answerAsk(askId, const ElicitCancel());
        case 'accept':
          final form = ask.request;
          final content = decodeBody(a.body);
          if (form is! ElicitationForm || content == null) return 'refused';
          final values = <String, Object>{
            for (final e in content.entries)
              if (e.value != null) e.key: e.value!,
          };
          if (!form.accepts(values)) return 'refused';
          c.answerAsk(askId, ElicitAccept(values));
        default:
          return 'refused';
      }
      return null;
    });
  }

  /// Only an agent the computer lists as ready, in a folder it offers (V2-2
  /// D9): the phone's words are checked here, not left to the window. The
  /// answer goes to [phone] only, like a prompt's.
  Future<void> _open(
    String mobileId,
    _Phone phone,
    int rid,
    String agent,
    String folder,
  ) async {
    int? paneId;
    try {
      final choice = _source.agents.where((a) => a.id == agent).firstOrNull;
      if (choice != null &&
          choice.ready &&
          _source.folders.any((f) => f.key == folder)) {
        paneId = await _source.open(agent, folder);
        if (paneId != null) _rescan();
      }
    } on Object {
      paneId = null;
    }
    _send(
      mobileId,
      AiResult(
        rid: rid,
        ok: paneId != null,
        code: paneId == null ? 'refused' : null,
        sid: paneId == null ? null : sidOf(paneId),
      ),
      phone,
    );
  }

  // --------------------------------------------------------------- utils --

  bool _take(_Phone phone) {
    final now = _now();
    // Never negative: a clock set back must not empty the phone's budget.
    final seconds = max(0, now.difference(phone.refilled).inMicroseconds) / 1e6;
    phone
      ..tokens = min(
        _AiBudget.burst,
        phone.tokens + seconds * _AiBudget.perSecond,
      )
      ..refilled = now;
    if (phone.tokens < 1) return false;
    phone.tokens -= 1;
    return true;
  }

  static int? _ridOf(AiMessage m) => switch (m) {
    AiPrompt(:final rid) ||
    AiAnswer(:final rid) ||
    AiCancel(:final rid) ||
    AiForceStop(:final rid) ||
    AiUnqueue(:final rid) ||
    AiOpen(:final rid) => rid,
    _ => null,
  };

  /// A phone that is gone gets nothing (an answer may come after it left).
  /// With [to], only that one: a phone that came back on a new channel is
  /// another [_Phone] and does not get the answer to a request it never made.
  void _send(String mobileId, AiMessage message, [_Phone? to]) {
    final phone = _phones[mobileId];
    if (_disposed || phone == null || (to != null && !identical(phone, to))) {
      return;
    }
    _out.add(OutboundMessage(mobileId, message));
  }
}
