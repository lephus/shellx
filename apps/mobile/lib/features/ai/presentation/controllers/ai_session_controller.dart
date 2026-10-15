import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

/// V2-2 §5.2: one AI session on the phone. It mirrors the session while the
/// page is open (attached when made, detached on [dispose]) and sends only
/// what the user explicitly asked for: nothing is ever answered, or sent again,
/// by itself (V2-2 D13). A request answers its failure code (null: done) so
/// the page can say it ([AiWords.failure]); nothing here is ever logged but
/// error types.
///
/// V2-2b: it holds the computer's AI listing while the page is open (R3: what the computer can do, B1; the
/// sessions it has, B22), and follows its session to its new sid when the computer restarted ShellX (B22).
@injectable
class AiSessionController extends Controller {
  AiSessionController(
    @factoryParam this.agentId,
    @factoryParam String sid,
    SessionHolder session,
    this._drafts,
    this._registry,
  ) : _sid = sid,
      _backend = session.backend.peek() {
    final backend = _backend;
    if (backend == null) {
      _closed.value = true;
      return;
    }
    final MachineSession machine;
    try {
      machine = backend.machine(agentId);
    } on StateError {
      // Not pinned any more: forgotten by an `untrusted` handshake the client ran on its own. The
      // machine says why; the page does not call it "closed on the computer".
      _machineState.value = const MachineFailed(MachineConnectionFailure.untrusted);
      _closed.value = true;
      return;
    }
    _machine = machine;
    _machineState.value = machine.state;
    _machineStates = machine.states.listen((s) => _set(_machineState, s));
    _follow(machine.ai.attach(sid));
    _onChange();
    unawaited(_holdListing(machine));
  }

  /// B22: how long a session closed on the computer is looked for under another sid.
  static const Duration findAgainFor = Duration(seconds: 30);

  final String agentId;
  String _sid;
  final ShellxBackend? _backend;
  final AiDrafts _drafts;
  final WorkspaceRegistry _registry;
  MachineSession? _machine;
  AiSessionHandle? _link;
  StreamSubscription<void>? _changes;
  StreamSubscription<MachineConnectionState>? _machineStates;
  Timer? _tick;
  bool _disposed = false;

  /// The machine's workspace once the page holds its AI listing (R3), and how to let the listing go.
  TerminalWorkspace? _workspace;
  void Function()? _releaseListing;
  StreamSubscription<AiListing>? _listingFeed;

  /// B22: who the session is — the agent's own session id, the agent, the folder — as far as the phone knows.
  String? _acp;
  String? _agent;
  String? _cwd;

  /// B22: the time to find the session again runs; [_findAgainOver] once it ran out.
  Timer? _findAgainTimer;
  bool _findAgainOver = false;

  /// What the text field held last ([keepDraft]): a session found again under another sid keeps it.
  String _lastDraft = '';

  /// The app is on screen (the page tells, see [setForeground]).
  bool _foreground = true;

  /// The answer to a permission or question is on its way (only after it the buttons wait for the
  /// computer).
  bool _answerInFlight = false;

  final Signal<int> _version = signal(0);
  final Signal<bool> _closed = signal(false);
  final Signal<MachineConnectionState> _machineState = signal(const MachineIdle());
  final Signal<bool> _sending = signal(false);
  final Signal<int?> _answering = signal(null);
  final Signal<bool> _stopping = signal(false);
  final Signal<DateTime> _now = signal(DateTime.now());
  final Signal<bool> _reattached = signal(false);

  /// The session shown: the one the page was opened for, or the one it was found again as after the
  /// computer restarted ShellX (B22).
  String get sid => _sid;

  /// The backend the page shows the relay state of; null when signed out.
  ShellxBackend? get backend => _backend;

  /// The machine's AI sessions; null when the page cannot show this session.
  AiMachine? get ai => _machine?.ai;

  /// V2-2b B1 (R3): whether the computer can do [feature] (an [AiFeature]) now.
  bool can(String feature) => _machine?.ai.can(feature) ?? false;

  /// The computer's AI listing as far as it can be trusted (the page holds it while open); null when none
  /// came yet.
  AiListing? get listing => _workspace?.aiListing;

  /// Bumps on every change of the mirror, the link or the listing (read it in a Watch).
  ReadonlySignal<int> get version => _version;

