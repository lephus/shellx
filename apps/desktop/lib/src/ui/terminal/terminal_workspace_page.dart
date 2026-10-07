import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/agent_state.dart';
import '../../config/config_controller.dart';
import '../../config/keybindings.dart';
import '../../mux/daemon_state.dart' show daemonStateProvider;
import '../../restore/restore_persistence.dart' show restoreStripProvider;
import '../../terminal/byte_size.dart';
import '../../terminal/clipboard_media.dart';
import '../../terminal/edit_line.dart';
import '../../terminal/find_session.dart';
import '../../terminal/find_sessions.dart';
import '../../terminal/pane_input.dart';
import '../../terminal/pane_layout.dart';
import '../../terminal/pane_paste.dart';
import '../../terminal/paste_sender.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../terminal/terminal_font_size.dart';
import '../../remote/ssh_actions.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_focus.dart';
import '../window_router.dart';
import 'click_select.dart' show selectionText;
import 'close_tab.dart';
import 'key_sequence_host.dart';
import 'notifications_panel.dart';
import 'remote_marks.dart' show remoteAnnouncementBetween;
import 'session_sidebar.dart';
import 'shortcut_labels.dart';
import 'terminal_pane.dart';
import 'terminal_shortcuts.dart';
import 'terminal_workspace_config.dart';
import 'terminal_workspace_notices.dart';
import 'terminal_workspace_ssh.dart';

/// Spec §3.2: `Row(Sidebar 220 px, VerticalDivider, TerminalPane)`.
class TerminalWorkspacePage extends ConsumerStatefulWidget {
  const TerminalWorkspacePage({super.key});

  @override
  ConsumerState<TerminalWorkspacePage> createState() =>
      TerminalWorkspacePageState();
}

