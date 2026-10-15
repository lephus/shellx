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

  /// Every prompt as it came (V2-2b: what a phone sends with its text).
  final prompts = <AiPhonePrompt>[];

  /// V2-2b B13: the files `@` offers in the session's folder.
  List<String> projectFiles = const [];

  /// Every query [files] was asked.
  final queries = <String>[];
  final permissions = <(int, String)>[];
  final asks = <(int, ElicitationResponse)>[];
  var cancels = 0;
  var forceStops = 0;
  bool accept = true;

  /// Set: `send`, `cancel` and `forceStop` throw it (a runtime that fails).
  Object? failWith;

  /// Set: `send` waits for it first (a prompt still on its way).
  Completer<void>? hold;

  /// Set: `answerPermission` and `answerAsk` refuse with it (an answer the
  /// window takes only on the computer).
  AiRefused? refuse;

  void _fail() {
    final error = failWith;
    if (error != null) throw error;
  }

  void _refuse() {
    final refusal = refuse;
    if (refusal != null) throw refusal;
  }

  /// Like `AiRuntime.send` for a phone: the prompt is the phone's (B24).
  @override
  Future<bool> send(AiPhonePrompt prompt) async {
    final gate = hold;
    if (gate != null) await gate.future;
    _fail();
    if (!accept) return false;
    // V2-2b B13, R18: the window sends only files `@` offers.
    if (prompt.files.any((f) => !projectFiles.contains(f))) {
      throw const AiRefused('refused');
    }
    sent.add(prompt.text);
    prompts.add(prompt);
    final blocks = [TextBlock(prompt.text)];
    if (state.turn == null) {
      state.beginTurn(blocks, aiT0, source: PromptSource.phone);
    } else {
      state.enqueue(blocks, source: PromptSource.phone);
    }
    return true;
  }

  /// V2-2b B13: every file containing [query] (the hub keeps eight).
  @override
  Future<List<String>> files(String query) async {
    queries.add(query);
    return [
      for (final f in projectFiles)
        if (f.contains(query)) f,
    ];
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
    _refuse();
    permissions.add((id, optionId));
    state.resolvePermission(id, PermissionSelected(optionId));
  }

  @override
  void answerAsk(int id, ElicitationResponse response) {
    _refuse();
    asks.add((id, response));
    state.resolveAsk(id, response);
  }

  /// V2-2b B11: the choices set, in order.
  final configs = <(String, Object)>[];
  final modes = <String>[];

  /// Set: `setConfig` and `setMode` throw it (the agent said no).
  Object? failConfig;

  @override
  Future<void> setConfig(String id, Object value) async {
    final error = failConfig;
    if (error != null) throw error;
    configs.add((id, value));
    state.configOptions = [
      for (final o in state.configOptions ?? const <ConfigOption>[])
        o.id == id ? o.withValue(value) : o,
    ];
    state.touch();
  }

  @override
  Future<void> setMode(String modeId) async {
    final error = failConfig;
    if (error != null) throw error;
    modes.add(modeId);
    state.modes = state.modes?.withCurrent(modeId);
    state.touch();
  }

  /// V2-2b B17: what `listSessions` answers (null: the agent says nothing),
  /// and the cursors it was asked with.
  ListSessionsResult? history;
  final cursors = <String?>[];

  @override
  Future<ListSessionsResult?> listSessions({String? cursor}) async {
    _fail();
    cursors.add(cursor);
    return history;
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
  /// `folders`, `control`, `open`, `folder` (`chooseFolder`), `seen`,
  /// `threshold` (a window whose adapter fails).
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

  /// Panes whose runtime this window makes when asked for it ([control]), as
  /// `AiRuntimes.runtimeFor` does for a tab that can run and has none yet (a
  /// restored tab, an agent switched back on).
  final lazy = <int>{};

  @override
  AiControl? control(int paneId, {bool start = false}) {
    _maybeFail('control');
    if (start) started.add(paneId);
    if (controls[paneId] == null && lazy.contains(paneId)) _make(paneId);
    return controls[paneId];
  }

  void _make(int paneId) {
    final i = entries.indexWhere((e) => e.paneId == paneId);
    if (i < 0 || entries[i].unavailable != null) return;
    final old = entries[i];
    final state = AiSessionState(
      agentId: old.agentId,
      agentName: old.agentName,
      cwd: '/p',
    )..setPhase(AgentPhase.ready);
    entries[i] = AiSessionEntry(
      paneId: paneId,
      agentId: old.agentId,
      agentName: old.agentName,
      title: old.title,
      cwd: old.cwd,
      state: state,
    );
    controls[paneId] = FakeAiControl(state);
    // Listed at once; the window tells of it a little later, coalesced
    // (`AiRuntimes.made`).
    scheduleMicrotask(() => _changes.add(null));
  }

  /// Set: `open` waits for it first (a tab still being made).
  Completer<void>? holdOpen;

  /// V2-2b B17: the earlier sessions `open` was asked to reopen, in order.
  final resumed = <String>[];

  @override
  Future<int?> open(String agentId, String folderKey, {String? resume}) async {
    _maybeFail('open');
    openedWith.add((agentId, folderKey));
    if (resume != null) resumed.add(resume);
    final gate = holdOpen;
    if (gate != null) await gate.future;
    final id = opened;
    if (id != null) add(id);
    return id;
  }

  /// V2-2b B18: what `chooseFolder` was asked: (pane, folder key).
  final folderChosen = <(int, String)>[];

  /// Set: `chooseFolder` answers false (a window that will not).
  var refuseFolder = false;

  /// Like the desktop's: only a pane without a folder, only a key offered;
  /// the pane then has the folder, and its runtime is made when asked for
  /// ([lazy]).
  @override
  Future<bool> chooseFolder(int paneId, String folderKey) async {
    _maybeFail('folder');
    folderChosen.add((paneId, folderKey));
    final folder = _folders.where((f) => f.key == folderKey).firstOrNull;
    final i = entries.indexWhere((e) => e.paneId == paneId);
    if (refuseFolder ||
        folder == null ||
        i < 0 ||
        entries[i].unavailable != AiRemoteState.noFolder) {
      return false;
    }
    final old = entries[i];
    entries[i] = AiSessionEntry(
      paneId: paneId,
      agentId: old.agentId,
      agentName: old.agentName,
      title: old.title,
      cwd: folder.path ?? '/p',
    );
    lazy.add(paneId);
    _changes.add(null);
    return true;
  }

  @override
  bool seenOnDesktop(int paneId) {
    _maybeFail('seen');
    return seen.contains(paneId);
  }
}

/// A hub over [source] whose messages are kept per phone. Pushes go to
/// [pushes], or to [sink] when a test needs one that does something else.
/// Its clock is [now], or [clock] (a fake one) when given.
final class HubRig {
  HubRig({
    FakeAiSource? source,
    this.pushes,
    AiPushSink? sink,
    DateTime Function()? clock,
  }) : source = source ?? FakeAiSource() {
    hub = AiPhoneHub(
      source: this.source,
      push: sink ?? pushes?.add,
      now: clock ?? () => now,
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
