import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config_controller.dart';
import '../../config/config_opener.dart';
import '../../config/font_probe.dart';
import '../../config/shellx_config.dart';
import '../../terminal/terminal_tabs.dart';
import '../../terminal/user_commands.dart';
import 'terminal_intents.dart';

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

  static bool _hardwareAltGr() =>
      defaultTargetPlatform == TargetPlatform.windows &&
      HardwareKeyboard.instance.logicalKeysPressed.contains(
        LogicalKeyboardKey.altRight,
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

  /// Closes whichever A9 overlay (palette, shortcut editor, problems
  /// panel) is open. `closePanel` calls it first, before its own early
  /// return, so every window shortcut dismisses an open overlay (Tasks
  /// 10-12 fill it in).
  void closeConfigOverlay() {}

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
      // Registered disabled: Tasks 10-12 turn them on. A disabled action
      // lets the key through, so a chord bound to one does nothing yet.
      CommandPaletteIntent: run<CommandPaletteIntent>(
        (_) {},
        enabled: (_) => false,
      ),
      ShowShortcutsIntent: run<ShowShortcutsIntent>(
        (_) {},
        enabled: (_) => false,
      ),
      ShowConfigProblemsIntent: run<ShowConfigProblemsIntent>(
        (_) {},
        enabled: (_) => false,
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
    final ran = runUserCommand(ref.read(terminalTabsProvider), command);
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
  }
}
