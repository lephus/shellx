import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/ssh_actions.dart';
import '../window_router.dart';
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

enum _NewAction { tab, ssh, tmux }

/// The sidebar header's `+` (A8 UI §5.2): a click is "New tab" (A1: in an
/// SSH workspace, an SSH tab); right click, Shift+F10 and the Menu key open
/// the three ways in. Kept out of `session_sidebar.dart`.
class SidebarNewButton extends ConsumerWidget {
  const SidebarNewButton({
    super.key,
    required this.semanticLabel,
    required this.tooltip,
    required this.busy,
  });

  final String semanticLabel;
  final InlineSpan? tooltip;
  final bool busy;

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showShellxMenu<_NewAction>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.new.tab'),
          value: _NewAction.tab,
          label: l10n.terminalNewTab,
          shortcut: newTabShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.new.ssh'),
          value: _NewAction.ssh,
          label: l10n.sshConnectMenu,
          shortcut: sshConnectShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.new.tmux'),
          value: _NewAction.tmux,
          label: l10n.tmuxAttachMenu,
          shortcut: tmuxAttachShortcutLabel(),
        ),
      ],
    );
    final router = ref.read(windowRouterProvider.notifier);
    switch (choice) {
      case _NewAction.tab:
        unawaited(ref.read(sshActionsProvider).newTab());
      case _NewAction.ssh:
        router.open(const SshConnectRoute());
      case _NewAction.tmux:
        router.open(const SshConnectRoute(SshDialogTab.tmux));
      case null:
        break;
    }
  }

  /// Below the button's left edge (where Shift+F10 opens menus).
  Offset _below(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset(0, box.size.height));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final shiftF10 =
            key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed;
        if (!shiftF10 && key != LogicalKeyboardKey.contextMenu) {
          return KeyEventResult.ignored;
        }
        unawaited(_menu(context, ref, _below(context)));
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapDown: (d) =>
            unawaited(_menu(context, ref, d.globalPosition)),
        child: ShellxIconButton(
          key: const Key('sidebar.newTab'),
          icon: Icons.add,
          semanticLabel: semanticLabel,
          tooltip: tooltip,
          busy: busy,
          onPressed: () => ref.read(sshActionsProvider).newTab(),
        ),
      ),
    );
  }
}