  /// The page cannot show this session (signed out, machine not pinned).
  ReadonlySignal<bool> get closed => _closed;

  /// The state of the machine's channel. The link stays `attaching` while the machine is failed or
  /// untrusted, so this is what says the computer cannot be reached.
  ReadonlySignal<MachineConnectionState> get machineState => _machineState;
  ReadonlySignal<bool> get sending => _sending;

  /// The permission or question being answered, from the tap until the computer's header shows it
  /// gone (its buttons wait), or null.
  ReadonlySignal<int?> get answering => _answering;
  ReadonlySignal<bool> get stopping => _stopping;

  /// Ticks every second while a turn runs on a live link, with the app on screen ("Đang chạy · 0:12").
  ReadonlySignal<DateTime> get now => _now;

  /// B22: the session was found again under another sid after the computer restarted ShellX ("Đã nối lại
  /// sau khi ShellX khởi động lại."), until the user sends something.
  ReadonlySignal<bool> get reattached => _reattached;

  /// What the user left in the text field of this session the last time, empty when nothing (in memory;
  /// see [AiDrafts]). Of this session on this machine: the same id on another computer is another one.
  String get draft => _drafts.of(_draftKey);

  /// The text field now holds [text]. A session that is over for good keeps no draft: a message that was
  /// refused after it closed is not put back — unless the session is found again (B22), which takes it.
  void keepDraft(String text) {
    _lastDraft = text;
    if (_over) return;
    _drafts.keep(_draftKey, text);
  }

  String get _draftKey => '$agentId/$_sid';

  /// The computer dropped the session (`gone`) or ShellX quit there (`desktop_closed`): nothing more will
  /// be said in it. Not `detached` (a page of this phone leaving), `unavailable` or `unreadable`: they may
  /// pass. See [AiWords.closed].
  bool get _over {
    final link = _link;
    return link != null &&
        link.state == AiLinkState.closed &&
        (link.closedReason == 'gone' || link.closedReason == 'desktop_closed');
  }

