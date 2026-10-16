import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart';
import '../../ai/ai_frame_notifier.dart';
import '../../ai/ai_host_provider.dart';
import '../../ai/ai_phone_reverts.dart';
import '../../ai/ai_project_files.dart';
import '../../ai/ai_runtimes.dart';
import '../../config/settings_schema.dart' show SettingPage;
import '../../terminal/clipboard_media.dart' show clipboardMediaProvider;
import '../../terminal/terminal_tabs.dart';
import '../config/config_ui_request.dart';
import '../settings/settings_start_page.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart' show TogglePaneZoomIntent;
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart';
import 'ai_dock.dart';
import 'ai_files_panel.dart';
import 'ai_folder_card.dart';
import 'ai_header.dart';
import 'ai_history.dart';
import 'ai_log_dialog.dart';
import 'ai_permission_bar.dart';
import 'ai_run_sheet.dart';
import 'ai_scope.dart';
import 'ai_side_panel.dart';
import 'ai_timeline.dart';

enum _More { settings, restart, log }

/// V2-1 D3, spec §4.1: an AI pane, the negative leaf of an AI tab — its
/// header, the conversation (at most 760 px wide) with the dock under it,
/// and the overlay over it (run sheet, viewer, "Resume session").
/// - Instant feedback: the pane shows at once; its runtime is made right
///   after that first frame (never while building).
/// - B11: the agent starts when the pane's tab is first shown, once per
///   runtime; a hidden pane's views hear nothing until it shows again.
/// - [focusNode] is the window's terminal focus while this pane is the
///   selected tab's focused pane. The whole pane holds it and hands the
///   keyboard on to the folder field while the folder card is up, the run
///   sheet while one is, else the composer, so the window's shortcuts and
///   `focusTerminal` reach the pane.
/// - The folder card ("Choose folder" over a conversation) comes over the
///   conversation without unmounting it: Cancel finds the composer's text.
class AiPaneView extends ConsumerStatefulWidget {
  const AiPaneView({
    super.key,
    required this.tab,
    required this.pane,
    required this.selected,
    this.focusNode,
  });

  final TerminalTab tab;
  final AiPaneState pane;

  /// The pane's tab is the selected one.
  final bool selected;
  final FocusNode? focusNode;

  @override
  ConsumerState<AiPaneView> createState() => _AiPaneViewState();
}

class _AiPaneViewState extends ConsumerState<AiPaneView> {
  final _ui = AiPaneUi();

  /// The composer's (or the folder field's) focus: the pane's own, never
  /// the window's (a text field would keep a terminal view's key handler
  /// on it, below).
  final _input = FocusNode(debugLabel: 'ai input');

  /// The overlay's keyboard focus (the run sheet's terminal): while the
  /// sheet is up, the window's requests for the keyboard go to it, not to
  /// the composer ([_forward]).
  final _overlayFocus = FocusNode(debugLabel: 'ai overlay');
  var _overlayUp = false;

  /// The folder field's focus. The card can come over a conversation whose
  /// composer stays mounted (its text is kept), so the two cannot share one
  /// node.
  final _folderInput = FocusNode(debugLabel: 'ai folder');
  AiRuntime? _runtime;
  AiFrameNotifier? _frames;

  /// The runtime this pane started: each runtime starts once (B11).
  AiRuntime? _started;
  var _attachQueued = false;

  /// "Choose folder" on a "folder gone" card (§6).
  var _choosing = false;

  /// V2-2b B19, R12: the reverts phones make; this pane says its own.
  StreamSubscription<AiPhoneRevert>? _phoneReverts;

  /// D14: the pane reopens a session (a restored tab, History): "Resume
  /// session" shows while it loads. A new folder starts a new session
  /// ([_useFolder]), and nothing is being resumed then.
  late bool _resuming = widget.pane.sessionId != null;

