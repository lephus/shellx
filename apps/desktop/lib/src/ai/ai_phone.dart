import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
// Not the terminal-sharing message of that name: the agents' readiness.
import 'package:shellx_agent/shellx_agent.dart' hide AgentReady;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../agent/notify_threshold.dart';
import '../config/config_controller.dart' show shellxConfigProvider;
import '../mux/daemon_state.dart';
import '../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import '../ui/window_focus.dart';
import 'ai_agents.dart';
import 'ai_image_encode.dart';
import 'ai_off_thread.dart';
import 'ai_phone_files.dart';
import 'ai_phone_reverts.dart';
import 'ai_project_files.dart';
import 'ai_runtimes.dart';
import 'ai_undo.dart';

/// V2-2 D2: the window's AI sessions as the phone hub sees them, over
/// V2-1b's tab list and runtimes. Nothing here starts an agent except a
/// phone's attach (an explicit "open this session") or "Phiên AI mới".
final class DesktopAiSource implements AiSessionSource {
  DesktopAiSource(this._ref) {
    _subscriptions.addAll([
      _ref.listen(terminalTabsProvider, (_, _) => _changed()),
      _ref.listen(sidebarWorkspacesProvider, (_, _) => _changed()),
      // The agents and the default one by their sources: a derived provider
      // (`aiAgentsProvider`, `aiDefaultAgentProvider`) is computed again only
      // once something reads it (`window_focus.dart`), and with the window
      // hidden nothing may. The rescan that follows reads `aiAgentsProvider`,
      // so the runtimes of an agent switched off stop then (V2-1 D21).
      _ref.listen(
        shellxConfigProvider.select((s) => s.config.aiAgentClaude),
        (_, _) => _changed(),
      ),
      _ref.listen(aiCustomAgentsProvider, (_, _) => _changed()),
      _ref.listen(aiReadinessProvider, (_, _) => _changed()),
      _ref.listen(aiDefaultAgentChoiceProvider, (_, _) => _changed()),
    ]);
    // A runtime made (its pane shown, a phone's attach) is a session with a
    // state from now on. One replaced or forgotten changes its tab (another
    // folder, the tab closed) or the agents (switched off, removed): both
    // listened to above.
    _made = _ref
        .read(aiRuntimesProvider.notifier)
        .made
        .listen((_) => _changed());
  }

  final Ref _ref;
  final _changes = StreamController<void>.broadcast(sync: true);
  final _subscriptions = <ProviderSubscription<Object?>>[];
  late final StreamSubscription<int> _made;

  /// Microtask-coalesced: a burst of tab changes is one rescan.
  var _queued = false;