  /// The app comes to the foreground (true) or goes away from it (false): the page tells, since it is
  /// the page that sees the lifecycle. In the background nothing counts the turn's time (a second tick
  /// wakes the phone for a header nobody sees); coming back sets the clock at once.
  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _syncTick();
  }

  AiMirror? get mirror => _link?.mirror;
  MirrorHead? get head => _link?.mirror.head;
  AiLinkState get linkState => _link?.state ?? AiLinkState.closed;
  String? get closedReason => _link?.closedReason;

  /// The page's text field may send: live, the computer takes prompts.
  bool get canSend => !_closed.peek() && linkState == AiLinkState.live && (head?.canSend ?? false) && !_sending.peek();

  /// Sends [text] (queued on the computer while a turn runs). Null when
  /// taken; else the failure code. A message that failed on the way may have
  /// landed ([AiWords.outcomeUnknown]): it is never sent again by itself.
  Future<String?> send(String text) async {
    final machine = _machine;
    if (machine == null || text.trim().isEmpty) return 'refused';
    if (_sending.peek()) return AiWords.inFlight;
    _set(_reattached, false);
    _set(_sending, true);
    try {
      await machine.ai.prompt(_sid, text);
      return null;
    } catch (error) {
      return _failure(error);
    } finally {
      _set(_sending, false);
    }
  }

  /// The user's pick on the permission panel (V2-1 D10): one explicit tap.
  Future<String?> answerPermission(MirrorPermission permission, PermissionOption option) {
    final sid = _sid;
    return _answer(permission.id, () => _machine!.ai.answerPermission(sid, permission.id, option.optionId));
  }

  /// The user's answer to a question (V2-1 D22).
  Future<String?> answerAsk(int ask, ElicitationResponse response) {
    final sid = _sid;
    return _answer(ask, () => _machine!.ai.answerAsk(sid, ask, response));
  }

  /// Stop the turn (the desktop's Esc).
  Future<String?> stop() async {
    final machine = _machine;
    if (machine == null) return 'refused';
    if (_stopping.peek()) return AiWords.inFlight;
    _set(_stopping, true);
    try {
      await machine.ai.cancel(_sid);
      return null;
    } catch (error) {
      return _failure(error);
    } finally {
      _set(_stopping, false);
    }
  }

  /// "Dừng hẳn", once the computer offers it.
  Future<String?> forceStop() {
    final sid = _sid;
    return _simple(() => _machine!.ai.forceStop(sid));
  }

  /// Drops queued prompt [id].
  Future<String?> unqueue(int id) {
    final sid = _sid;
    return _simple(() => _machine!.ai.unqueue(sid, id));
  }

  /// "Tải thêm".
  void loadEarlier() => _link?.loadEarlier();

  /// V2-2b B11: the choices of "Chế độ và model", or why they cannot be had (a code for [AiWords.failure]).
  Future<({AiConfigView? view, String? code})> loadConfig() async {
    final machine = _machine;
    if (machine == null) return (view: null, code: 'refused');
    try {
      return (view: await machine.ai.config(sid), code: null);
    } catch (error) {
      return (view: null, code: _failure(error));
    }
  }

  /// V2-2b B11: one choice of an option (one explicit tap, one request, never sent again): null when the
  /// computer took it, else the failure code (`on_computer`: chosen on the computer only).
  Future<String?> setConfig(String id, Object value) => _simple(() => _machine!.ai.setConfig(sid, id, value));

  /// V2-2b B11: the mode of an agent with only modes; as [setConfig].
  Future<String?> setMode(String modeId) => _simple(() => _machine!.ai.setMode(sid, modeId));

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tick?.cancel();
    _findAgainTimer?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_machineStates?.cancel());
    unawaited(_listingFeed?.cancel());
    _releaseListing?.call();
    _link?.detach();
  }

  /// R3: the page holds the computer's AI listing while it is open — it says what the computer can do
  /// (B1) and which sessions it has (B22). A page opened from a notification has not listed the computer's
  /// sessions yet: it asks once, which also tells the computer's protocol.
  Future<void> _holdListing(MachineSession machine) async {
    if (machine.ai.protocol == null) {
      try {
        await machine.listSessions();
      } catch (error) {
        // Offline, or a handshake that failed: the strips say so; the features stay off until a list answers.
        if (kDebugMode) debugPrint('AI page list error: ${error.runtimeType}');
      }
    }
    if (_disposed) return;
    final TerminalWorkspace workspace;
    try {
      workspace = _registry.forMachine(agentId);
    } on StateError {
      return; // Not pinned any more: the machine says why.
    }
    _workspace = workspace;
    _releaseListing = workspace.holdAiListing();
    // Every listing tells the page ([version]): a button of a feature ([can]) shows as soon as a listing
    // names it, and the protocol learned above counts at once. Cancelled on [dispose].
    _listingFeed = machine.ai.listings.listen((_) => _onChange());
    _onChange();
  }

  /// An answer is one tap and one request. Once the computer took it, the buttons keep waiting until
  /// its header shows the request gone (or the link is lost, and what it holds then decides), so a
  /// second tap cannot answer the same request again. A failed one lets them work again.
  Future<String?> _answer(int id, Future<void> Function() run) async {
    if (_machine == null) return 'refused';
    if (_answering.peek() != null) return AiWords.inFlight;
    _answerInFlight = true;
    _set(_answering, id);
    try {
      await run();
      return null;
    } catch (error) {
      _set(_answering, null);
      return _failure(error);
    } finally {
      _answerInFlight = false;
      _releaseAnswer();
    }
  }

  Future<String?> _simple(Future<void> Function() run) async {
    if (_machine == null) return 'refused';
    try {
      await run();
      return null;
    } catch (error) {
      return _failure(error);
    }
  }

  /// The code of a request that failed. The computer's own come with [AiRequestException]. A
  /// [MachineConnectionException] is the channel: lost or silent, the request may have landed
  /// ([AiWords.outcomeUnknown]); a handshake that failed sent nothing, and the machine says why.
  String _failure(Object error) {
    switch (error) {
      case AiRequestException(:final code):
        return code;
      case MachineConnectionException(:final failure):
        return switch (failure) {
          MachineConnectionFailure.agentOffline || MachineConnectionFailure.timeout => AiWords.outcomeUnknown,
          MachineConnectionFailure.untrusted => AiWords.untrusted,
          MachineConnectionFailure.protocolUnsupported => AiWords.updateRequired,
        };
      default:
        if (kDebugMode) debugPrint('AI request error: ${error.runtimeType}');
        return AiWords.error;
    }
  }

  bool _stillAsking(int id) => head?.permission?.id == id || head?.ask?.id == id;

  /// Lets the buttons of an answer work again once the computer has moved on, or the link was lost.
  void _releaseAnswer() {
    final id = _answering.peek();
    if (id == null || _answerInFlight) return;
    if (!_stillAsking(id) || linkState != AiLinkState.live) _set(_answering, null);
  }

  /// Mirrors [link], and tells [_onChange] of each change of it.
  void _follow(AiSessionHandle link) {
    unawaited(_changes?.cancel());
    _link = link;
    _changes = link.changes.listen((_) => _onChange());
  }

  void _onChange() {
    if (_disposed) return;
    // Two pages of the same session share one link while it is open, and leaving one detaches it: the
    // page that stays takes a fresh link rather than show a session closed that is not.
    final link = _link;
    final machine = _machine;
    if (machine != null && link != null && link.state == AiLinkState.closed && link.closedReason == 'detached') {
      _follow(machine.ai.attach(_sid));
    }
    _remember();
    _syncTick();
    if (_over) {
      // A session that is over takes its draft with it (the drafts are bounded, but need not hold this one).
      _drafts.keep(_draftKey, '');
      _findAgain();
    }
    batch(() {
      _releaseAnswer();
      _version.value++;
    });
  }

  /// B22: who this session is, so that it can be found again under another sid. The listing says it the
  /// way it says every session (the folder cut as it cuts it); the header (V2-2b `acp`) knows the agent's
  /// session id even when the page came from a notification and no listing named the session yet.
  void _remember() {
    final seen = _machine?.ai.seen(_sid);
    final head = _link?.mirror.head;
    _acp = head?.acp ?? seen?.acpSessionId ?? _acp;
    _agent = seen?.agentId ?? (head == null || head.agentId.isEmpty ? null : head.agentId) ?? _agent;
    _cwd = seen?.cwd ?? head?.cwd ?? _cwd;
  }

  /// B22: the computer closed the session (`gone`, `desktop_closed`); after ShellX restarted there its tab
  /// may be back under another sid. For [findAgainFor] every listing is looked at: exactly one session of
  /// the same agent session, agent and folder is this one, and the page follows it; none or several, and
  /// the page stays closed (with "Mở danh sách phiên"). Never more than following: nothing is sent to it.
  void _findAgain() {
    if (_findAgainOver) return;
    _findAgainTimer ??= Timer(findAgainFor, () => _findAgainOver = true);
    final machine = _machine;
    final acp = _acp;
    final held = listing;
    if (machine == null || acp == null || held == null || !held.available) return;
    final matches = [
      for (final s in held.sessions)
        if (s.sid != _sid && s.acpSessionId == acp && s.agentId == _agent && s.cwd == _cwd) s,
    ];
    if (matches.length != 1) return;
    _followAgain(machine, matches.single.sid);
  }

  /// B22: the page shows [newSid] from now on; the text field's draft goes with it.
  void _followAgain(MachineSession machine, String newSid) {
    final old = _link;
    unawaited(_changes?.cancel());
    _changes = null;
    old?.detach(); // closed already: only let go
    _sid = newSid;
    _findAgainTimer?.cancel();
    _findAgainTimer = null;
    _findAgainOver = false;
    _follow(machine.ai.attach(newSid));
    if (_lastDraft.trim().isNotEmpty) _drafts.keep(_draftKey, _lastDraft);
    _set(_reattached, true);
  }

  /// The turn's clock runs while a turn runs on a link that is live, with the app on screen. After a
  /// loss nothing is known of the turn (it may have ended long ago), a closed link has none, and the
  /// background has nobody to look at it.
  void _syncTick() {
    final counting = !_disposed && _foreground && linkState == AiLinkState.live && head?.turn != null;
    if (counting && _tick == null) {
      _set(_now, DateTime.now()); // the time since the turn began is read at once, not a second later
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _set(_now, DateTime.now()));
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  void _set<T>(Signal<T> s, T value) {
    if (_disposed) return;
    s.value = value;
  }
}