  @override
  void initState() {
    super.initState();
    _ui.onChooseFolder = () {
      setState(() => _choosing = true);
      _forwardSoon();
    };
    _ui.onRun = (request) => unawaited(_run(request));
    _ui.fileIndex = _fileIndex;
    _ui.clipboardFiles = () => ref.read(clipboardMediaProvider).files();
    _ui.clipboardImage = () => ref.read(clipboardMediaProvider).image();
    _ui.readImageFile = _readImage;
    _ui.onRevertTurn = (turn) {
      final runtime = _runtime;
      if (runtime == null) return;
      unawaited(aiRevert(context, runtime, _ui, turn: turn));
    };
    widget.focusNode?.addListener(_onWindowFocus);
    _ui.addListener(_onUi);
    _phoneReverts = ref
        .read(aiPhoneRevertsProvider)
        .stream
        .listen(_onPhoneRevert);
    _attachSoon();
  }

  /// V2-2b B19, R12: a phone reverted files of this pane's session. The
  /// Changes panel opens on its note, as after a revert made here, and reads
  /// the project again.
  void _onPhoneRevert(AiPhoneRevert revert) {
    if (!mounted || revert.paneId != widget.pane.id) return;
    _ui.openPanel();
    _ui.note.value = AppLocalizations.of(
      context,
    ).aiRevertedFromPhone(revert.count);
    _ui.changesChanged();
  }

