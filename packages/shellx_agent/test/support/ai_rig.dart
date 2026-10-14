import 'dart:async';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';

final aiT0 = DateTime.utc(2026, 10, 14, 9);

/// What a runtime does with a phone's request, on a plain state: records
/// it and changes the state the way `AiRuntime` would.
final class FakeAiControl implements AiControl {
  FakeAiControl(this.state);

  @override
  final AiSessionState state;
  final sent = <String>[];
  final permissions = <(int, String)>[];
  final asks = <(int, ElicitationResponse)>[];
  var cancels = 0;
  var forceStops = 0;
  bool accept = true;

  /// Set: `send`, `cancel` and `forceStop` throw it (a runtime that fails).
  Object? failWith;

  /// Set: `send` waits for it first (a prompt still on its way).
  Completer<void>? hold;

  void _fail() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<bool> send(List<ContentBlock> prompt) async {
    final gate = hold;
    if (gate != null) await gate.future;
    _fail();
    if (!accept) return false;
    sent.add(blockText(prompt));
    if (state.turn == null) {
      state.beginTurn(prompt, aiT0);
    } else {
      state.enqueue(prompt);
    }
    return true;
  }

  @override
  void cancel() {
    _fail();
    cancels++;
    state.turn?.cancelRequested = true;
    state.touch();
  }

  @override
  Future<void> forceStop() async {
    _fail();
    forceStops++;
  }

  @override
  void answerPermission(int id, String optionId) {
    permissions.add((id, optionId));
    state.resolvePermission(id, PermissionSelected(optionId));
  }

  @override
  void answerAsk(int id, ElicitationResponse response) {
    asks.add((id, response));
    state.resolveAsk(id, response);
  }
}

/// A window with AI sessions on plain states.
final class FakeAiSource implements AiSessionSource {
  final _changes = StreamController<void>.broadcast(sync: true);
  final entries = <AiSessionEntry>[];
  final controls = <int, FakeAiControl>{};
  final started = <int>[];
  final seen = <int>{};
  int? opened;
  final openedWith = <(String, String)>[];

  /// Members that throw when called, by name: `sessions`, `agents`,
  /// `folders`, `control`, `open`, `seen`, `threshold` (a window whose
  /// adapter fails).
  final failing = <String>{};

  void _maybeFail(String member) {
    if (failing.contains(member)) throw StateError('$member failed');
  }

  Duration? _doneThreshold = const Duration(seconds: 30);
  List<AiAgentChoice> _agents = const [
    AiAgentChoice(id: 'claude', name: 'Claude'),
  ];
  List<AiFolderChoice> _folders = const [
    AiFolderChoice(key: 'ws:a', name: 'shop', path: '/p'),
  ];

  @override
  Duration? get doneThreshold {
    _maybeFail('threshold');
    return _doneThreshold;
  }

  set doneThreshold(Duration? value) => _doneThreshold = value;

