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
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_focus.dart';
import '../window_router.dart';
import 'close_tab.dart';
import 'notifications_panel.dart';
import 'session_sidebar.dart';
import 'shortcut_labels.dart';
import 'terminal_pane.dart';
import 'terminal_shortcuts.dart';

/// Spec §3.2: `Row(Sidebar 220 px, VerticalDivider, TerminalPane)`.
class TerminalWorkspacePage extends ConsumerStatefulWidget {
  const TerminalWorkspacePage({super.key});

  @override
  ConsumerState<TerminalWorkspacePage> createState() =>
      TerminalWorkspacePageState();
}

class TerminalWorkspacePageState extends ConsumerState<TerminalWorkspacePage> {
  final terminalFocus = FocusNode(debugLabel: 'terminal');
  final sidebarFocus = FocusNode(debugLabel: 'sidebar');

  /// The empty state's "Open new tab" (focused when the last tab closes).
  final emptyFocus = FocusNode(debugLabel: 'open new tab');

  /// The signed-out strip's "Sign in" (UI §3.6 region 3).
  final stripFocus = FocusNode(debugLabel: 'signed-out strip');
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

  void _buildShortcuts(TargetPlatform platform) {
    if (_shortcutsPlatform == platform && terminalShortcuts != null) return;
    _shortcutsPlatform = platform;
    terminalShortcuts = terminalViewShortcuts(platform);
    _workspaceShortcuts = desktopShortcuts(platform);
  }

  /// After the frame, so a TerminalView that just got [terminalFocus] (a
  /// new selection) is attached first. With no tab the keyboard goes to
  /// "Open new tab", so it never ends up outside the window shortcuts.
  ///
  /// A post-frame callback alone waits for a frame something else asks
  /// for (Esc in the sidebar changes nothing on screen), hence the
  /// explicit request.
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
    _beforePanel = FocusManager.instance.primaryFocus;
    setState(() => panelOpen = true); // the panel takes the keyboard
  }

  /// Esc, a click outside, a jump, or another window shortcut. With
  /// [restoreFocus] the keyboard goes back at once, so a shortcut that
  /// runs next (F6) starts from where the user was.
  void closePanel({bool restoreFocus = true}) {
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

  Future<void> closeTab(TerminalTab tab) => closeTabWithConfirm(
    tabs: ref.read(terminalTabsProvider.notifier),
    router: ref.read(windowRouterProvider.notifier),
    l10n: AppLocalizations.of(context),
    tab: tab,
  );

  /// UI §3.6 regions: terminal (or "Open new tab" with no tab), sidebar,
  /// signed-out strip (when shown).
  void _cycleRegion(int step) {
    final signedOut =
        ref.read(agentControllerProvider).phase == AuthPhase.signedOut;
    final noTab = ref.read(terminalTabsProvider).tabs.isEmpty;
    final regions = [
      noTab ? emptyFocus : terminalFocus,
      if (!noTab) sidebarFocus, // an empty list is no stop (UI §3.6)
      if (signedOut) stripFocus,
    ];
    final current = regions.indexWhere((node) => node.hasFocus);
    // From outside every region (the `+` button, a toast…) the sidebar
    // counts as the current region: `+` belongs to it.
    final from = current >= 0 ? current : (noTab ? 0 : 1);
    regions[(from + step) % regions.length].requestFocus();
  }

  /// Built once; every action reads the providers when it runs.
  late final _actionsMap = _actions();

  Map<Type, Action<Intent>> _actions() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    Action<T> run<T extends Intent>(
      void Function(T intent) body, {
      bool Function(T intent)? enabled,
    }) => _WindowAction<T>(body, enabled);
    return <Type, Action<Intent>>{
      // UI-A4 §5.3: the other window shortcuts still run with the panel
      // open; they close it first.
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        unawaited(tabs.openTab());
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
        } else {
          unawaited(closeTab(selected));
        }
      }),
      SelectTabIntent: run<SelectTabIntent>(
        (intent) {
          closePanel();
          workspaces.selectVisible(intent.position);
          focusTerminal();
        },
        // On Windows AltGr arrives as Ctrl+Alt, and AltGr+digit types
        // `{ [ ] }` on many layouts (German, Polish…): with the right Alt
        // held the key stays the shell's.
        enabled: (_) =>
            defaultTargetPlatform != TargetPlatform.windows ||
            !HardwareKeyboard.instance.logicalKeysPressed.contains(
              LogicalKeyboardKey.altRight,
            ),
      ),
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
      FontBiggerIntent: run<FontBiggerIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).increase(),
      ),
      FontSmallerIntent: run<FontSmallerIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).decrease(),
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
    };
  }

  void _copy() {
    final tab = ref.read(terminalTabsProvider).selected;
    final range = tab?.selection.selection;
    if (tab == null || range == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: tab.terminal.buffer.getText(range)),
      ),
    );
    tab.selection.clearSelection();
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

  /// ⌘V / Ctrl+Shift+V into the selected tab, sanitised (and bracketed when
  /// the program asked for it) by DesktopTerminal.paste.
  Future<void> _paste() async {
    final id = ref.read(terminalTabsProvider).selectedId;
    if (id == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) return;
    final tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == id)
        .firstOrNull;
    // An exited tab closes on Enter (UI §2.6): a paste must not do that.
    if (tab == null || tab.exited) return;
    tab.terminal.paste(text);
  }

  @override
  void initState() {
    super.initState();
    focusTerminal(); // UI §3.6: the terminal has the initial focus.
  }

  @override
  void dispose() {
    terminalFocus.dispose();
    sidebarFocus.dispose();
    emptyFocus.dispose();
    stripFocus.dispose();
    sidebarScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A new selection gets the keyboard (UI §3.6), except while the
    // sidebar has it: its arrow keys (Task 8) move the selection and must
    // keep the focus in the list. An open name field keeps it too (D15).
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id != null &&
          !sidebarFocus.hasFocus &&
          ref.read(sidebarWorkspacesProvider).renaming == null) {
        focusTerminal();
      }
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
    // A notification click, the panel, next unread (A4): the keyboard to
    // the selected tab's terminal; an open panel closes.
    ref.listen<int>(terminalFocusRequestProvider, (_, _) {
      closePanel(restoreFocus: false);
      focusTerminal();
    });
    _buildShortcuts(defaultTargetPlatform);
    return Shortcuts(
      shortcuts: _workspaceShortcuts!,
      child: Actions(
        actions: _actionsMap,
        // Every focus in the window sits inside this scope, so the
        // shortcuts work from any region and even when the focused node
        // goes away (it falls back to the scope itself, never above it).
        child: FocusScope(
          autofocus: true,
          debugLabel: 'workspace',
          child: Stack(
            children: [
              // Modal for screen readers too while the panel is open.
              Positioned.fill(
                child: ExcludeSemantics(excluding: panelOpen, child: _body()),
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
                  reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
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
            ],
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
          shortcuts: terminalShortcuts,
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

/// A window shortcut's action; [enabled] lets a key fall through to the
/// terminal when it does not apply.
class _WindowAction<T extends Intent> extends Action<T> {
  _WindowAction(this._body, this._enabled);
  final void Function(T intent) _body;
  final bool Function(T intent)? _enabled;

  @override
  bool isEnabled(T intent) => _enabled?.call(intent) ?? true;

  @override
  Object? invoke(T intent) {
    _body(intent);
    return null;
  }
}