  @override
  void didUpdateWidget(AiPaneView old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onWindowFocus);
      widget.focusNode?.addListener(_onWindowFocus);
    }
    _frames?.active = widget.selected;
    // D18: the panels look again when the tab comes back to the front.
    if (widget.selected && !old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ui.changesChanged();
      });
    }
    if (old.selected != widget.selected || old.pane.cwd != widget.pane.cwd) {
      _attachSoon();
    }
  }

  @override
  void dispose() {
    unawaited(_phoneReverts?.cancel());
    widget.focusNode?.removeListener(_onWindowFocus);
    _ui.removeListener(_onUi);
    _frames?.dispose();
    _ui.dispose();
    _input.dispose();
    _overlayFocus.dispose();
    _folderInput.dispose();
    super.dispose();
  }

  /// The window focused this pane (`focusTerminal`, a click): the keyboard
  /// goes on to the composer or the folder field when one is shown.
  void _onWindowFocus() {
    if (widget.focusNode?.hasPrimaryFocus ?? false) _forward();
  }

  /// To the folder field while the card is up, to the run sheet while it is
  /// up (a terminal program needs the keys), else to the composer.
  void _forward() {
    final sheet = _overlayFocus;
    final FocusNode node;
    if (widget.pane.cwd == null || _choosing) {
      node = _folderInput;
    } else if (_ui.overlay != null && sheet.context != null) {
      node = sheet;
    } else {
      node = _input;
    }
    if (node.context != null && node.canRequestFocus) node.requestFocus();
  }

  /// [_forward] once the frame is built, if the keyboard is this pane's to
  /// move: the pane holds the window's keyboard (not another pane of a split
  /// tab, nor a tab out of sight), and it is in the pane still or fell to the
  /// workspace when what had it went — not in a field elsewhere (Settings,
  /// the sidebar, a dialog) that the user is typing in.
  void _forwardSoon() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || widget.focusNode == null) return;
        final primary = FocusManager.instance.primaryFocus;
        final lost =
            primary == null ||
            identical(primary, FocusScope.of(context, createDependency: false));
        if (lost || widget.focusNode!.hasFocus) _forward();
      })
      ..ensureVisualUpdate();
  }

  /// An overlay went (the run sheet, a viewer): the keyboard was theirs,
  /// and it goes back to the composer instead of falling to the workspace.
  void _onUi() {
    final up = _ui.overlay != null;
    if (up == _overlayUp) return;
    _overlayUp = up;
    if (!up) _forwardSoon();
  }

  void _attachSoon() {
    if (_attachQueued) return;
    _attachQueued = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _attachQueued = false;
        if (mounted) _attach();
      })
      ..ensureVisualUpdate();
  }

  /// The pane's runtime: made on first use, swapped when it changes (a new
  /// folder, the agent switched off), started once when the tab is shown.
  void _attach() {
    final runtime = ref
        .read(aiRuntimesProvider.notifier)
        .runtimeFor(widget.pane.id);
    if (!identical(runtime, _runtime)) {
      final old = _frames;
      setState(() {
        _runtime = runtime;
        _frames = runtime == null
            ? null
            : (AiFrameNotifier(runtime.state)..active = widget.selected);
      });
      old?.dispose();
      // The composer of the new runtime is built next: it takes the keyboard
      // the folder card (or the old composer) had.
      if (runtime != null) _forwardSoon();
    }
    if (runtime != null && widget.selected && !identical(_started, runtime)) {
      _started = runtime;
      unawaited(runtime.start());
    }
  }

  /// "Cancel" on the folder card of a conversation: back to it, with the
  /// keyboard in its composer.
  void _cancelFolder() {
    setState(() => _choosing = false);
    _forwardSoon();
  }

  /// D5: the folder the user chose. Another folder is another runtime: the
  /// old one stops. Claude keeps a session under its project's folder, so the
  /// id of the old folder's session opens nothing in another one, and a load
  /// that fails there would leave the tab stuck (final review I-6): a new
  /// folder starts a new session. The same folder (it came back) reopens its
  /// own, as the agent says it can (D14).
  void _useFolder(String folder) {
    final old = _frames;
    final same = folder == widget.pane.cwd;
    setState(() {
      _choosing = false;
      _runtime = null;
      _frames = null;
      if (!same) _resuming = false;
    });
    old?.dispose();
    ref.read(aiRuntimesProvider.notifier).forget(widget.pane.id);
    ref
        .read(terminalTabsProvider.notifier)
        .updateAiPane(
          widget.pane.id,
          (p) => p.copyWith(cwd: folder, sessionId: same ? p.sessionId : null),
        );
    _attachSoon();
  }

  /// D8: a card's sign-in or install, in the run sheet over the
  /// conversation. Exit 0 closes the sheet and the session goes on: a
  /// sign-in reopens the session (`retry`), an install starts the agent and
  /// refreshes Settings › Agents.
  Future<void> _run(AiRunRequest request) async {
    final runtime = _runtime;
    if (runtime == null) return;
    final l10n = AppLocalizations.of(context);
    final name = widget.pane.agentName;
    switch (request) {
      case AiRunLogin(:final method):
        final command = runtime.loginCommand(method);
        if (command == null) return;
        _ui.showOverlay(
          AiRunSheet(
            key: UniqueKey(),
            title: l10n.aiRunSheetLogin(name),
            command: command,
            workingDirectory: runtime.state.cwd,
            failureNote: l10n.aiLoginFailed,
            focusNode: _overlayFocus,
            onDone: () {
              _ui.closeOverlay();
              unawaited(runtime.retry());
            },
            onClose: _ui.closeOverlay,
          ),
        );
      case AiRunInstall():
        final agent = aiAgentById(
          ref.read(aiAgentsProvider),
          widget.pane.agentId,
        );
        if (agent == null) return;
        final readiness = await ref.read(aiReadinessSourceProvider)(agent);
        if (!mounted || !identical(runtime, _runtime)) return;
        final install = readiness is AgentNeedsInstall
            ? readiness.install
            : null;
        if (install == null) {
          // Installed meanwhile, or npm went away: the next start says.
          unawaited(runtime.retry());
          return;
        }
        final folder = install.workingDirectory;
        _ui.showOverlay(
          AiRunSheet(
            key: UniqueKey(),
            title: l10n.aiRunSheetInstall(name),
            command: install,
            workingDirectory: folder ?? runtime.state.cwd,
            makeFolder: folder != null,
            focusNode: _overlayFocus,
            onDone: () {
              _ui.closeOverlay();
              unawaited(ref.read(aiReadinessProvider.notifier).refresh());
              unawaited(runtime.retry());
            },
            onClose: _ui.closeOverlay,
          ),
        );
    }
  }

  /// D16: a dropped image, at most 10 MiB (agents refuse bigger ones).
  static Future<Uint8List?> _readImage(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 10 << 20) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<List<String>>? _index;
  int? _indexTurn;

  /// D16: the project's files for `@`, read again after each turn.
  Future<List<String>> _fileIndex() {
    final runtime = _runtime;
    if (runtime == null) return Future.value(const []);
    final turn = aiLastEndedTurn(runtime.state);
    if (_index == null || _indexTurn != turn) {
      _indexTurn = turn;
      _index = ref
          .read(aiProjectFilesProvider)
          .index(runtime.state.cwd)
          .catchError((Object _) => const <String>[]);
    }
    return _index!;
  }

  /// D15: an earlier session of this folder, in a new AI tab of the same
  /// agent that reopens it (D14).
  Future<void> _history(AiRuntime runtime) => showAiHistory(
    context,
    runtime,
    onOpen: (sessionId, title) {
      final l10n = AppLocalizations.of(context);
      final pane = widget.pane;
      ref
          .read(terminalTabsProvider.notifier)
          .openAiTab(
            agentId: pane.agentId,
            agentName: pane.agentName,
            title: (title?.trim().isNotEmpty ?? false)
                ? title!
                : l10n.aiNewSession,
            cwd: runtime.state.cwd,
            sessionId: sessionId,
          );
    },
  );

  /// Through the window's action when there is one (it also announces).
  void _zoom() {
    final tabs = ref.read(terminalTabsProvider.notifier)
      ..focusPane(widget.pane.id);
    const intent = TogglePaneZoomIntent();
    final action = Actions.maybeFind<TogglePaneZoomIntent>(
      context,
      intent: intent,
    );
    if (action != null && action.isEnabled(intent)) {
      Actions.invoke(context, intent);
    } else {
      tabs.toggleZoom();
    }
  }

  /// I-4: "Restart agent" looks at the login shell's environment again, as
  /// Settings › Agents does, so a Node, git or agent installed since ShellX
  /// started is found (the environment is otherwise kept for the whole run).
  void _forgetLoginEnvironment() {
    try {
      ref.read(aiHostProvider).env.invalidate();
    } on Object {
      // No AI host (a window of a test of something else): the agent
      // restarts all the same.
    }
  }

  Future<void> _more(Offset at) async {
    final l10n = AppLocalizations.of(context);
    final runtime = _runtime;
    final choice = await showShellxMenu<_More>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          value: _More.settings,
          label: l10n.aiMenuAgentsSettings,
          key: const Key('ai.more.settings'),
        ),
        ShellxMenuEntry(
          value: _More.restart,
          label: l10n.aiMenuRestart,
          enabled: runtime != null,
          key: const Key('ai.more.restart'),
        ),
        ShellxMenuEntry(
          value: _More.log,
          label: l10n.aiMenuViewLog,
          enabled: runtime != null,
          key: const Key('ai.more.log'),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _More.settings:
        ref.read(settingsStartPageProvider.notifier).set(SettingPage.agents);
        ref
            .read(configUiRequestProvider.notifier)
            .request(ConfigUiRequest.settings);
      case _More.restart:
        if (runtime != null) {
          _forgetLoginEnvironment();
          unawaited(runtime.restart());
        }
      case _More.log:
        if (runtime != null) unawaited(showAiLogDialog(context, runtime));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = widget.pane;
    // D21, D7: an agent switched off or removed; the runtimes stop it.
    ref.listen(aiAgentsProvider, (_, _) => _attachSoon());
    final offered = ref.watch(
      aiAgentsProvider.select((a) => aiAgentById(a, pane.agentId) != null),
    );
    final runtime = _runtime;
    final frames = _frames;
    final needsFolder = pane.cwd == null || _choosing;
    // D5, §6: the card for a folder to work in. Over a conversation (the
    // folder is gone) it can be cancelled.
    final card = AiFolderCard(
      key: const Key('ai.folder'),
      initial: pane.cwd,
      focusNode: _folderInput,
      onChosen: _useFolder,
      onCancel: pane.cwd == null ? null : _cancelFolder,
    );
    final Widget body;
    if (!offered) {
      body = _Message(
        text: pane.agentId == kClaudeAgentId
            ? l10n.aiClaudeOff
            : l10n.aiAgentUnknown,
      );
    } else if (runtime == null || frames == null) {
      body = needsFolder ? card : _Message(text: '', resuming: _resuming);
    } else {
      // The conversation stays mounted under the card — out of sight, out of
      // the keyboard's way — so cancelling it finds the composer as it was.
      final conversation = AiPaneScope(
        runtime: runtime,
        frames: frames,
        tab: widget.tab,
        pane: pane,
        ui: _ui,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Conversation(input: _input, resuming: _resuming),
            ),
            // §4.4: the right panel, 268 px.
            ListenableBuilder(
              listenable: _ui,
              builder: (context, _) => _ui.panelOpen
                  ? const AiSidePanel(files: AiFilesPanel())
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      body = Stack(
        fit: StackFit.expand,
        children: [
          Visibility(
            visible: !needsFolder,
            maintainState: true,
            child: conversation,
          ),
          if (needsFolder) card,
        ],
      );
    }
    final tabs = ref.read(terminalTabsProvider.notifier);
    Widget header(AiHeaderView view) => ListenableBuilder(
      listenable: _ui,
      builder: (context, _) => AiHeader(
        paneId: pane.id,
        agentName: pane.agentName,
        title: widget.tab.label,
        view: view,
        // D15: only for an agent that lists its sessions.
        onHistory: runtime != null && runtime.state.capabilities.listSessions
            ? () => unawaited(_history(runtime))
            : null,
        onPanel: runtime == null ? null : _ui.togglePanel,
        panelOpen: _ui.panelOpen,
        onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
        onZoom: widget.tab.isSplit ? _zoom : null,
        onMore: (at) => unawaited(_more(at)),
      ),
    );
    final content = Semantics(
      container: true,
      label: l10n.aiPaneLabel(pane.agentName),
      child: ColoredBox(
        color: ShellxDesktopColors.bgTerminal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (frames != null && offered && !needsFolder)
              AiSelect<AiHeaderView>(
                frames: frames,
                select: aiHeaderViewOf,
                builder: (context, view) => header(view),
              )
            else
              header((
                phase: offered && !needsFolder
                    ? AgentPhase.starting
                    : AgentPhase.stopped,
                needsInput: false,
                started: null,
                stopping: false,
              )),
            const Divider(height: 1, color: ShellxDesktopColors.line),
            Expanded(child: body),
          ],
        ),
      ),
    );
    final window = widget.focusNode;
    if (window != null) {
      // A field that just appeared (the composer once the runtime is there,
      // the folder card) takes the keyboard the pane holds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && window.hasPrimaryFocus) _forward();
      });
    }
    // Always a `Focus` here, with or without the window's node: a wrapper
    // that came and went with the selection would rebuild the whole pane
    // from scratch (the composer's text, the panels, the scroll place).
    return Focus(
      focusNode: window,
      canRequestFocus: window == null ? false : null,
      skipTraversal: window == null ? true : null,
      // `FocusNode.attach` keeps the key handler the last terminal view
      // put on the window's node unless a new one is given: without this,
      // Enter, Backspace and the arrows typed here would go to that
      // (hidden) terminal.
      onKeyEvent: window == null ? null : (_, _) => KeyEventResult.ignored,
      child: content,
    );
  }
}

