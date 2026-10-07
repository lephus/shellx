import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/pane_input.dart';
import '../theme/shellx_desktop_theme.dart';
import 'copy_mode_controller.dart';
import '../window_focus.dart';

/// A10 D16: files dropped on a pane become their paths on its command line
/// (shell-escaped, no Enter). While files are over the pane it is outlined
/// with a hint; the hint goes when they leave, are dropped, the window
/// loses focus, or the pane stops accepting (hidden, a dialog open, ended).
class PaneDropTarget extends ConsumerStatefulWidget {
  const PaneDropTarget({
    super.key,
    required this.paneId,
    required this.enabled,
    required this.remote,
    required this.child,
  });

  final int paneId;

  /// False for a pane that is hidden (another tab, under a zoom), ended, or
  /// behind a dialog: `DropTarget` keeps receiving events while invisible.
  final bool enabled;

  /// A pane on a server: it shows the refusal while files hover (D17).
  final bool remote;
  final Widget child;

  @override
  ConsumerState<PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends ConsumerState<PaneDropTarget> {
  bool _over = false;

  void _set(bool over) {
    if (_over != over && mounted) setState(() => _over = over);
  }

  @override
  void didUpdateWidget(PaneDropTarget old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _over = false;
  }

  void _done(DropDoneDetails details) {
    _set(false);
    final paths = [
      for (final f in details.files)
        if (f.path.isNotEmpty) f.path,
    ];
    if (paths.isEmpty) return;
    // A11 D13: a drop is for the program, not for copy mode.
    ref.read(copyModeProvider.notifier).exit(widget.paneId);
    unawaited(
      ref
          .read(paneInputProvider)
          .insertPaths(widget.paneId, paths, focus: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The window lost the keyboard (Cmd-Tab mid-drag): no stuck hint.
    ref.listen<bool>(windowFocusProvider, (_, focused) {
      if (!focused) _set(false);
    });
    final l10n = AppLocalizations.of(context);
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => _set(true),
      onDragExited: (_) => _set(false),
      onDragDone: _done,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_over && widget.enabled)
            Positioned.fill(
              child: IgnorePointer(
                child: Semantics(
                  liveRegion: true,
                  label: widget.remote ? l10n.dropHintSsh : l10n.dropHint,
                  child: DecoratedBox(
                    key: const Key('drop.hint'),
                    decoration: BoxDecoration(
                      color: ShellxDesktopColors.accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: widget.remote
                            ? ShellxDesktopColors.warn
                            : ShellxDesktopColors.accent,
                        width: 2,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: ShellxSpace.s12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: ShellxSpace.s12,
                          vertical: ShellxSpace.s4,
                        ),
                        decoration: BoxDecoration(
                          color: ShellxDesktopColors.surface,
                          borderRadius: BorderRadius.circular(ShellxRadius.r8),
                          border: Border.all(color: ShellxDesktopColors.border),
                        ),
                        child: Text(
                          widget.remote ? l10n.dropHintSsh : l10n.dropHint,
                          style: ShellxText.body.copyWith(
                            color: ShellxDesktopColors.textTitle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
