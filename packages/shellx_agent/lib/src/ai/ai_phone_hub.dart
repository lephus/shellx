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
  void answerPermission(int id, String optionId);
  void answerAsk(int id, ElicitationResponse response);
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
  /// focused, pane focused): no push for it (V2-2 D11).
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
    this.turn,
    this.elapsed,
  });

  final AiPushKind kind;
  final String agentName;
  final String sid;

  /// What the agent waits for ("Sửa src/main.ts").
  final String? detail;
  final int? turn;
  final Duration? elapsed;

  /// For `ai.push` (window → background service).
  Map<String, Object?> toFields() => {
    'kind': kind.name,
    'name': agentName,
    'sid': sid,
    'detail': ?detail,
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
  _Watch(this.state, this.listener, this.generation, this.items);
  final AiSessionState state;
  final void Function() listener;
  final int generation;
  int? attention;
  int items;

  /// When the last "needs you" push went; a done push does not count.
  DateTime? needsPushedAt;
}

/// The window's side of AI on phones (V2-2 D1, D2, D5, D11): lists the AI
/// sessions, mirrors the ones a phone attaches (at most one update per
/// [flushEvery] each, within each phone's window), runs the phone's
/// requests — only explicit ones, checked against what is pending now —
/// and asks for a push when a session needs the user and no phone has it
/// open and the window does not show it. Never logs anything a session holds.
final class AiPhoneHub implements AiEndpoint {
  AiPhoneHub({
    required AiSessionSource source,
    AiPushSink? push,
    DateTime Function()? now,
    String? epoch,
    this.flushEvery = const Duration(milliseconds: 100),
    this.listEvery = const Duration(milliseconds: 250),
    this.pushEvery = const Duration(seconds: 30),
  }) : _source = source,
       _push = push,
       _now = now ?? DateTime.now,
       epoch = epoch ?? _newEpoch() {
    _changes = source.changes.listen((_) => _rescan());
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
        _drop(phone, sid);
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
        unawaited(_prompt(mobileId, sid, rid, text));
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
        unawaited(_open(mobileId, rid, agent, folder));
      case AiListResult() ||
          AiSnapshot() ||
          AiUpdate() ||
          AiClosed() ||
          AiResult():
        break; // desktop → phone types are never taken from a phone
    }
  }

  /// Forgets the phone: its mirrors, its listing, its budget. The router may
  /// say it more than once; nothing is sent to a phone that is not known.
  @override
  void phoneGone(String mobileId) => _phones.remove(mobileId);

  @override
  void allPhonesGone() => _phones.clear();

  /// Stops listening; the window is going.
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    _flushTimers.clear();
    _listTimer?.cancel();
    for (final w in _watched.values) {
      w.state.removeListener(w.listener);
    }
    _watched.clear();
    _phones.clear();
  }

  // ------------------------------------------------------------ sessions --

  void _rescan() {
    if (_disposed) return;
    final entries = _source.sessions;
    final live = <int>{};
    for (final e in entries) {
      final state = e.state;
      if (state == null) continue;
      live.add(e.paneId);
      final watch = _watched[e.paneId];
      if (watch != null && identical(watch.state, state)) continue;
      if (watch != null) {
        watch.state.removeListener(watch.listener);
        _resubscribe(e.paneId, state);
      }
      void listener() => _onState(e.paneId);
      state.addListener(listener);
      _watched[e.paneId] = _Watch(
        state,
        listener,
        _generation(state),
        state.timeline.items.length,
      )..attention = state.currentPermission?.id ?? state.currentAsk?.id;
    }
    for (final paneId in [..._watched.keys]) {
      if (live.contains(paneId)) continue;
      final w = _watched.remove(paneId)!;
      w.state.removeListener(w.listener);
    }
    // Sessions that went away close on every phone that mirrors them.
    final present = {for (final e in entries) sidOf(e.paneId)};
    for (final MapEntry(key: mobileId, value: phone) in _phones.entries) {
      for (final sid in [...phone.subs.keys]) {
        if (present.contains(sid)) continue;
        _drop(phone, sid);
        _send(mobileId, AiClosed(sid: sid, reason: 'gone'));
      }
    }
    _scheduleListing();
  }

  /// [phone] mirrors [sid] no more (nor waits for a page of it).
  void _drop(_Phone phone, String sid) {
    phone.subs.remove(sid);
    phone.earlier.remove(sid);
  }

  int _generation(AiSessionState state) =>
      _generations[state] ??= _nextGeneration++;

  /// The session got a new state (a new runtime): phones start over.
  void _resubscribe(int paneId, AiSessionState state) {
    final sid = sidOf(paneId);
    for (final MapEntry(key: mobileId, value: phone) in _phones.entries) {
      if (!phone.subs.containsKey(sid)) continue;
      final sub = AiSubscription(state, generation: _generation(state));
      _drop(phone, sid);
      phone.subs[sid] = sub;
      _sendAll(mobileId, phone, sid, sub.attach(null));
    }
  }

  void _onState(int paneId) {
    final w = _watched[paneId];
    if (w == null) return;
    final sid = sidOf(paneId);
    _scheduleFlush(sid);
    _scheduleListing();
    final s = w.state;
    final attention = s.currentPermission?.id ?? s.currentAsk?.id;
    if (attention != null && attention != w.attention) {
      _maybePush(paneId, w, AiPushKind.needsInput, detail: aiWaitingOf(s));
    }
    w.attention = attention;
    final items = s.timeline.items;
    for (var i = w.items; i < items.length; i++) {
      final item = items[i];
      if (item is! TurnEndItem || item.outcome == TurnOutcome.cancelled) {
        continue;
      }
      final threshold = _source.doneThreshold;
      if (threshold == null || item.elapsed < threshold) continue;
      _maybePush(
        paneId,
        w,
        AiPushKind.done,
        turn: item.turn,
        elapsed: item.elapsed,
      );
    }
    w.items = items.length;
  }

  void _maybePush(
    int paneId,
    _Watch w,
    AiPushKind kind, {
    String? detail,
    int? turn,
    Duration? elapsed,
  }) {
    final push = _push;
    if (push == null) return;
    final sid = sidOf(paneId);
    // A phone that has the session open shows it already (V2-2 D11). A
    // phone that only lists still gets the push: the app shows it as an
    // in-app banner while open, a notification otherwise.
    if (_phones.values.any((p) => p.subs.containsKey(sid))) return;
    if (_source.seenOnDesktop(paneId)) return;
    if (kind == AiPushKind.needsInput) {
      // The limit is of "needs you" pushes among themselves: a done push
      // just before must not hide the question that follows it.
      final now = _now();
      final last = w.needsPushedAt;
      if (last != null) {
        // A clock set back says nothing of how long ago: do not hide it.
        final since = now.difference(last);
        if (!since.isNegative && since < pushEvery) return;
      }
      w.needsPushedAt = now;
    }
    push(
      AiPush(
        kind: kind,
        agentName: w.state.agentName,
        sid: sid,
        detail: detail,
        turn: turn,
        elapsed: elapsed,
      ),
    );
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
    final listing = AiListing(
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
    );
    final text = _listingText(listing);
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
    final paneId = _paneOf(sid);
    final entry = paneId == null
        ? null
        : _source.sessions.where((e) => e.paneId == paneId).firstOrNull;
    if (paneId == null || entry == null) {
      _drop(phone, sid);
      // A name too long to be one of ours is not repeated: the answer would
      // be as big as the question.
      if (sid.length <= _maxSidLength) {
        _send(mobileId, AiClosed(sid: sid, reason: 'gone'));
      }
      return;
    }
    final state = _source.control(paneId, start: true)?.state ?? entry.state;
    if (state == null) {
      // It cannot run yet: the phone shows why (set up on the computer). The
      // names are the tab's and the folder's: cut like a listing's.
      _drop(phone, sid);
      final cwd = entry.cwd;
      _send(
        mobileId,
        AiSnapshot(
          sid: sid,
          seq: 1,
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
      return;
    }
    _rescan(); // a runtime may just have been made
    var sub = phone.subs[sid];
    if (sub == null || !identical(sub.state, state)) {
      sub = AiSubscription(state, generation: _generation(state));
      phone.subs[sid] = sub;
    }
    phone.earlier.remove(sid); // the phone starts from this snapshot
    _sendAll(mobileId, phone, sid, sub.attach(have));
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
    final control = _controlOf(sid);
    String? code;
    if (control == null) {
      code = 'not_found';
    } else {
      try {
        code = run(control);
      } on Object {
        code = 'refused'; // a runtime that fails still answers, once
      }
    }
    _send(mobileId, AiResult(rid: rid, ok: code == null, code: code));
  }

  AiControl? _controlOf(String sid) {
    final paneId = _paneOf(sid);
    if (paneId == null) return null;
    if (!_source.sessions.any((e) => e.paneId == paneId)) return null;
    return _source.control(paneId);
  }

  Future<void> _prompt(
    String mobileId,
    String sid,
    int rid,
    String text,
  ) async {
    final control = _controlOf(sid);
    String? code;
    if (control == null) {
      code = 'not_found';
    } else if (text.trim().isEmpty) {
      code = 'refused';
    } else if (utf8Length(text) > kAiMaxPromptBytes) {
      code = 'too_large';
    } else if (control.state.queue.length >= AiSessionState.maxQueue) {
      code = 'queue_full';
    } else {
      try {
        if (!await control.send([TextBlock(text)])) code = 'refused';
      } on Object {
        code = 'refused'; // nothing escapes into the window's zone
      }
    }
    _send(mobileId, AiResult(rid: rid, ok: code == null, code: code));
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

  Future<void> _open(
    String mobileId,
    int rid,
    String agent,
    String folder,
  ) async {
    int? paneId;
    try {
      paneId = await _source.open(agent, folder);
    } on Object {
      paneId = null;
    }
    if (paneId != null) _rescan();
    _send(
      mobileId,
      AiResult(
        rid: rid,
        ok: paneId != null,
        code: paneId == null ? 'refused' : null,
        sid: paneId == null ? null : sidOf(paneId),
      ),
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
  void _send(String mobileId, AiMessage message) {
    if (_disposed || !_phones.containsKey(mobileId)) return;
    _out.add(OutboundMessage(mobileId, message));
  }
}