/// The conversation, the dock under it, and what lies over it.
///
/// Keys 1–9 and Esc answer the waiting question wherever the keyboard is in
/// the conversation (final review M-2). The composer takes them first, as
/// before ([AiDock.keyHook]); but a click on the agent's words (a
/// `SelectionArea`) or on the user's message (a `SelectableText`) moves the
/// keyboard there, to read or copy, and the composer's handler no longer
/// hears it. So the column listens too, for the keys that reach it: from
/// anywhere in it except a field the user is typing in, and never from what
/// lies over it (the run sheet's terminal, a viewer) or from another pane or
/// a dialog, which are not in it.
///
/// A click on the blank space of the column is "inside" the composer's field
/// as well (like the dock and the cards): on macOS and Windows a click
/// outside a field takes its focus.
class _Conversation extends StatefulWidget {
  const _Conversation({required this.input, required this.resuming});

  final FocusNode input;
  final bool resuming;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  /// The Esc or digit key taken on key-down, until it is let go: its repeats
  /// are taken too (as the composer does), so a held key answers one
  /// question, not the next as well.
  LogicalKeyboardKey? _held;

  /// Whether the keyboard is in a field the user types into (the composer, a
  /// question's text field): its keys are its own. A read-only text (the
  /// user's message, a log) is no field.
  static bool _typing() {
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null) return false;
    final widget = focus.widget;
    final field = widget is EditableText
        ? widget
        : focus.findAncestorWidgetOfExactType<EditableText>();
    return field != null && !field.readOnly;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == _held) _held = null;
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && key == _held) return KeyEventResult.handled;
    // A press by the user, never one the system made up (a key held while
    // the window came back), and only while a question waits.
    if (event is! KeyDownEvent || event.synthesized) {
      return KeyEventResult.ignored;
    }
    _held = null;
    final scope = context.getInheritedWidgetOfExactType<AiPaneScope>();
    if (scope == null || scope.state.currentPermission == null || _typing()) {
      return KeyEventResult.ignored;
    }
    // Not typing: a draft in the composer does not keep the digits from the
    // question.
    if (!aiPermissionKeys(scope.runtime, event, hasText: false)) {
      return KeyEventResult.ignored;
    }
    _held = key;
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final runtime = scope.runtime;
    return Stack(
      children: [
        Positioned.fill(
          child: TapRegion(
            groupId: EditableText,
            behavior: HitTestBehavior.opaque,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: AiTimeline()),
                  AiDock(
                    focusNode: widget.input,
                    permissionBar: const AiPermissionBar(),
                    keyHook: (event, {required hasText}) =>
                        aiPermissionKeys(runtime, event, hasText: hasText),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.resuming)
          // M-3: until the session has loaded; after that a stopped or
          // restarting agent is no loading, and the conversation stays.
          AiSelect<bool>(
            frames: scope.frames,
            select: (s) =>
                s.sessionId == null &&
                (s.phase == AgentPhase.stopped ||
                    s.phase == AgentPhase.starting),
            builder: (context, loading) =>
                loading ? const _ResumeCard() : const SizedBox.shrink(),
          ),
        ListenableBuilder(
          listenable: scope.ui,
          builder: (context, _) => switch (scope.ui.overlay) {
            final overlay? => Positioned.fill(child: overlay),
            null => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// A pane without a conversation (no runtime yet, or none to have): a
/// line of text.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.resuming = false});

  final String text;
  final bool resuming;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Center(
        child: Padding(
          padding: const EdgeInsets.all(ShellxSpace.s24),
          child: Text(
            text,
            key: const Key('ai.message'),
            textAlign: TextAlign.center,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
      ),
      if (resuming) const _ResumeCard(),
    ],
  );
}

/// D14: "Resume session — Loading the conversation…" while a reopened
/// session loads (no spinner: no looping animation).
class _ResumeCard extends StatelessWidget {
  const _ResumeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: const Key('ai.resume'),
        margin: const EdgeInsets.all(ShellxSpace.s24),
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.history,
                  size: 16,
                  color: ShellxDesktopColors.accent,
                ),
                const SizedBox(width: ShellxSpace.s6),
                Text(
                  l10n.aiResumeSession,
                  style: ShellxText.bodyStrong.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ShellxSpace.s4),
            Text(
              l10n.aiResumeLoading,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
