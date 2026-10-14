import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_words.dart';

/// V2-2 §5.2: one AI session on the phone. It mirrors the session while the
/// page is open (attached when made, detached on [dispose]) and sends only
/// what the user explicitly asked for: nothing is ever answered, or sent again,
/// by itself (V2-2 D13). A request answers its failure code (null: done) so
/// the page can say it ([AiWords.failure]); nothing here is ever logged but
/// error types.
@injectable
class AiSessionController extends Controller {
  AiSessionController(@factoryParam this.agentId, @factoryParam this.sid, SessionHolder session, this._drafts)
    : _backend = session.backend.peek() {
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
  }

  final String agentId;
  final String sid;
  final ShellxBackend? _backend;
  final AiDrafts _drafts;
  MachineSession? _machine;
  AiSessionHandle? _link;
  StreamSubscription<void>? _changes;
  StreamSubscription<MachineConnectionState>? _machineStates;
  Timer? _tick;
  bool _disposed = false;

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

  /// The backend the page shows the relay state of; null when signed out.
  ShellxBackend? get backend => _backend;

  /// Bumps on every change of the mirror or the link (read it in a Watch).
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

  /// What the user left in the text field of this session the last time, empty when nothing (in memory;
  /// see [AiDrafts]). Of this session on this machine: the same id on another computer is another one.
  String get draft => _drafts.of(_draftKey);

  /// The text field now holds [text]. A session that is over for good keeps no draft: a message that was
  /// refused after it closed is not put back.
  void keepDraft(String text) {
    if (_over) return;
    _drafts.keep(_draftKey, text);
  }

  String get _draftKey => '$agentId/$sid';

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
    _set(_sending, true);
    try {
      await machine.ai.prompt(sid, text);
      return null;
    } catch (error) {
      return _failure(error);
    } finally {
      _set(_sending, false);
    }
  }

  /// The user's pick on the permission panel (V2-1 D10): one explicit tap.
  Future<String?> answerPermission(MirrorPermission permission, PermissionOption option) =>
      _answer(permission.id, () => _machine!.ai.answerPermission(sid, permission.id, option.optionId));

  /// The user's answer to a question (V2-1 D22).
  Future<String?> answerAsk(int ask, ElicitationResponse response) =>
      _answer(ask, () => _machine!.ai.answerAsk(sid, ask, response));

  /// Stop the turn (the desktop's Esc).
  Future<String?> stop() async {
    final machine = _machine;
    if (machine == null) return 'refused';
    if (_stopping.peek()) return AiWords.inFlight;
    _set(_stopping, true);
    try {
      await machine.ai.cancel(sid);
      return null;
    } catch (error) {
      return _failure(error);
    } finally {
      _set(_stopping, false);
    }
  }

  /// "Dừng hẳn", once the computer offers it.
  Future<String?> forceStop() => _simple(() => _machine!.ai.forceStop(sid));

  /// Drops queued prompt [id].
  Future<String?> unqueue(int id) => _simple(() => _machine!.ai.unqueue(sid, id));

  /// "Tải thêm".
  void loadEarlier() => _link?.loadEarlier();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tick?.cancel();
    unawaited(_changes?.cancel());
    unawaited(_machineStates?.cancel());
    _link?.detach();
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
      _follow(machine.ai.attach(sid));
    }
    _syncTick();
    if (_over) {
      // A session that is over takes its draft with it (the drafts are bounded, but need not hold this one).
      _drafts.keep(_draftKey, '');
    }
    batch(() {
      _releaseAnswer();
      _version.value++;
    });
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
