import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config_controller.dart';
import '../../config/config_opener.dart';
import '../../config/font_probe.dart';
import '../../config/keybind_trigger.dart' show altGrHeld;
import '../../config/shellx_config.dart';
import '../../terminal/pane_paste.dart';
import '../../terminal/terminal_tabs.dart';
import '../../terminal/user_commands.dart';
import 'terminal_intents.dart';
import 'terminal_workspace_notices.dart' show A9Overlay;
import '../settings/update_check_ui.dart';

/// A window shortcut's action; [enabled] lets a key fall through to the
/// terminal when it does not apply.
///
/// A9 D26 (A1, A3 D20, for every chord): with the right Alt held on
/// Windows (AltGr = Ctrl + right Alt) the key is the keyboard layout's, so
/// no window shortcut runs, whatever its intent or whether the user bound
/// it. Left Ctrl+Alt chords are unaffected.
class WindowAction<T extends Intent> extends Action<T> {
  WindowAction(this._body, this._enabled, {bool Function()? altGrHeld})
    : _altGrHeld = altGrHeld ?? _hardwareAltGr;
  final void Function(T intent) _body;
  final bool Function(T intent)? _enabled;
  final bool Function() _altGrHeld;

  static bool _hardwareAltGr() => altGrHeld(
    HardwareKeyboard.instance.logicalKeysPressed,
    defaultTargetPlatform,
  );

  @override
  bool isEnabled(T intent) => !_altGrHeld() && (_enabled?.call(intent) ?? true);

  @override
  Object? invoke(T intent) {
    _body(intent);
    return null;
  }
}

/// A9's part of the workspace window: the actions of the config intents,
/// the font probe, running a user command. Kept apart from the page.
mixin WorkspaceConfig<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  // What the page provides.
  void closePanel({bool restoreFocus = true});
  void focusTerminal();
  Future<void> closeTab(TerminalTab tab);
  FocusNode get terminalFocus;
  Map<Type, Action<Intent>> get actionsMap;

  // From WorkspaceConfigUi: closes whichever A9 overlay is open (`closePanel`
  // calls it first); opens one; forgets font problems the probe no longer
  // finds.
  void closeConfigOverlay({bool restoreFocus = true});
  void openOverlay(A9Overlay overlay);
  void openWhatsNew();
  A9Overlay? get overlay;
  void forgetFixedRuntimeProblems();

  /// The actions of the A9 intents.
  Map<Type, Action<Intent>> configActions() {
    Action<I> run<I extends Intent>(
      void Function(I intent) body, {
      bool Function(I intent)? enabled,
    }) => WindowAction<I>(body, enabled);
    return <Type, Action<Intent>>{
      // The whole tab, every pane (A3 D6's row ×), not only the focused one.
      CloseWholeTabIntent: run<CloseWholeTabIntent>((_) {
        closePanel();
        final selected = ref.read(terminalTabsProvider).selected;
        if (selected != null) unawaited(closeTab(selected));
      }, enabled: (_) => ref.read(terminalTabsProvider).selected != null),
      ReloadConfigIntent: run<ReloadConfigIntent>((_) {
        closePanel();
        unawaited(ref.read(shellxConfigProvider.notifier).load(manual: true));
      }),
      OpenSettingsIntent: run<OpenSettingsIntent>(
        (_) => openOverlay(A9Overlay.settings),
      ),
      OpenConfigIntent: run<OpenConfigIntent>((_) {
        closePanel();
        unawaited(openShellxConfig(ref.read));
      }),
      RunUserCommandIntent: run<RunUserCommandIntent>(
        (intent) => _runCommand(intent.name),
      ),
      // Only while a terminal has the keyboard: in the sidebar the key is
      // the sidebar's.
      SendTextIntent: run<SendTextIntent>(
        (intent) =>
            sendTextToFocused(ref.read(terminalTabsProvider), intent.text),
        enabled: (_) => terminalFocus.hasFocus,
      ),
      IgnoreKeyIntent: run<IgnoreKeyIntent>((_) {}),
      // ⌘⇧P opens the palette, and closes it when it is open (D33).
      CommandPaletteIntent: run<CommandPaletteIntent>(
        (_) => overlay == A9Overlay.palette
            ? closeConfigOverlay()
            : openOverlay(A9Overlay.palette),
      ),
      // A11 D21: ⌘⇧F opens the all-terminals search, and closes it when
      // it is open.
      SearchAllIntent: run<SearchAllIntent>(
        (_) => overlay == A9Overlay.searchAll
            ? closeConfigOverlay()
            : openOverlay(A9Overlay.searchAll),
      ),
      ShowShortcutsIntent: run<ShowShortcutsIntent>(
        (_) => openOverlay(A9Overlay.shortcuts),
      ),
      ShowTourIntent: run<ShowTourIntent>((_) => openOverlay(A9Overlay.tour)),
      ShowWhatsNewIntent: run<ShowWhatsNewIntent>((_) => openWhatsNew()),
      // A12 D20: the answer shows in Settings > General.
      CheckForUpdatesIntent: run<CheckForUpdatesIntent>((_) {
        openOverlay(A9Overlay.settings);
        unawaited(ref.read(updateCheckUiProvider.notifier).check());
      }),
      // Always enabled: the palette lists it only when there are problems
      // (D33), a bound key may ask any time.
      ShowConfigProblemsIntent: run<ShowConfigProblemsIntent>(
        (_) => openOverlay(A9Overlay.problems),
      ),
    };
  }

  /// D35: a `command` / `snippet` by name; with no live terminal, a toast.
  void _runCommand(String name) {
    final command = ref
        .read(shellxConfigProvider)
        .config
        .commands
        .where((c) => c.name == name)
        .firstOrNull;
    if (command == null) return;
    closePanel();
    final ran = runUserCommand(
      ref.read(terminalTabsProvider),
      command,
      sender: ref.read(pasteSenderProvider),
      tabs: () => ref.read(terminalTabsProvider),
    );
    if (ran == CommandRun.noTerminal) {
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(const NoTerminalForCommandNotice());
    } else {
      focusTerminal();
    }
  }

  /// Runs [intent] through this window's actions when it is enabled (the
  /// palette and key sequences, Tasks 9 and 11). False when there is no
  /// such action or it does not apply now.
  bool invokeIntent(Intent intent) {
    final action = actionsMap[intent.runtimeType];
    if (action == null || !action.isEnabled(intent)) return false;
    const ActionDispatcher().invokeAction(action, intent);
    return true;
  }

  /// A9 D11: probe the configured families once per load (it needs the
  /// engine's fonts, so it runs from the window, not the controller).
  /// Manual: a rebuild never re-runs it. The immediate call (the startup
  /// load ran before this page) writes after the frame (Riverpod 3: no
  /// provider writes while the tree builds; preflight D4).
  void listenToConfig() {
    ref.listenManual(
      shellxConfigProvider.select((s) => (s.generation, s.config)),
      (previous, next) {
        if (previous == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _probeFonts(next.$1, next.$2);
          });
        } else {
          _probeFonts(next.$1, next.$2);
        }
      },
      fireImmediately: true,
    );
  }

  /// `reportRuntimeProblems` changes neither the generation nor the
  /// configuration, so the listener above does not fire again; it also
  /// ignores a report for a generation that a newer load replaced.
  void _probeFonts(int generation, ShellxConfig config) {
    if (generation == 0) return;
    ref
        .read(shellxConfigProvider.notifier)
        .reportRuntimeProblems(
          generation,
          kFontProblemCodes,
          fontProblems(config, ref.read(fontProbeProvider)),
        );
    forgetFixedRuntimeProblems();
  }
}