  /// Adds AI pane [paneId] with a ready state (or none, [runs] false).
  AiSessionState add(
    int paneId, {
    bool runs = true,
    AiRemoteState? unavailable,
    String title = 'Phiên AI mới',
  }) {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: '/p',
    )..setPhase(AgentPhase.ready);
    entries.add(
      AiSessionEntry(
        paneId: paneId,
        agentId: 'claude',
        agentName: 'Claude',
        title: title,
        cwd: '/p',
        state: runs ? state : null,
        unavailable: unavailable,
      ),
    );
    if (runs) controls[paneId] = FakeAiControl(state);
    _changes.add(null);
    return state;
  }

  /// Adds AI pane [paneId] on a [state] the test made.
  void addState(
    int paneId,
    AiSessionState state, {
    String title = 'Phiên AI mới',
  }) {
    entries.add(
      AiSessionEntry(
        paneId: paneId,
        agentId: state.agentId,
        agentName: 'Claude',
        title: title,
        cwd: '/p',
        state: state,
      ),
    );
    controls[paneId] = FakeAiControl(state);
    _changes.add(null);
  }

  /// A new runtime for [paneId]: another state in the same tab.
  AiSessionState replace(int paneId) {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: '/p',
    )..setPhase(AgentPhase.ready);
    final i = entries.indexWhere((e) => e.paneId == paneId);
    final old = entries[i];
    entries[i] = AiSessionEntry(
      paneId: paneId,
      agentId: old.agentId,
      agentName: old.agentName,
      title: old.title,
      cwd: old.cwd,
      state: state,
    );
    controls[paneId] = FakeAiControl(state);
    _changes.add(null);
    return state;
  }

  /// The runtime of [paneId] is forgotten (a folder was changed, its agent
  /// switched off): the tab stays without a state. [unavailable] says why
  /// it cannot run; null: it just has none now (a new one comes).
  void forget(int paneId, {AiRemoteState? unavailable}) {
    final i = entries.indexWhere((e) => e.paneId == paneId);
    final old = entries[i];
    entries[i] = AiSessionEntry(
      paneId: paneId,
      agentId: old.agentId,
      agentName: old.agentName,
      title: old.title,
      cwd: old.cwd,
      unavailable: unavailable,
    );
    controls.remove(paneId);
    _changes.add(null);
  }

  void remove(int paneId) {
    entries.removeWhere((e) => e.paneId == paneId);
    controls.remove(paneId);
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<AiSessionEntry> get sessions {
    _maybeFail('sessions');
    return List.of(entries);
  }

  @override
  List<AiAgentChoice> get agents {
    _maybeFail('agents');
    return _agents;
  }

  set agents(List<AiAgentChoice> value) => _agents = value;

  @override
  List<AiFolderChoice> get folders {
    _maybeFail('folders');
    return _folders;
  }

  set folders(List<AiFolderChoice> value) => _folders = value;

  @override
  String? defaultAgent = 'claude';

  @override
  AiControl? control(int paneId, {bool start = false}) {
    _maybeFail('control');
    if (start) started.add(paneId);
    return controls[paneId];
  }

  /// Set: `open` waits for it first (a tab still being made).
  Completer<void>? holdOpen;

  @override
  Future<int?> open(String agentId, String folderKey) async {
    _maybeFail('open');
    openedWith.add((agentId, folderKey));
    final gate = holdOpen;
    if (gate != null) await gate.future;
    final id = opened;
    if (id != null) add(id);
    return id;
  }

  @override
  bool seenOnDesktop(int paneId) {
    _maybeFail('seen');
    return seen.contains(paneId);
  }
}

/// A hub over [source] whose messages are kept per phone. Pushes go to
/// [pushes], or to [sink] when a test needs one that does something else.
final class HubRig {
  HubRig({FakeAiSource? source, this.pushes, AiPushSink? sink})
    : source = source ?? FakeAiSource() {
    hub = AiPhoneHub(
      source: this.source,
      push: sink ?? pushes?.add,
      now: () => now,
      epoch: 'ep',
    );
    hub.outbound.listen(sent.add);
  }

  final FakeAiSource source;
  final List<AiPush>? pushes;
  late final AiPhoneHub hub;
  final sent = <OutboundMessage>[];
  DateTime now = aiT0;

  List<AiMessage> to(String phone) => [
    for (final o in sent)
      if (o.mobileId == phone) o.message as AiMessage,
  ];

  T last<T extends AiMessage>(String phone) => to(phone).whereType<T>().last;

  /// The mirror of [sid] built from every body [phone] got.
  AiMirror mirror(String phone, String sid) {
    final mirror = AiMirror();
    for (final m in to(phone)) {
      switch (m) {
        case AiSnapshot(sid: final s, :final body) when s == sid:
          mirror.apply(decodeBody(body)!, snapshot: true);
        case AiUpdate(sid: final s, :final body) when s == sid:
          mirror.apply(decodeBody(body)!, snapshot: false);
        default:
          break;
      }
    }
    return mirror;
  }
}