class TerminalWorkspacePageState extends ConsumerState<TerminalWorkspacePage>
    with
        WorkspaceConfig<TerminalWorkspacePage>,
        WorkspaceConfigUi<TerminalWorkspacePage>,
        WorkspaceSequences<TerminalWorkspacePage> {
  @override
  final terminalFocus = FocusNode(debugLabel: 'terminal');
  final sidebarFocus = FocusNode(debugLabel: 'sidebar');

  /// The empty state's "Open new tab" (focused when the last tab closes).
  final emptyFocus = FocusNode(debugLabel: 'open new tab');

  /// The signed-out strip's "Sign in" (UI §3.6 region 3).
  final stripFocus = FocusNode(debugLabel: 'signed-out strip');

  /// The abnormal-end strip's "Close" (UI-A5 §4).
  final restoreStripFocus = FocusNode(debugLabel: 'restore strip');
  final daemonStripFocus = FocusNode(debugLabel: 'service strip');
  final sidebarScroll = ScrollController();

  /// The notifications panel is open (UI-A4 §5).
  bool panelOpen = false;

  /// Where the keyboard was before the panel opened; it goes back there
  /// when the panel closes (UI-A4 §5.3).
  FocusNode? _beforePanel;

  /// The TerminalView map (spec criterion 2, without plain F6: it belongs
  /// to the shell), built once per platform with [_workspaceShortcuts]: a
  /// new map on every build would make each TerminalView rebuild its
  /// shortcut index.
  Map<ShortcutActivator, Intent>? terminalShortcuts;
  Map<ShortcutActivator, Intent>? _workspaceShortcuts;
  TargetPlatform? _shortcutsPlatform;
  KeyBindings? _shortcutsFor;

  /// Rebuilt only when the platform or the effective bindings change
  /// (A9 D24): a reload applies at once, a rebuild costs nothing.
  void _buildShortcuts(TargetPlatform platform, KeyBindings bindings) {
    if (_shortcutsPlatform == platform &&
        identical(_shortcutsFor, bindings) &&
        terminalShortcuts != null) {
      return;
    }
    _shortcutsPlatform = platform;
    _shortcutsFor = bindings;
    terminalShortcuts = terminalViewShortcuts(platform, bindings: bindings);
    _workspaceShortcuts = desktopShortcuts(platform, bindings: bindings);
  }

  /// After the frame, so a TerminalView that just got [terminalFocus] (a
  /// new selection) is attached first. With no tab the keyboard goes to
  /// "Open new tab", so it never ends up outside the window shortcuts.
  ///
  /// A post-frame callback alone waits for a frame something else asks
  /// for (Esc in the sidebar changes nothing on screen), hence the
  /// explicit request.
  @override
  void focusTerminal() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        final empty = ref.read(terminalTabsProvider).tabs.isEmpty;
        (empty ? emptyFocus : terminalFocus).requestFocus();
      })
      ..ensureVisualUpdate();
  }

  /// ⌘⇧I, the bell.
  void togglePanel() => panelOpen ? closePanel() : _openPanel();

  void _openPanel() {
    if (panelOpen) return;
    closeConfigOverlay(restoreFocus: false); // one surface at a time
    _beforePanel = FocusManager.instance.primaryFocus;
    setState(() => panelOpen = true); // the panel takes the keyboard
  }

  /// Esc, a click outside, a jump, or another window shortcut. With
  /// [restoreFocus] the keyboard goes back at once, so a shortcut that
  /// runs next (F6) starts from where the user was.
  @override
  void closePanel({bool restoreFocus = true}) {
    closeConfigOverlay(restoreFocus: restoreFocus); // A9: any shortcut
    if (!panelOpen) return;
    final before = _beforePanel;
    _beforePanel = null;
    setState(() => panelOpen = false);
    if (!restoreFocus) return;
    if (before != null && before.context != null && before.canRequestFocus) {
      before.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
    } else {
      focusTerminal(); // what it was on went away (a closed tab)
    }
  }

  /// D13: the next tab with unread; none → a neutral toast and the same
  /// words for a screen reader.
  void _jumpToNextUnread() {
    closePanel();
    final attention = ref.read(tabAttentionProvider.notifier);
    final next = attention.nextUnread();
    if (next != null && attention.jumpTo(next)) return;
    // A fresh notice each time: a repeated ⌘⇧U restarts the toast.
    ref.read(terminalTabsProvider.notifier).showNotice(NoUnreadNotice());
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).noUnreadNotifications,
        Directionality.of(context),
      ),
    );
  }

  @override
  Future<void> closeTab(TerminalTab tab) => closeTabWithConfirm(
    tabs: ref.read(terminalTabsProvider.notifier),
    router: ref.read(windowRouterProvider.notifier),
    l10n: AppLocalizations.of(context),
    tab: tab,
    confirm: ref.read(shellxConfigProvider).config.confirmClose,
  );

  /// ⌘W on a split tab, the pane ×, middle click on a pane header, "Close
  /// pane" (UI-A3 §2.1, §4.1); the keyboard then goes to the tab's new
  /// focused pane (UI-A3 §6), or back to the same pane when the dialog is
  /// cancelled. A pane that closed is announced (D22).
  Future<void> closePane(TerminalTab tab, int paneId) async {
    final l10n = AppLocalizations.of(context);
    await closePaneWithConfirm(
      tabs: ref.read(terminalTabsProvider.notifier),
      router: ref.read(windowRouterProvider.notifier),
      l10n: l10n,
      tab: tab,
      paneId: paneId,
      confirm: ref.read(shellxConfigProvider).config.confirmClose,
    );
    if (!mounted) return;
    final after = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tab.id)
        .firstOrNull;
    // Only this pane going away is news: a cancelled dialog says nothing,
    // even when another pane exited meanwhile.
    if (tab.isSplit && after != null && !after.panes.containsKey(paneId)) {
      _announce(l10n.paneAnnounceClosed(after.paneCount));
    }
    focusTerminal();
  }

  // AltGr (Windows: Ctrl + right Alt) is handled once, for every window
  // shortcut, by [WindowAction] (A9 D26).
  bool _split(Intent intent) => ref.read(terminalTabsProvider).selected != null;

  /// The pane chords apply only to a split tab; otherwise the key reaches
  /// the shell, like ⌘C without a selection.
  bool _isSplit(Intent intent) =>
      ref.read(terminalTabsProvider).selected?.isSplit ?? false;

  /// D22: polite, once.
  void _announce(String message) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    ),
  );

  /// A focus change from the keyboard (UI-A3 §8); a click is not read.
  void _announceFocusedPane() {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null || !tab.isSplit) return;
    _announce(
      AppLocalizations.of(context).paneRegionLabel(
        tab.paneNumber(tab.focusedPaneId),
        tab.paneCount,
        tab.focused.automaticLabel,
      ),
    );
  }

  /// ⌘D / ⌘⇧D, the menus: the new pane is announced and gets the keyboard.
  /// Announced only while the split tab is still the one shown: a tab
  /// switch during a pending open must not speak for another tab.
  Future<void> _splitPane(SplitAxis axis) async {
    final origin = ref.read(terminalTabsProvider).selected;
    if (origin == null) return;
    await ref.read(terminalTabsProvider.notifier).split(axis);
    if (!mounted) return;
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab != null &&
        tab.id == origin.id &&
        tab.paneCount > origin.paneCount) {
      _announce(
        AppLocalizations.of(
          context,
        ).paneAnnounceSplit(tab.paneNumber(tab.focusedPaneId), tab.paneCount),
      );
    }
    focusTerminal();
  }

  /// UI §3.6 regions: terminal (or "Open new tab" with no tab), sidebar,
  /// signed-out strip (when shown), abnormal-end strip (when shown; after
  /// the sidebar, right before the terminal, UI-A5 §4).
  void _cycleRegion(int step) {
    final signedOut =
        ref.read(agentControllerProvider).phase == AuthPhase.signedOut;
    final restoreStrip = ref.read(restoreStripProvider) != null;
    final daemonStrip = ref.read(daemonStateProvider).strip != null;
    final noTab = ref.read(terminalTabsProvider).tabs.isEmpty;
    final regions = [
      noTab ? emptyFocus : terminalFocus,
      if (!noTab) sidebarFocus, // an empty list is no stop (UI §3.6)
      if (signedOut) stripFocus,
      if (restoreStrip) restoreStripFocus,
      if (daemonStrip) daemonStripFocus,
    ];
    final current = regions.indexWhere((node) => node.hasFocus);
    // From outside every region (the `+` button, a toast…) the sidebar
    // counts as the current region: `+` belongs to it.
    final from = current >= 0 ? current : (noTab ? 0 : 1);
    regions[(from + step) % regions.length].requestFocus();
  }

  /// Built once; every action reads the providers when it runs.
  @override
  late final actionsMap = _actions();

  Map<Type, Action<Intent>> _actions() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    Action<T> run<T extends Intent>(
      void Function(T intent) body, {
      bool Function(T intent)? enabled,
    }) => WindowAction<T>(body, enabled);
    return <Type, Action<Intent>>{
      // UI-A4 §5.3: the other window shortcuts still run with the panel
      // open; they close it first.
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        unawaited(ref.read(sshActionsProvider).newTab());
        focusTerminal();
      }),
      CloseTabIntent: run<CloseTabIntent>((_) {
        closePanel();
        // UI-A2 §4: an open name field (maybe another tab's) is saved
        // first; losing the focus commits it.
        if (ref.read(sidebarWorkspacesProvider).renaming != null) {
          FocusManager.instance.primaryFocus?.unfocus();
          FocusManager.instance.applyFocusChangesIfNeeded();
        }
        final selected = ref.read(terminalTabsProvider).selected;
        if (selected == null) {
          // UI §2.7 (accepted): ⌘W on the empty state hides the window.
          ref.read(windowRouterProvider.notifier).hideWindow();
        } else if (selected.isSplit) {
          unawaited(closePane(selected, selected.focusedPaneId)); // A3 D6
        } else {
          unawaited(closeTab(selected));
        }
      }),
      SelectTabIntent: run<SelectTabIntent>((intent) {
        closePanel();
        workspaces.selectVisible(intent.position);
        focusTerminal();
      }),
      // A3 P3 (D3, D9-D12). Disabled, a chord reaches the shell; like the
      // other window shortcuts they close the panel first (UI-A4 §5.3).
      SplitPaneIntent: run<SplitPaneIntent>((intent) {
        closePanel();
        unawaited(_splitPane(intent.axis));
      }, enabled: _split),
      FocusPaneIntent: run<FocusPaneIntent>((intent) {
        closePanel();
        if (tabs.focusDirection(intent.direction)) {
          focusTerminal();
          _announceFocusedPane();
        }
      }, enabled: _isSplit),
      TogglePaneZoomIntent: run<TogglePaneZoomIntent>((_) {
        closePanel();
        final l10n = AppLocalizations.of(context);
        _announce(
          tabs.toggleZoom()
              ? l10n.paneAnnounceZoomed
              : l10n.paneAnnounceUnzoomed,
        );
        focusTerminal();
      }, enabled: _isSplit),
      EqualizePanesIntent: run<EqualizePanesIntent>((_) {
        closePanel();
        tabs.equalize();
      }, enabled: _isSplit),
      ResizePaneIntent: run<ResizePaneIntent>((intent) {
        closePanel();
        tabs.resizeFocused(intent.direction);
      }, enabled: _isSplit),
      NextTabIntent: run<NextTabIntent>((_) {
        closePanel();
        workspaces.step(1);
        focusTerminal();
      }),
      PreviousTabIntent: run<PreviousTabIntent>((_) {
        closePanel();
        workspaces.step(-1);
        focusTerminal();
      }),
      // The new workspace's name field takes the keyboard (D15); it hands
      // it to the terminal when it closes.
      NewWorkspaceIntent: run<NewWorkspaceIntent>((_) {
        closePanel();
        unawaited(workspaces.create());
      }),
      ToggleNotificationsPanelIntent: run<ToggleNotificationsPanelIntent>(
        (_) => togglePanel(),
      ),
      JumpToNextUnreadIntent: run<JumpToNextUnreadIntent>(
        (_) => _jumpToNextUnread(),
      ),
      // ⌘C / Ctrl+Shift+C copies only with a selection; otherwise the key
      // stays the terminal's (spec §3.2).
      CopySelectionIntent: run<CopySelectionIntent>(
        (_) => _copy(),
        enabled: (_) =>
            ref.read(terminalTabsProvider).selected?.selection.selection !=
            null,
      ),
      PasteClipboardIntent: run<PasteClipboardIntent>((_) {
        unawaited(_paste());
      }),
      SelectAllIntent: run<SelectAllIntent>(
        (_) => _selectAll(),
        // Outside the terminal (sidebar, a toast…) the key does nothing.
        enabled: (intent) =>
            ref.read(terminalTabsProvider).selected != null &&
            (intent.fromMenu || terminalFocus.hasFocus),
      ),
      // A10 D4: ⌘F opens the focused pane's bar (or refocuses it); ⌘G and
      // ⌘⇧G step through its matches. With no bar open ⌘G is the shell's.
      StartSearchIntent: run<StartSearchIntent>((_) {
        closePanel();
        final tab = ref.read(terminalTabsProvider).selected;
        if (tab == null) return;
        ref.read(findSessionsProvider.notifier).open(tab.focusedPaneId);
        WidgetsBinding.instance
          ..addPostFrameCallback(
            (_) => ref
                .read(findSessionsProvider)[tab.focusedPaneId]
                ?.focusNode
                .requestFocus(),
          )
          ..ensureVisualUpdate();
      }, enabled: (_) => ref.read(terminalTabsProvider).selected != null),
      NavigateSearchIntent: run<NavigateSearchIntent>((intent) {
        final bar = _focusedFind();
        intent.next ? bar?.next() : bar?.previous();
      }, enabled: (_) => _focusedFind() != null),
      EndSearchIntent: run<EndSearchIntent>((_) {
        final tab = ref.read(terminalTabsProvider).selected;
        if (tab == null) return;
        ref.read(findSessionsProvider.notifier).close(tab.focusedPaneId);
        focusTerminal();
      }, enabled: (_) => _focusedFind() != null),
      // A11 D11: only at a prompt — a program on the alternate screen
      // (vim, less) gets the key itself.
      EditLineIntent: run<EditLineIntent>(
        (i) => ref
            .read(terminalTabsProvider)
            .selected
            ?.focused
            .terminal
            .sendUserText(editLineSequence(i.op)),
        enabled: (_) {
          final pane = ref.read(terminalTabsProvider).selected?.focused;
          return pane != null &&
              terminalFocus.hasFocus &&
              canEditLine(
                exited: pane.exited,
                altBuffer: pane.terminal.isUsingAltBuffer,
              );
        },
      ),
      FontBiggerIntent: run<FontBiggerIntent>(
        (i) => ref.read(terminalFontSizeProvider.notifier).increase(i.step),
      ),
      FontSmallerIntent: run<FontSmallerIntent>(
        (i) => ref.read(terminalFontSizeProvider.notifier).decrease(i.step),
      ),
      FontResetIntent: run<FontResetIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).reset(),
      ),
      NextRegionIntent: run<NextRegionIntent>((_) {
        closePanel();
        _cycleRegion(1);
      }),
      PreviousRegionIntent: run<PreviousRegionIntent>((_) {
        closePanel();
        _cycleRegion(-1);
      }),
      ...configActions(),
      ...sshWindowActions(ref, closePanel: closePanel),
    };
  }

  void _copy() {
    final tab = ref.read(terminalTabsProvider).selected;
    final range = tab?.selection.selection;
    if (tab == null || range == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(
          text: selectionText(
            tab.terminal.buffer,
            range,
            tab.selection.selectionMode,
          ),
        ),
      ),
    );
    tab.selection.clearSelection();
  }

  /// A10 D4: the find bar of the selected tab's focused pane, if open.
  FindSession? _focusedFind() {
    final tab = ref.read(terminalTabsProvider).selected;
    return tab == null
        ? null
        : ref.read(findSessionsProvider)[tab.focusedPaneId];
  }

  /// ⌘A / Ctrl+Shift+A / the menu: every line, scrollback included.
  void _selectAll() {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null) return;
    final buffer = tab.terminal.buffer;
    tab.selection.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(tab.terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }

  /// ⌘V / Ctrl+Shift+V / the menu into the **focused pane of the selected
  /// tab at the moment of the key** — chosen before the clipboard is read,
  /// so a tab switch while it is read cannot send the text elsewhere (A10
  /// D13). Sanitised and bracketed by [DesktopTerminal.paste]; a large text
  /// is asked about, then sent in pieces ([PasteSender]). The sink writes
  /// through the pane's terminal, so in-process, background-service and SSH
  /// panes behave alike.
  Future<void> _paste() async {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null) return;
    final paneId = tab.focusedPaneId;
    final terminal = tab.focused.terminal;
    final media = ref.read(clipboardMediaProvider);
    final input = ref.read(paneInputProvider);
    // A10 D15: files copied in Finder / Explorer first (their name is also
    // on the clipboard as text), then text, then an image.
    final files = await media.files();
    if (!mounted) return;
    if (files.isNotEmpty) {
      await input.insertPaths(paneId, files);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      final image = await media.image();
      if (image != null && mounted) await input.pasteImage(paneId, image);
      return;
    }
    final sink = PanePasteSink(
      () => ref.read(terminalTabsProvider),
      paneId,
      terminal,
    );
    // An exited pane closes on Enter (UI §2.6): a paste must not do that.
    if (!sink.alive) return;
    final l10n = AppLocalizations.of(context);
    var asked = false;
    final outcome = await ref
        .read(pasteSenderProvider)
        .send(
          paneId,
          text,
          sink,
          confirm: (bytes) {
            asked = true;
            return ref
                .read(windowRouterProvider.notifier)
                .confirm(
                  ConfirmRequest(
                    title: l10n.pasteLargeTitle(
                      formatByteSize(bytes, locale: l10n.localeName),
                    ),
                    body: l10n.pasteLargeBody,
                    confirmLabel: l10n.pasteLargeAction,
                    destructive: false,
                  ),
                );
          },
        );
    // The dialog took the keyboard: give it back to the terminal.
    if (asked && mounted) focusTerminal();
    if (outcome == PasteOutcome.tooLarge && mounted) {
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(const PasteTooLargeNotice());
    }
  }

  @override
  void initState() {
    super.initState();
    focusTerminal(); // UI §3.6: the terminal has the initial focus.
    listenToConfig();
    listenToConfigUi();
    listenToSequences();
  }

  @override
  void dispose() {
    disposeSequences();
    disposeConfigUi();
    terminalFocus.dispose();
    sidebarFocus.dispose();
    emptyFocus.dispose();
    stripFocus.dispose();
    restoreStripFocus.dispose();
    daemonStripFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A new selection gets the keyboard (UI §3.6), except while the
    // sidebar has it: its arrow keys (Task 8) move the selection and must
    // keep the focus in the list. An open name field keeps it too (D15).
    // A3 (UI-A3 §6): so does a new focused pane of the selected tab.
    ref.listen(
      terminalTabsProvider.select(
        (s) => (s.selectedId, s.selected?.focusedPaneId),
      ),
      (_, next) {
        if (next.$1 != null &&
            !sidebarFocus.hasFocus &&
            ref.read(sidebarWorkspacesProvider).renaming == null) {
          focusTerminal();
        }
      },
    );
    // A8 (UI-A8 §8): the shown pane's connection changed — said once.
    ref.listen<TerminalTabsState>(terminalTabsProvider, (before, after) {
      final text = remoteAnnouncementBetween(
        AppLocalizations.of(context),
        before,
        after,
        ref.read(terminalTabsProvider.notifier).resolveReplaced,
      );
      if (text != null) _announce(text);
    });
    // The last tab closed: the keyboard goes to "Open new tab" instead of
    // vanishing with the terminal (after the frame that builds the button).
    ref.listen(terminalTabsProvider.select((s) => s.tabs.isEmpty), (
      wasEmpty,
      empty,
    ) {
      if (empty && wasEmpty == false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) emptyFocus.requestFocus();
        });
      }
    });
    // A10 D23 F3: the window is active again. If whatever had the keyboard
    // went away meanwhile (it fell back to the workspace scope itself, or
    // to nothing), the keyboard goes to the terminal; a field the user is
    // typing in, or an open dialog, panel or overlay, keeps it.
    ref.listen<bool>(windowFocusProvider, (_, focused) {
      if (!focused) return;
      // Never from a dialog, the panel or an overlay the user is in.
      if (panelOpen ||
          overlay != null ||
          ref.read(windowRouterProvider).dialogOpen) {
        return;
      }
      final current = FocusManager.instance.primaryFocus;
      if (current == null || current is FocusScopeNode) focusTerminal();
    });
    // A notification click, the panel, next unread (A4): the keyboard to
    // the selected tab's terminal; an open panel closes.
    ref.listen<int>(terminalFocusRequestProvider, (_, _) {
      closePanel(restoreFocus: false);
      focusTerminal();
    });
    _buildShortcuts(
      defaultTargetPlatform,
      ref.watch(shellxConfigProvider.select((s) => s.bindings)),
    );
    return Shortcuts(
      shortcuts: overlay == A9Overlay.shortcuts
          ? const {}
          : _workspaceShortcuts!,
      child: Actions(
        actions: actionsMap,
        // Every focus in the window sits inside this scope, so the
        // shortcuts work from any region and even when the focused node
        // goes away (it falls back to the scope itself, never above it).
        child: FocusScope(
          autofocus: true,
          debugLabel: 'workspace',
          child: sequenceScope(
            Stack(
              children: [
                // Modal for screen readers too while the panel is open.
                Positioned.fill(
                  child: ExcludeSemantics(
                    excluding: panelOpen || overlay != null,
                    child: _body(),
                  ),
                ),
                // UI-A4 §5.3: a click outside closes the panel (and only that).
                // macOS: it starts under the band, so the window still drags
                // (and the bell still toggles) while the panel is open. Both
                // slots are keyed: the barrier coming and going must not
                // shift the panel's AnimatedSwitcher to a new element (its
                // fade would never play).
                if (panelOpen)
                  Positioned(
                    key: const ValueKey('panel.barrierSlot'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    top: isMacDesktop ? ShellxSizes.headerBandMac : 0,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        key: const Key('panel.barrier'),
                        behavior: HitTestBehavior.opaque,
                        onTap: closePanel,
                        onSecondaryTap: closePanel,
                      ),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('panel.slot'),
                  // x 6: over the selected row's 3 px bar (x 6), not beside
                  // it (UI-A4 §5.2).
                  left: ShellxSpace.s6,
                  top:
                      (isMacDesktop
                          ? ShellxSizes.headerBandMac
                          : ShellxSizes.headerBandWindows) +
                      ShellxSizes.panelOffsetY,
                  child: AnimatedSwitcher(
                    duration: ShellxMotion.of(context, ShellxMotion.base),
                    reverseDuration: ShellxMotion.of(
                      context,
                      ShellxMotion.exit,
                    ),
                    switchInCurve: ShellxMotion.baseCurve,
                    switchOutCurve: ShellxMotion.exitCurve,
                    transitionBuilder: _panelTransition,
                    layoutBuilder: _topLeft,
                    child: panelOpen
                        ? NotificationsPanel(
                            key: const ValueKey('panel.open'),
                            onClose: closePanel,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                ?overlaySlot(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: ShellxSizes.sidebarWidth,
        child: SessionSidebar(
          focusNode: sidebarFocus,
          scrollController: sidebarScroll,
          onSelected: (id) {
            ref.read(terminalTabsProvider.notifier).select(id);
            focusTerminal();
          },
          onClose: closeTab,
          onEscape: focusTerminal,
          panelOpen: panelOpen,
          onToggleNotifications: togglePanel,
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: TerminalPane(
          terminalFocus: terminalFocus,
          emptyFocus: emptyFocus,
          stripFocus: stripFocus,
          restoreStripFocus: restoreStripFocus,
          daemonStripFocus: daemonStripFocus,
          shortcuts: overlay == A9Overlay.shortcuts
              ? const {}
              : terminalShortcuts,
          onKeyEvent: sequenceKey,
          onShowConfigProblems: () => openOverlay(A9Overlay.problems),
          onClosePane: (id) {
            final tab = ref.read(terminalTabsProvider).tabOfSession(id);
            if (tab != null) unawaited(closePane(tab, id));
          },
        ),
      ),
    ],
  );

  static Widget _topLeft(Widget? current, List<Widget> previous) =>
      Stack(alignment: Alignment.topLeft, children: [...previous, ?current]);

  /// UI-A4 §5.2: fade + translateY −4 → 0 in `base`; out, a fade in
  /// `exit`. The outgoing panel takes no clicks and no keyboard.
  static Widget _panelTransition(Widget child, Animation<double> animation) =>
      AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final leaving = animation.status == AnimationStatus.reverse;
          return IgnorePointer(
            ignoring: leaving,
            child: ExcludeFocus(
              excluding: leaving,
              child: FadeTransition(
                opacity: animation,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    leaving ? 0 : -ShellxSpace.s4 * (1 - animation.value),
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: child,
      );
}