  void _changed() {
    if (_queued || _changes.isClosed) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
    unawaited(_made.cancel());
    unawaited(_changes.close());
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// The AI sessions in the sidebar's order, as the interface says.
  @override
  List<AiSessionEntry> get sessions {
    final runtimes = _ref.read(aiRuntimesProvider.notifier);
    final agents = _ref.read(aiAgentsProvider);
    return [
      for (final tab in _tabsInSidebarOrder())
        if (tab.ai case final pane?)
          _entry(pane, runtimes.existing(pane.id)?.state, agents),
    ];
  }

  /// The tabs as the sidebar shows them, top to bottom: workspace by
  /// workspace, pinned ones first (not the order they were opened in). A
  /// tab the sidebar has not placed yet comes after them.
  List<TerminalTab> _tabsInSidebarOrder() {
    final tabs = _ref.read(terminalTabsProvider).tabs;
    final byId = {for (final t in tabs) t.id: t};
    final placed = <int>{};
    return [
      for (final id in _ref.read(sidebarWorkspacesProvider).orderedTabIds)
        if (placed.add(id)) ?byId[id],
      for (final t in tabs)
        if (!placed.contains(t.id)) t,
    ];
  }

  AiSessionEntry _entry(
    AiPaneState pane,
    AiSessionState? state,
    List<AgentSpec> agents,
  ) => AiSessionEntry(
    paneId: pane.id,
    agentId: pane.agentId,
    agentName: pane.agentName,
    title: pane.title,
    cwd: pane.cwd,
    acpSessionId: pane.sessionId,
    state: state,
    // A live runtime is listed live, whatever else changed meanwhile: a tab
    // never flaps to "cannot run" between its runtime made and listed.
    unavailable: state == null ? _cannotRun(pane, agents) : null,
  );

  /// Why the tab of [pane] cannot run now, which phones are told (D14): no
  /// folder chosen yet (V2-1 D5), or its agent switched off, removed or not
  /// known here (V2-1 D21). Null: it can; its runtime is made when the pane
  /// shows or a phone attaches.
  static AiRemoteState? _cannotRun(AiPaneState pane, List<AgentSpec> agents) {
    if (pane.cwd == null) return AiRemoteState.noFolder;
    if (aiAgentById(agents, pane.agentId) == null) {
      return AiRemoteState.agentOff;
    }
    return null;
  }

  @override
  List<AiAgentChoice> get agents {
    final readiness = _ref.read(aiReadinessProvider);
    return [
      for (final a in _ref.read(aiAgentsProvider))
        AiAgentChoice(
          id: a.id,
          name: a.name,
          // Not resolved yet counts as ready (V2-1b: "New AI session" never
          // waits); a missing agent then says so in the session itself.
          ready: readiness[a.id] == null || readiness[a.id] is AgentReady,
        ),
    ];
  }

  @override
  List<AiFolderChoice> get folders {
    final l10n = _ref.read(appL10nProvider);
    final out = <AiFolderChoice>[];
    final seen = <String>{};
    for (final w in _ref.read(sidebarWorkspacesProvider).workspaces) {
      final root = w.root;
      if (root == null || w.ssh != null || !seen.add(root)) continue;
      out.add(
        AiFolderChoice(
          key: 'ws:${w.id}',
          name: w.displayName(l10n),
          path: root,
        ),
      );
    }
    for (final tab in _tabsInSidebarOrder()) {
      final cwd = tab.ai?.cwd;
      if (cwd == null || !seen.add(cwd)) continue;
      final name =
          cwd.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ??
          cwd;
      out.add(AiFolderChoice(key: 'path:$cwd', name: name, path: cwd));
    }
    return out;
  }

  @override
  String? get defaultAgent => _ref.read(aiDefaultAgentProvider)?.id;

  /// Never throws: a runtime that cannot be made is a session the hub cannot
  /// control (the error's type goes to the log, nothing of the session).
  @override
  AiControl? control(int paneId, {bool start = false}) {
    try {
      final runtime = _ref.read(aiRuntimesProvider.notifier).runtimeFor(paneId);
      if (runtime == null) return null;
      // D15: a tab whose agent never ran (restored, or not shown yet) starts,
      // as when it is shown. One that ran and stopped ("Dừng hẳn") stays
      // stopped until the user sends something: a phone that attaches again
      // (its channel came back) must not start it, nor run what was queued
      // before the stop (D13). The pane starts each runtime once, likewise.
      if (start &&
          runtime.state.phase == AgentPhase.stopped &&
          runtime.state.sessionId == null) {
        unawaited(runtime.start());
      }
      return _RuntimeControl(_ref, paneId, runtime);
    } on Object catch (error) {
      debugPrint('ShellX: AI session for a phone failed: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<int?> open(String agentId, String folderKey, {String? resume}) async {
    final path = folders.where((f) => f.key == folderKey).firstOrNull?.path;
    final agent = aiAgentById(_ref.read(aiAgentsProvider), agentId);
    if (path == null || agent == null) return null;
    final tabId = _ref
        .read(terminalTabsProvider.notifier)
        .openAiTab(
          agentId: agent.id,
          agentName: agent.name,
          title: _ref.read(appL10nProvider).aiNewSession,
          cwd: path,
          // V2-2b B17: reopens that earlier session (`session/load`), as the
          // desktop's History does (V2-1 D15).
          sessionId: resume,
          workspace: _workspaceFor(folderKey, path),
          select: false, // the computer's user keeps their tab (V2-2 D9)
        );
    final pane = _ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tabId)
        .firstOrNull
        ?.ai;
    if (pane == null) return null;
    // Its agent starts at once (D9). A runtime that cannot be made leaves no
    // tab behind: the phone hears "refused" (§7), the computer shows nothing.
    if (control(pane.id, start: true) == null) {
      _ref.read(terminalTabsProvider.notifier).close(tabId);
      return null;
    }
    return pane.id;
  }

  /// V2-2b B18: what the tab's own "Use this folder" does
  /// (`AiPaneView._useFolder`), for a tab that has no folder yet: a runtime it
  /// may have is forgotten and the pane gets [folderKey]'s folder (a new
  /// session: no session id). False when the pane has a folder, is gone, or
  /// the key is not offered now. The runtime is made, and its agent started,
  /// when a phone attaches or the pane shows (V2-2 D15).
  @override
  Future<bool> chooseFolder(int paneId, String folderKey) async {
    final path = folders.where((f) => f.key == folderKey).firstOrNull?.path;
    final pane = _ref
        .read(terminalTabsProvider)
        .tabOfPane(paneId)
        ?.aiPanes[paneId];
    if (path == null || pane == null || pane.cwd != null) return false;
    _ref.read(aiRuntimesProvider.notifier).forget(paneId);
    _ref
        .read(terminalTabsProvider.notifier)
        .updateAiPane(paneId, (p) => p.copyWith(cwd: path, sessionId: null));
    return true;
  }

  /// Where a new tab in [folderKey] goes (D9): the workspace it names
  /// (`ws:<id>`), else the workspace of the AI tab whose folder it is; null:
  /// the one the computer shows.
  String? _workspaceFor(String folderKey, String path) {
    if (folderKey.startsWith('ws:')) return folderKey.substring(3);
    final tab = _tabsInSidebarOrder()
        .where((t) => t.ai?.cwd == path)
        .firstOrNull;
    if (tab == null) return null;
    return _ref.read(sidebarWorkspacesProvider).workspaceOf(tab.id);
  }

  /// D11: the window active and the pane focused. Focus says nothing of a
  /// user who walked away, so the hub pushes a request anyway once it waited
  /// a minute (`AiPhoneHub.overdueAfter`).
  @override
  bool seenOnDesktop(int paneId) {
    if (!readWindowActive(_ref.read)) return false;
    final selected = _ref.read(terminalTabsProvider).selected;
    return selected != null && selected.focusedPaneId == paneId;
  }

  @override
  Duration? get doneThreshold =>
      notifyThreshold(_ref.read(settingsStoreProvider));
}

/// A pane's runtime as the hub drives it for a phone.
final class _RuntimeControl implements AiControl {
  _RuntimeControl(this._ref, this._paneId, this._runtime);

  final Ref _ref;

  /// The AI pane whose runtime this is: its pane says what a phone reverted.
  final int _paneId;
  final AiRuntime _runtime;

  @override
  AiSessionState get state => _runtime.state;

  /// V2-2 D7, V2-2b B12, B13, B24: what a phone sends, as the phone's — its
  /// text, then its images as `image` blocks, base64 off the UI isolate when
  /// they are many bytes, then a `resource_link` for each file, as the
  /// composer does (V2-1 D16). A file goes only when `@` offers it in the
  /// session's folder now and it is there (R18): else nothing is sent
  /// (`refused`). The agent's answer to `initialize` may have come while the
  /// images were encoded: one that takes no images is sent none
  /// (`no_images`), asked with no `await` before `send`.
  @override
  Future<bool> send(AiPhonePrompt prompt) async {
    final links = prompt.files.isEmpty
        ? const <ContentBlock>[]
        : await _links(prompt.files);
    final images = prompt.images;
    final data = images.isEmpty
        ? const <String>[]
        : await aiEncodeImages(_ref.read(aiOffThreadProvider), [
            for (final i in images) i.bytes,
          ]);
    if (images.isNotEmpty && aiTakesNoImages(_runtime.state)) {
      throw const AiRefused('no_images');
    }
    return _runtime.send([
      if (prompt.text.trim().isNotEmpty) TextBlock(prompt.text),
      for (final (i, image) in images.indexed)
        ImageBlock(data: data[i], mimeType: image.mime),
      ...links,
    ], source: PromptSource.phone);
  }

  /// V2-2b B13, R18: a `resource_link` for each of [files] — once each —, as
  /// the composer makes it (V2-1 D16); [AiRefused] (`refused`) for one `@`
  /// does not offer in the session's folder now, one that leaves the folder,
  /// or one that is not there.
  Future<List<ContentBlock>> _links(List<String> files) async {
    final state = _runtime.state;
    final cwd = state.cwd;
    final offered = {...await _ref.read(aiPhoneFileIndexProvider).files(state)};
    final links = <ContentBlock>[];
    for (final path in {...files}) {
      final file = p.join(cwd, path);
      if (!offered.contains(path) ||
          !p.isWithin(p.normalize(cwd), p.normalize(file)) ||
          !await File(file).exists()) {
        throw const AiRefused('refused');
      }
      links.add(
        ResourceLinkBlock(
          uri: Uri.file(file).toString(),
          name: p.basename(path),
          title: path,
        ),
      );
    }
    return links;
  }

  /// V2-2b B13: the files of the session's folder matching [query], as the
  /// composer's `@` offers them.
  @override
  Future<List<String>> files(String query) =>
      _ref.read(aiPhoneFileIndexProvider).match(_runtime.state, query);

  @override
  void cancel() => _runtime.cancel();

  @override
  Future<void> forceStop() => _runtime.forceStop();

  /// V2-1 R6, V2-2 D13: an option that turns on a mode acting without
  /// asking (Claude's "Yes, and bypass permissions") asks the Bypass question
  /// on the computer first. A phone has no such question: such an answer is
  /// given on the computer only (`on_computer`); the request stays open.
  @override
  void answerPermission(int id, String optionId) {
    final option = _runtime.state.permissions
        .where((p) => p.id == id)
        .firstOrNull
        ?.request
        .options
        .where((o) => o.optionId == optionId)
        .firstOrNull;
    final enables = option == null
        ? aiIsNoApprovalMode(optionId)
        : aiOptionEnablesNoApproval(option);
    if (enables) throw const AiRefused('on_computer');
    _runtime.answerPermission(id, optionId);
  }

  @override
  void answerAsk(int id, ElicitationResponse response) =>
      _runtime.answerAsk(id, response);

  @override
  Future<ListSessionsResult?> listSessions({String? cursor}) =>
      _runtime.listSessions(cursor: cursor);

  /// V2-2b B11: a choice from the phone, as the composer's chip makes it —
  /// sent to the agent, then remembered for its next sessions. The hub
  /// checked it against what the session offers; checked again here, so no
  /// way round the hub sets a mode acting without asking, nor any value of an
  /// option named like one (a select too: `yolo` with `on` / `off`): that is
  /// made on the computer, after its question (R16, V2-1 R6).
  @override
  Future<void> setConfig(String id, Object value) async {
    if (aiTurnsOnNoApproval(configId: id, value: value)) {
      throw const AiRefused('on_computer');
    }
    if (aiIsNoApprovalMode(id)) throw const AiRefused('on_computer');
    await _runtime.setConfig(id, value);
    await rememberConfig(
      _ref.read(settingsStoreProvider),
      _runtime.state.agentId,
      id,
      value,
    );
  }

  /// V2-2b B11: a legacy mode from the phone; as [setConfig] (the computer's
  /// mode chip remembers none).
  @override
  Future<void> setMode(String modeId) async {
    if (aiIsNoApprovalMode(modeId)) throw const AiRefused('on_computer');
    await _runtime.setMode(modeId);
  }

  /// The turn whose restore point a phone's [turn] means: that one, else
  /// the session's first; null when it has none (undo was off).
  int? _restoreTurn(int? turn) {
    final from = turn ?? aiTurnsOf(_runtime.state).first;
    return from == null || _runtime.checkpointOf(from) == null ? null : from;
  }

  /// V2-2b B19: what the Changes panel shows of [turn] (null: the session),
  /// read now — the same reads (`AiChangesPanel._load`).
  @override
  Future<AiChangesView> changes({int? turn}) async {
    final s = _runtime.state;
    final turns = aiTurnsOf(s);
    AiChangesView view([
      List<FileChange> files = const [],
      Set<String> after = const {},
    ]) => AiChangesView(
      scope: turn == null ? 'session' : 'turn',
      turn: turn,
      files: [for (final c in files) AiChangedFile.of(c)],
      after: [
        for (final c in files)
          if (after.contains(c.path)) c.path,
      ],
      first: turns.first,
      last: turns.last,
      done: turns.lastFinished,
      // Why there is nothing to undo, while no turn has a restore point.
      off: turns.last == null ? aiUndoOffOf(s)?.reason.name : null,
    );
    if (_restoreTurn(turn) == null) return view();
    final files = turn == null
        ? await _runtime.sessionChanges()
        : await _runtime.changesSince(turn);
    // git did not answer: said, not an empty list.
    if (files == null) throw const AiRefused('refused');
    final last = turn ?? turns.lastFinished;
    final after = last == null ? null : await _runtime.changedAfterTurn(last);
    return view(files, after ?? const {});
  }

  /// V2-2b B19, R18: one file's diff — a file of the changes as they are
  /// now, so inside the session folder — as the desktop's diff overlay reads
  /// it: before the turn against the disk, 1 MiB at most.
  @override
  Future<Map<String, Object?>> diff({int? turn, required String path}) async {
    final from = _restoreTurn(turn);
    if (from == null) throw const AiRefused('undo_off');
    final files = turn == null
        ? await _runtime.sessionChanges()
        : await _runtime.changesSince(turn);
    if (files == null) throw const AiRefused('refused');
    if (!files.any((c) => c.path == path)) throw const AiRefused('refused');
    final before = aiFileContentOf(await _runtime.fileBefore(from, path));
    final now = await _ref
        .read(aiProjectFilesProvider)
        .read(p.join(_runtime.state.cwd, path));
    if (before is AiFileBinary || now is AiFileBinary) {
      return {'path': path, 'binary': true};
    }
    if (before is AiFileTooLarge || now is AiFileTooLarge) {
      throw const AiRefused('too_big');
    }
    if (before is AiFileMissing && now is AiFileMissing) {
      return {'path': path, 'missing': true};
    }
    final texts = (
      path,
      before is AiFileText ? before.text : null,
      now is AiFileText ? now.text : '',
    );
    // Smoothness: the hub runs on the UI isolate, and a long file is cut off
    // it, as the diff overlay's lines are.
    final body = (texts.$2?.length ?? 0) + texts.$3.length > _inlineDiffChars
        ? await _ref.read(aiOffThreadProvider)(_fileDiffBody, texts)
        : _fileDiffBody(texts);
    if (body == null) throw const AiRefused('too_big');
    return body;
  }

  /// V2-2b B19: [AiUndo], as the panel's "Revert turn" — worked out again
  /// now, since what the phone saw may be old (RF4) — with the question of
  /// B14 asked through the phone (`confirm`). The pane says what went back.
  @override
  Future<int> revert({int? turn, String? keep}) async {
    if (_runtime.state.turn != null) throw const AiRefused('busy_turn');
    if (_restoreTurn(turn) == null) throw const AiRefused('undo_off');
    final undo = AiUndo(_runtime);
    final AiUndoPlan plan;
    switch (await undo.plan(turn: turn)) {
      case AiUndoBusy():
        throw const AiRefused('busy_turn');
      case AiUndoFailed():
        throw const AiRefused('refused');
      case AiUndoNothing():
        return 0;
      case final AiUndoPlan planned:
        plan = planned;
    }
    final touched = plan.touched;
    if (touched.isNotEmpty && keep == null) {
      throw AiRefused(
        'confirm',
        body: encodeRevertConfirm(
          touched: touched,
          someClean: plan.someClean,
          total: plan.paths.length,
        ),
      );
    }
    final done = await undo.apply(plan, keepTouched: keep == 'clean');
    if (!done.ok) throw AiRefused(done.busy ? 'busy_turn' : 'refused');
    final reverts = _ref.read(aiPhoneRevertsProvider);
    if (done.count > 0 && !reverts.isClosed) {
      reverts.add((paneId: _paneId, count: done.count));
    }
    return done.count;
  }
}

/// V2-2b B19: above this many characters in its two texts, the region of a
/// phone's diff is cut off the UI isolate (a file of 1 MiB whose every line
/// changed is ~100 ms of it; one of 64 KiB, a few).
const int _inlineDiffChars = 64 * 1024;

/// [aiFileDiffBody] of `(path, old text, new text)`: one argument, top-level,
/// so that it can run on another isolate ([OffThread]).
Map<String, Object?>? _fileDiffBody((String, String?, String) texts) =>
    aiFileDiffBody(path: texts.$1, oldText: texts.$2, newText: texts.$3);

/// V2-2 D11: where the hub's pushes go — the agent side's notifications
/// in-process, the background service in its mode (`ai.push`). `main.dart`
/// overrides it ([aiPushSinkFor]); null: no pushes (tests).
final aiPushSinkProvider = Provider<AiPushSink?>((ref) => null);

/// What `main.dart` sets [aiPushSinkProvider] to (V2-2 D11): in-process the
/// agent side's own [notifications] (null while they are off); with the
/// background service ([daemonMode]) `ai.push` on its current link, so the
/// service sends it with its account and under its limit.
Override aiPushSinkFor({
  required bool daemonMode,
  AgentNotifications? notifications,
}) => daemonMode
    ? aiPushSinkProvider.overrideWith((ref) {
        final client = ref.watch(daemonLinkProvider)?.client;
        return client == null ? null : muxAiPushSink(client);
      })
    : aiPushSinkProvider.overrideWithValue(notifications?.aiNotice);

/// In-process: the agent side's slot the hub serves phones through
/// ([startAiPhone]).
final class _AiSlotPlug {
  AiEndpointSlot? slot;

  /// The window stops serving phones: [hub] tells them while the slot still
  /// carries what it sends, then the slot answers "unavailable" (V2-2 D1).
  void close(AiPhoneHub hub) {
    hub.dispose();
    final plugged = slot;
    slot = null;
    if (plugged != null && identical(plugged.target, hub)) {
      plugged.target = null;
    }
  }
}

final _aiSlotPlugProvider = Provider<_AiSlotPlug>((ref) => _AiSlotPlug());

/// V2-2 D1: the window's side of AI on phones, made once per run. Read, not
/// watched: it lives as long as the window.
final aiPhoneHubProvider = Provider<AiPhoneHub>((ref) {
  final plug = ref.watch(_aiSlotPlugProvider);
  final source = DesktopAiSource(ref);
  final hub = AiPhoneHub(
    source: source,
    push: (push) => ref.read(aiPushSinkProvider)?.call(push),
  );
  ref.onDispose(() {
    plug.close(hub);
    source.dispose();
  });
  return hub;
});

/// V2-2 D1, background-service mode: the hub on each link to the service,
/// one [MuxAiBinding] per link (a second `ai.serve` on one link would leave
/// the phones it carries mirrored by nobody). A link that ends takes its
/// phones with it at once; a restarted service gets `ai.serve` on its new
/// link.
final aiDaemonBindingProvider = Provider<void>((ref) {
  MuxAiBinding? binding;

  void unbind() {
    final old = binding;
    binding = null;
    if (old != null) unawaited(old.dispose());
  }

  void bind(DaemonLink? link) {
    final client = link?.client;
    if (identical(client, binding?.client)) return; // the same link
    unbind();
    if (client == null) return;
    final bound = binding = MuxAiBinding(client, ref.read(aiPhoneHubProvider));
    void ended() {
      if (identical(binding, bound)) unbind();
    }

    unawaited(client.done.then((_) => ended(), onError: (Object _) => ended()));
  }

  bind(ref.read(daemonLinkProvider));
  ref.listen(daemonLinkProvider, (_, next) => bind(next));
  ref.onDispose(unbind);
});

/// Called once by `main.dart`, after the AI startup is scheduled and before
/// any phone can reach the window: in-process the hub becomes the target of
/// the agent side's [slot] (every runtime's router sends it `ai.*`); with
/// the background service it binds to each link to the service instead.
/// Never throws: the window starts whatever happens here (phones then hear
/// "unavailable"); the error's type goes to the log.
void startAiPhone(ProviderContainer container, {AiEndpointSlot? slot}) {
  try {
    final hub = container.read(aiPhoneHubProvider);
    if (slot != null) {
      container.read(_aiSlotPlugProvider).slot = slot;
      slot.target = hub;
    } else {
      container.read(aiDaemonBindingProvider);
    }
  } on Object catch (error) {
    debugPrint('ShellX: AI for phones failed to start: ${error.runtimeType}');
  }
}

/// The window quits (V2-2 D1), before its agents stop: every phone that
/// lists hears `available: false`, every one that mirrors a session
/// `desktop_closed`, and from then on the agent side's slot answers
/// "unavailable". Never throws.
void stopAiPhone(ProviderContainer container) {
  try {
    if (!container.exists(aiPhoneHubProvider)) return;
    container
        .read(_aiSlotPlugProvider)
        .close(container.read(aiPhoneHubProvider));
  } on Object catch (error) {
    debugPrint('ShellX: closing AI for phones failed: ${error.runtimeType}');
  }
}
