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
  @override
  Duration? doneThreshold = const Duration(seconds: 30);
  int? opened;
  final openedWith = <(String, String)>[];

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

  void remove(int paneId) {
    entries.removeWhere((e) => e.paneId == paneId);
    controls.remove(paneId);
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<AiSessionEntry> get sessions => List.of(entries);

  @override
  List<AiAgentChoice> get agents => const [
    AiAgentChoice(id: 'claude', name: 'Claude'),
  ];

  @override
  List<AiFolderChoice> folders = const [
    AiFolderChoice(key: 'ws:a', name: 'shop', path: '/p'),
  ];

  @override
  String? defaultAgent = 'claude';

  @override
  AiControl? control(int paneId, {bool start = false}) {
    if (start) started.add(paneId);
    return controls[paneId];
  }

  @override
  Future<int?> open(String agentId, String folderKey) async {
    openedWith.add((agentId, folderKey));
    final id = opened;
    if (id != null) add(id);
    return id;
  }

  @override
  bool seenOnDesktop(int paneId) => seen.contains(paneId);
}

/// A hub over [source] whose messages are kept per phone.
final class HubRig {
  HubRig({FakeAiSource? source, this.pushes})
    : source = source ?? FakeAiSource() {
    hub = AiPhoneHub(
      source: this.source,
      push: pushes?.add,
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
