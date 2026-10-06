import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/agent_state.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'close_tab.dart';
import 'session_sidebar.dart';
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

  /// Spec criterion 2: the window shortcuts, also handed to every
  /// TerminalView.
  Map<ShortcutActivator, Intent>? terminalShortcuts;
  TargetPlatform? _shortcutsPlatform;

  /// Built once: a new map on every build would make each TerminalView
  /// rebuild its shortcut index.
  Map<ShortcutActivator, Intent> _shortcutsFor(TargetPlatform platform) {
    if (_shortcutsPlatform != platform || terminalShortcuts == null) {
      _shortcutsPlatform = platform;
      terminalShortcuts = desktopShortcuts(platform);
    }
    return terminalShortcuts!;
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
    CallbackAction<T> run<T extends Intent>(void Function(T intent) body) =>
        CallbackAction<T>(
          onInvoke: (intent) {
            body(intent);
            return null;
          },
        );
    return <Type, Action<Intent>>{
      NewTabIntent: run<NewTabIntent>((_) {
        unawaited(tabs.openTab());
        focusTerminal();
      }),
      CloseTabIntent: run<CloseTabIntent>((_) {
        final selected = ref.read(terminalTabsProvider).selected;
        if (selected == null) {
          // UI §2.7 (accepted): ⌘W on the empty state hides the window.
          ref.read(windowRouterProvider.notifier).hideWindow();
        } else {
          unawaited(closeTab(selected));
        }
      }),
      SelectTabIntent: _SelectTabAction((intent) {
        tabs.selectIndex(intent.position);
        focusTerminal();
      }),
      NextTabIntent: run<NextTabIntent>((_) {
        tabs.next();
        focusTerminal();
      }),
      PreviousTabIntent: run<PreviousTabIntent>((_) {
        tabs.previous();
        focusTerminal();
      }),
      CopySelectionIntent: _CopyAction(ref),
      PasteClipboardIntent: run<PasteClipboardIntent>((_) {
        unawaited(_paste());
      }),
      FontBiggerIntent: run<FontBiggerIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).increase(),
      ),
      FontSmallerIntent: run<FontSmallerIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).decrease(),
      ),
      FontResetIntent: run<FontResetIntent>(
        (_) => ref.read(terminalFontSizeProvider.notifier).reset(),
      ),
      NextRegionIntent: run<NextRegionIntent>((_) => _cycleRegion(1)),
      PreviousRegionIntent: run<PreviousRegionIntent>((_) => _cycleRegion(-1)),
    };
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
    // keep the focus in the list.
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id != null && !sidebarFocus.hasFocus) focusTerminal();
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
    final shortcuts = _shortcutsFor(defaultTargetPlatform);
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: _actionsMap,
        // Every focus in the window sits inside this scope, so the
        // shortcuts work from any region and even when the focused node
        // goes away (it falls back to the scope itself, never above it).
        child: FocusScope(
          autofocus: true,
          debugLabel: 'workspace',
          child: Row(
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
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: TerminalPane(
                  terminalFocus: terminalFocus,
                  emptyFocus: emptyFocus,
                  stripFocus: stripFocus,
                  shortcuts: shortcuts,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ⌘C / Ctrl+Shift+C copies only when there is a selection; while disabled
/// the shortcut manager leaves the key to the terminal (spec §3.2).
class _CopyAction extends Action<CopySelectionIntent> {
  _CopyAction(this._ref);
  final WidgetRef _ref;

  @override
  bool isEnabled(CopySelectionIntent intent) =>
      _ref.read(terminalTabsProvider).selected?.selection.selection != null;

  @override
  Object? invoke(CopySelectionIntent intent) {
    final tab = _ref.read(terminalTabsProvider).selected;
    final range = tab?.selection.selection;
    if (tab == null || range == null) return null;
    unawaited(
      Clipboard.setData(
        ClipboardData(text: tab.terminal.buffer.getText(range)),
      ),
    );
    tab.selection.clearSelection();
    return null;
  }
}

/// ⌘1…⌘9 / Ctrl+Alt+1…9. On Windows AltGr arrives as Ctrl+Alt, and
/// AltGr+digit types `{ [ ] }` on many layouts (German, Polish…): with the
/// right Alt held the key stays the shell's.
class _SelectTabAction extends CallbackAction<SelectTabIntent> {
  _SelectTabAction(void Function(SelectTabIntent intent) select)
    : super(
        onInvoke: (intent) {
          select(intent);
          return null;
        },
      );

  @override
  bool isEnabled(SelectTabIntent intent) =>
      defaultTargetPlatform != TargetPlatform.windows ||
      !HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.altRight,
      );
}
