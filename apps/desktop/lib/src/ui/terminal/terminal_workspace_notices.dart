import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_opener.dart';
import '../../config/config_problem.dart';
import '../../config/keybind_actions.dart' show describeIntent;
import '../../terminal/closed_items.dart' show closedItemsProvider;
import '../../terminal/find_sessions.dart';
import '../../terminal/global_search.dart' show GlobalHit;
import '../../terminal/sidebar_workspaces.dart' show sidebarWorkspacesProvider;
import '../../terminal/terminal_tabs.dart';
import '../config/command_palette.dart';
import '../config/config_problems_panel.dart';
import '../config/config_ui_request.dart';
import '../config/search_all_overlay.dart';
import '../config/shortcuts_sheet.dart';
import '../settings/settings_overlay.dart';
import '../window_router.dart';
import '../theme/shellx_desktop_theme.dart';
import 'key_sequence.dart';
import 'terminal_intents.dart';
import 'shortcut_labels.dart';

/// A9's overlays over the workspace (UI-A9 §2-4).
enum A9Overlay { palette, problems, shortcuts, settings, searchAll }

/// One problem for the toast's "already told" check: where and what, never
/// the text (D36: a problem that stays is not announced on every reload).
typedef ProblemKey = (String, int, ConfigProblemCode);

/// What the toasts already told, kept outside the page: closing and
/// reopening the window builds a new page that must not tell it again.
final class ConfigToastMemory {
  ConfigLoad? handledLoad;
  Set<ProblemKey> loadKeys = {};
  Set<ProblemKey> runtimeSeen = {};
}

final configToastMemoryProvider = Provider<ConfigToastMemory>(
  (ref) => ConfigToastMemory(),
);

Set<ProblemKey> _visibleKeys(Iterable<ConfigProblem> problems) => {
  for (final p in problems)
    if (p.severity != ConfigSeverity.info) (p.file, p.line, p.code),
};

