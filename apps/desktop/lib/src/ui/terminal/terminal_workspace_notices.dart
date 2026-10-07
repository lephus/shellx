import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config_controller.dart';
import '../../config/config_opener.dart';
import '../../config/config_problem.dart';
import '../../terminal/terminal_tabs.dart';
import '../config/config_problems_panel.dart';
import '../config/config_ui_request.dart';
import '../theme/shellx_desktop_theme.dart';
import 'key_sequence.dart';
import 'shortcut_labels.dart';

/// A9's overlays over the workspace (UI-A9 §2-4).
enum A9Overlay { palette, problems, shortcuts }

/// One problem for the toast's "already told" check: where and what, never
/// the text (D36: a problem that stays is not announced on every reload).
typedef _ProblemKey = (String, int, ConfigProblemCode);

Set<_ProblemKey> _visibleKeys(Iterable<ConfigProblem> problems) => {
  for (final p in problems)
    if (p.severity != ConfigSeverity.info) (p.file, p.line, p.code),
};

/// A9's toasts for the loads and the problems panel slot, kept apart from
/// the page.
mixin WorkspaceConfigUi<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  void closePanel({bool restoreFocus = true});
  void focusTerminal();

  A9Overlay? overlay;
  FocusNode? _beforeOverlay;

  // The overlays that exist so far (the palette and the shortcut editor
  // arrive with their own tasks).
  static const _built = {A9Overlay.problems};

  void openOverlay(A9Overlay next) {
    if (!_built.contains(next)) return;
    // Before closing whatever is open, which clears it.
    final before = _beforeOverlay ?? FocusManager.instance.primaryFocus;
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

  ConfigLoad? _handledLoad;
  Set<_ProblemKey> _loadKeys = {};
  Set<_ProblemKey> _runtimeSeen = {};

  /// Toasts follow the loads (D36), the tray's requests open the overlays.
  /// The first look at the state is after the frame: the startup load ran
  /// before this page, and Riverpod 3 forbids provider writes while the
  /// tree builds (preflight D4).
  void listenToConfigUi() {
    ref.listenManual(shellxConfigProvider, _onConfig);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onConfig(null, ref.read(shellxConfigProvider));
    });
    // A Ghostty notice waiting for a free toast slot.
    ref.listenManual(terminalTabsProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) _showGhosttyIfDue();
    });
    ref.listenManual(configUiRequestProvider, (_, next) {
      if (next == null) return;
      openOverlay(switch (next.$1) {
        ConfigUiRequest.palette => A9Overlay.palette,
        ConfigUiRequest.problems => A9Overlay.problems,
        ConfigUiRequest.shortcuts => A9Overlay.shortcuts,
      });
    });
  }

  void _onConfig(ConfigState? previous, ConfigState notified) {
    // A listener before this one (the font probe) may have published again
    // while this notification was on its way: judge the latest state.
    final next = ref.read(shellxConfigProvider);
    final load = next.lastLoad;
    if (load != null && !identical(load, _handledLoad)) {
      _handledLoad = load;
      _onLoad(load, next);
    }
    if (previous == null ||
        !identical(previous.runtimeProblems, next.runtimeProblems)) {
      _onRuntime(next);
    }
    _showGhosttyIfDue();
  }

  void _onLoad(ConfigLoad load, ConfigState next) {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final keys = _visibleKeys(next.loadProblems);
    final fresh = keys.difference(_loadKeys);
    _loadKeys = keys;
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

  /// What only the window can find (the font probe): told once per
  /// problem, not on every reload that finds it again.
  void _onRuntime(ConfigState next) {
    final current = _visibleKeys(next.runtimeProblems);
    final fresh = current.difference(_runtimeSeen);
    _runtimeSeen.addAll(current);
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

  /// The probe ran for the current load: a runtime problem it no longer
  /// finds is told again if it comes back.
  void forgetFixedRuntimeProblems() {
    _runtimeSeen = _runtimeSeen.intersection(
      _visibleKeys(ref.read(shellxConfigProvider).runtimeProblems),
    );
  }

  /// D4: shown once, when no other toast is up; acknowledged only after it
  /// was shown, so it survives a first load that raised problems.
  void _showGhosttyIfDue() {
    if (!ref.read(shellxConfigProvider).ghosttyNoticePending) return;
    if (ref.read(terminalTabsProvider).notice != null) return;
    ref
        .read(terminalTabsProvider.notifier)
        .showNotice(const ConfigGhosttyNotice());
    ref.read(shellxConfigProvider.notifier).ackGhosttyNotice();
  }
}