/// A9's toasts for the loads and the problems panel slot, kept apart from
/// the page.
mixin WorkspaceConfigUi<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  void closePanel({bool restoreFocus = true});
  void focusTerminal();
  Map<Type, Action<Intent>> get actionsMap;
  bool invokeIntent(Intent intent);

  A9Overlay? overlay;
  FocusNode? _beforeOverlay;

  /// D33: the entries are fixed when the palette opens, before the focus
  /// moves into it (whether copy applies depends on where the keyboard
  /// was); the last eight run ones, in memory only, newest first.
  List<PaletteEntry> _paletteEntries = const [];
  final List<String> _recent = [];

  /// What applied when the palette opened (by intent), so that a reload
  /// under the open palette does not re-ask questions that depend on where
  /// the keyboard was: the field has it now.
  Set<String> _openIntents = const {};

  /// A reload while the palette is open: the entries follow the new
  /// configuration (a removed command is gone, a rebound key shows its new
  /// label); the palette keeps its query and its cursor.
  void _refreshPalette() {
    if (overlay != A9Overlay.palette) return;
    final state = ref.read(shellxConfigProvider);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _paletteEntries = [
        ...paletteEntries(
          l10n: l10n,
          config: state,
          enabled: (intent) {
            if (intent is ShowConfigProblemsIntent) {
              return state.visibleProblemCount > 0;
            }
            if (intent is RunUserCommandIntent) return true;
            return _openIntents.contains(describeIntent(intent));
          },
        ),
        ..._moveEntries(l10n),
      ];
    });
  }

  /// A11 D20: "Move tab to {workspace}" for each other workspace and "Move
  /// pane to tab {label}" for up to 20 other tabs, in sidebar order; they
  /// stand for the selected tab and its focused pane.
  List<PaletteEntry> _moveEntries(AppLocalizations l10n) {
    final tabs = ref.read(terminalTabsProvider);
    final selected = tabs.selected;
    if (selected == null) return const [];
    final side = ref.read(sidebarWorkspacesProvider);
    final here = side.workspaceOf(selected.id);
    PaletteEntry entry(String id, String title, Intent intent) => PaletteEntry(
      id: id,
      title: title,
      subtitle: null,
      kind: PaletteKind.action,
      shortcut: null,
      intent: intent,
    );
    return [
      for (final w in side.workspaces)
        if (w.id != here)
          entry(
            'move-tab:${w.id}',
            l10n.moveTabToWorkspace(w.displayName(l10n)),
            MoveTabToWorkspaceIntent(w.id),
          ),
      for (final id
          in side.orderedTabIds
              .where((id) => id != selected.id)
              .where((id) => tabs.tabs.any((t) => t.id == id))
              .take(20))
        entry(
          'join-pane:$id',
          l10n.movePaneToTab(tabs.tabs.firstWhere((t) => t.id == id).label),
          JoinPaneIntent(tabId: id),
        ),
    ];
  }

  List<PaletteEntry> _buildPaletteEntries() {
    final state = ref.read(shellxConfigProvider);
    final hasTab = ref.read(terminalTabsProvider).selected != null;
    final entries = paletteEntries(
      l10n: AppLocalizations.of(context),
      config: state,
      enabled: (intent) {
        if (intent is ShowConfigProblemsIntent) {
          return state.visibleProblemCount > 0;
        }
        if (intent is CommandPaletteIntent) return false;
        // With no tab there is nothing to paste into (the chord itself
        // stays enabled: it falls through to nothing).
        if (intent is PasteClipboardIntent && !hasTab) return false;
        // A11 D14: the key still answers "nothing to reopen"; the palette
        // entry is off while there is nothing.
        if (intent is ReopenClosedIntent) {
          return ref.read(closedItemsProvider).length > 0;
        }
        final action = actionsMap[intent.runtimeType];
        return action != null && action.isEnabled(intent);
      },
    );
    _openIntents = {for (final e in entries) describeIntent(e.intent)};
    return [...entries, ..._moveEntries(AppLocalizations.of(context))];
  }

  /// Enter or a click: close first (the keyboard goes back where it was),
  /// then run, so the action starts from the user's own focus.
  void _runPalette(PaletteEntry entry) {
    closeOverlay();
    _recent
      ..remove(entry.id)
      ..insert(0, entry.id);
    if (_recent.length > 8) _recent.removeLast();
    invokeIntent(entry.intent);
  }

  /// A11 D21: a chosen match — its tab is selected, its pane focused and
  /// its find bar opened on [query], standing on the match. The bar's
  /// reveal exists only once the pane has built it, so the jump is made
  /// again after that frame.
  void _openSearchHit(GlobalHit hit, String query) {
    closeOverlay(restoreFocus: false);
    final tab = ref.read(terminalTabsProvider).tabOfSession(hit.paneId);
    if (tab == null) {
      focusTerminal(); // the pane closed meanwhile
      return;
    }
    ref.read(sidebarWorkspacesProvider.notifier).reveal(tab.id);
    ref.read(terminalTabsProvider.notifier).focusPane(hit.paneId);
    final find = ref.read(findSessionsProvider.notifier).open(hit.paneId);
    if (find == null) {
      focusTerminal();
      return;
    }
    if (find.matchCase) find.toggleMatchCase();
    find.setQuery(query);
    // A line that left the history: the first match of the pane.
    final row = hit.liveRow ?? 0;
    find.goToMatchAtOrAfter(row);
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        final live = ref.read(findSessionsProvider)[hit.paneId];
        if (live == null) return;
        live.goToMatchAtOrAfter(row);
        live.focusNode.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  void openOverlay(A9Overlay next) {
    // Before closing whatever is open, which clears it.
    final before = _beforeOverlay ?? FocusManager.instance.primaryFocus;
    if (next == A9Overlay.palette) _paletteEntries = _buildPaletteEntries();
    closePanel(restoreFocus: false);
    ref.read(keySequenceProvider.notifier).cancel();
    _beforeOverlay = before;
    setState(() => overlay = next);
  }

  void closeOverlay({bool restoreFocus = true}) {
    if (overlay == null) return;
    final before = _beforeOverlay;
    _beforeOverlay = null;
    setState(() => overlay = null);
    if (!restoreFocus) return;
    if (before != null && before.context != null && before.canRequestFocus) {
      before.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
    } else {
      focusTerminal();
    }
  }

  /// `closePanel` calls it first, before its own early return, so every
  /// window shortcut dismisses an open overlay (UI-A9 §2.2).
  void closeConfigOverlay({bool restoreFocus = true}) =>
      closeOverlay(restoreFocus: restoreFocus);

  /// The overlay's slot in the window's stack (null: nothing open).
  Widget? overlaySlot() {
    if (overlay == A9Overlay.palette) {
      return Positioned(
        key: const ValueKey('a9.palette'),
        left: ShellxSizes.sidebarWidth + 1,
        right: 0,
        top:
            (isMacDesktop ? ShellxSizes.paneHeaderMac : 0) +
            ShellxSizes.paletteTop,
        child: Align(
          alignment: Alignment.topCenter,
          child: TapRegion(
            onTapOutside: (_) => closeOverlay(),
            child: CommandPalette(
              entries: _paletteEntries,
              recent: _recent,
              onRun: _runPalette,
              onClose: closeOverlay,
            ),
          ),
        ),
      );
    }
    if (overlay == A9Overlay.searchAll) {
      return Positioned(
        key: const ValueKey('a9.searchall'),
        left: ShellxSizes.sidebarWidth + 1,
        right: 0,
        top:
            (isMacDesktop ? ShellxSizes.paneHeaderMac : 0) +
            ShellxSizes.paletteTop,
        child: Align(
          alignment: Alignment.topCenter,
          child: TapRegion(
            onTapOutside: (_) => closeOverlay(),
            child: SearchAllOverlay(
              onOpen: _openSearchHit,
              onClose: closeOverlay,
            ),
          ),
        ),
      );
    }
    if (overlay == A9Overlay.shortcuts) {
      // The sheet blocks the window (UI-A9 §4.2): a scrim behind it, and
      // the workspace shortcuts are off meanwhile (the page empties them).
      return Positioned.fill(
        key: const ValueKey('a9.shortcuts'),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ModalBarrier(
                color: ShellxDesktopColors.scrim,
                dismissible: false,
              ),
            ),
            Center(
              child: ShortcutsSheet(
                onClose: closeOverlay,
                onOpenFile: () {
                  closeOverlay();
                  unawaited(openShellxConfig(ref.read));
                },
              ),
            ),
          ],
        ),
      );
    }
    if (overlay == A9Overlay.settings) {
      // Blocks the window like the shortcut sheet: a scrim, and the
      // workspace shortcuts are off meanwhile (the page empties them).
      return Positioned.fill(
        key: const ValueKey('a9.settings'),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ModalBarrier(
                color: ShellxDesktopColors.scrim,
                dismissible: false,
              ),
            ),
            Center(
              child: SettingsOverlay(
                onClose: closeOverlay,
                onOpenFile: () {
                  closeOverlay();
                  unawaited(openShellxConfig(ref.read));
                },
              ),
            ),
          ],
        ),
      );
    }
    if (overlay != A9Overlay.problems) return null;
    return Positioned(
      key: const ValueKey('a9.problems'),
      left: ShellxSizes.sidebarWidth + 1,
      right: 0,
      top:
          (isMacDesktop ? ShellxSizes.paneHeaderMac : 0) +
          ShellxSizes.paletteTop,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConfigProblemsPanel(
          onClose: closeOverlay,
          onOpenFile: () {
            closeOverlay();
            unawaited(openShellxConfig(ref.read));
          },
          onReload: () => unawaited(
            ref.read(shellxConfigProvider.notifier).load(manual: true),
          ),
        ),
      ),
    );
  }

  ConfigToastMemory get _memory => ref.read(configToastMemoryProvider);

  /// The latest generation the font probe has reported for (-1: none yet).
  int _probedGeneration = -1;
  ConfigLoad? _pendingLoad;
  Timer? _loadTimer;

  /// How long a load's feedback waits for the probe before it is decided
  /// without it.
  static const _probeBound = Duration(milliseconds: 500);

  void disposeConfigUi() {
    _loadTimer?.cancel();
    _loadTimer = null;
  }

  /// Toasts follow the loads (D36), the tray's requests open the overlays.
  /// The first look at the state is after the frame: the startup load ran
  /// before this page, and Riverpod 3 forbids provider writes while the
  /// tree builds (preflight D4).
  void listenToConfigUi() {
    ref.listenManual(shellxConfigProvider, _onConfig);
    ref.listenManual(shellxConfigProvider, (_, _) => _refreshPalette());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onConfig(null, ref.read(shellxConfigProvider));
    });
    // A Ghostty notice waiting for a free toast slot or a visible window.
    ref.listenManual(terminalTabsProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) _showGhosttyIfDue();
    });
    ref.listenManual(windowRouterProvider.select((s) => s.visible), (_, _) {
      _showGhosttyIfDue();
    });
    ref.listenManual(configUiRequestProvider, (_, next) {
      if (next == null) return;
      openOverlay(switch (next.$1) {
        ConfigUiRequest.palette => A9Overlay.palette,
        ConfigUiRequest.problems => A9Overlay.problems,
        ConfigUiRequest.shortcuts => A9Overlay.shortcuts,
        ConfigUiRequest.settings => A9Overlay.settings,
        ConfigUiRequest.searchAll => A9Overlay.searchAll,
      });
    });
  }

  void _onConfig(ConfigState? previous, ConfigState notified) {
    // A listener before this one (the font probe) may have published again
    // while this notification was on its way: judge the latest state.
    final next = ref.read(shellxConfigProvider);
    final load = next.lastLoad;
    if (load != null && !identical(load, _memory.handledLoad)) {
      _memory.handledLoad = load;
      if (_probedGeneration >= next.generation) {
        _onLoad(load, next);
      } else {
        // Decided once the probe has reported for this generation, so a
        // problem that the probe finds again is never taken for a fix.
        _pendingLoad = load;
        _loadTimer?.cancel();
        _loadTimer = Timer(_probeBound, _flushLoad);
      }
    }
    if (previous == null ||
        !identical(previous.runtimeProblems, next.runtimeProblems)) {
      _onRuntime(next);
    }
    _refreshCount(next);
    _showGhosttyIfDue();
  }

  void _flushLoad() {
    _loadTimer?.cancel();
    _loadTimer = null;
    final load = _pendingLoad;
    _pendingLoad = null;
    if (load != null && mounted) {
      _onLoad(load, ref.read(shellxConfigProvider));
    }
  }

  void _onLoad(ConfigLoad load, ConfigState next) {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final keys = _visibleKeys(next.loadProblems);
    final fresh = keys.difference(_memory.loadKeys);
    _memory.loadKeys = keys;
    final count = next.visibleProblemCount;
    if (count > 0) {
      if (fresh.isNotEmpty || load.manual) {
        tabs.showNotice(
          ConfigProblemsNotice(count, hasErrors: next.errorCount > 0),
        );
      }
      return;
    }
    if (ref.read(terminalTabsProvider).notice is ConfigProblemsNotice) {
      tabs.dismissNotice();
    }
    if (load.manual) tabs.showNotice(const ConfigReloadedNotice());
  }

  /// A problems toast that is up shows the current count once the load is
  /// settled (the probe has reported); it never shows 0 (a fix dismisses it).
  void _refreshCount(ConfigState next) {
    if (_pendingLoad != null || _probedGeneration < next.generation) return;
    final shown = ref.read(terminalTabsProvider).notice;
    final count = next.visibleProblemCount;
    if (shown is! ConfigProblemsNotice || count == 0) return;
    final errors = next.errorCount > 0;
    if (shown.count == count && shown.hasErrors == errors) return;
    ref
        .read(terminalTabsProvider.notifier)
        .showNotice(ConfigProblemsNotice(count, hasErrors: errors));
  }

  /// What only the window can find (the font probe): told once per
  /// problem, not on every reload that finds it again.
  void _onRuntime(ConfigState next) {
    final current = _visibleKeys(next.runtimeProblems);
    final fresh = current.difference(_memory.runtimeSeen);
    _memory.runtimeSeen.addAll(current);
    if (fresh.isEmpty) return;
    ref
        .read(terminalTabsProvider.notifier)
        .showNotice(
          ConfigProblemsNotice(
            next.visibleProblemCount,
            hasErrors: next.errorCount > 0,
          ),
        );
  }

  /// The probe has reported for the current generation: a runtime problem
  /// it no longer finds is told again if it comes back, and the load's
  /// feedback (waiting for this) is decided.
  void forgetFixedRuntimeProblems() {
    final state = ref.read(shellxConfigProvider);
    _probedGeneration = state.generation;
    _memory.runtimeSeen = _memory.runtimeSeen.intersection(
      _visibleKeys(state.runtimeProblems),
    );
    if (_pendingLoad != null) _flushLoad();
  }

  /// D4: shown once, when no other toast is up; acknowledged only after it
  /// was shown, so it survives a first load that raised problems.
  void _showGhosttyIfDue() {
    if (!ref.read(shellxConfigProvider).ghosttyNoticePending) return;
    if (ref.read(terminalTabsProvider).notice != null) return;
    // Acknowledged only when someone can see it.
    if (!ref.read(windowRouterProvider).visible) return;
    ref
        .read(terminalTabsProvider.notifier)
        .showNotice(const ConfigGhosttyNotice());
    ref.read(shellxConfigProvider.notifier).ackGhosttyNotice();
  }
}
