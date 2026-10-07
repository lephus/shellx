part of 'ssh_connect_dialog.dart';

/// UI-A8 §4: SSH | tmux, the chosen one underlined (2 px accent).
class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});
  final SshDialogTab selected;
  final void Function(SshDialogTab) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tab(SshDialogTab t, String label) {
      final on = t == selected;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          key: Key('ssh.tab.${t.name}'),
          onTap: () => onSelect(t),
          child: Container(
            height: ShellxSizes.connectTabBar,
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on ? ShellxDesktopColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              label,
              style: (on ? ShellxText.bodyStrong : ShellxText.body).copyWith(
                color: on
                    ? ShellxDesktopColors.textTitle
                    : ShellxDesktopColors.textDialog2,
              ),
            ),
          ),
        ),
      );
    }

    // UI-A8 §6: ←/→ switch tabs while a tab has focus.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _SwitchIntent(
          SshDialogTab.ssh,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): _SwitchIntent(
          SshDialogTab.tmux,
        ),
      },
      child: Actions(
        actions: {
          _SwitchIntent: CallbackAction<_SwitchIntent>(
            onInvoke: (i) {
              onSelect(i.tab);
              return null;
            },
          ),
        },
        child: Row(
          children: [
            tab(SshDialogTab.ssh, l10n.sshDialogTabSsh),
            tab(SshDialogTab.tmux, l10n.sshDialogTabTmux),
          ],
        ),
      ),
    );
  }
}

class _SwitchIntent extends Intent {
  const _SwitchIntent(this.tab);
  final SshDialogTab tab;
}

/// UI-A8 §4.1: grouped suggestions, the cursor row highlighted.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.rows,
    required this.cursor,
    required this.query,
    required this.onPick,
  });
  final List<(String, bool)> rows; // (text, fromConfig)
  final int? cursor;
  final String query;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = <Widget>[];
    bool? group;
    for (final (i, (text, config)) in rows.indexed) {
      if (group != config) {
        group = config;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s8,
              ShellxSpace.s6,
              ShellxSpace.s8,
              ShellxSpace.s2,
            ),
            child: ExcludeSemantics(
              child: Text(
                (config ? l10n.sshSuggestionsConfig : l10n.sshSuggestionsRecent)
                    .toUpperCase(),
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }
      final on = i == cursor;
      children.add(
        Semantics(
          selected: on,
          button: true,
          child: InkWell(
            onTap: () => onPick(text),
            child: Container(
              height: ShellxSizes.suggestionRow,
              padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? ShellxDesktopColors.primarySoft : null,
                border: on
                    ? const Border(
                        left: BorderSide(
                          color: ShellxDesktopColors.accent,
                          width: 3,
                        ),
                      )
                    : null,
              ),
              child: Text.rich(
                _highlight(cleanServerText(text), query),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: ShellxSpace.s4),
      constraints: const BoxConstraints(
        maxHeight: ShellxSizes.suggestionRow * ShellxSizes.suggestionListMax,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surfaceInset,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: ListView(shrinkWrap: true, children: children),
    );
  }

  static TextSpan _highlight(String text, String query) {
    final q = query.trim().toLowerCase();
    final at = q.isEmpty ? -1 : text.toLowerCase().indexOf(q);
    final base = ShellxText.body.copyWith(
      color: ShellxDesktopColors.textPrimary,
    );
    if (at < 0) return TextSpan(text: text, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: text.substring(0, at)),
        TextSpan(
          text: text.substring(at, at + q.length),
          style: ShellxText.bodyStrong,
        ),
        TextSpan(text: text.substring(at + q.length)),
      ],
    );
  }
}

/// UI-A8 §4.2: name, windows, last activity, attached elsewhere. The name
/// comes from the server: shown without control characters.
class _TmuxRow extends StatelessWidget {
  const _TmuxRow({
    super.key,
    required this.info,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });
  final TmuxSessionInfo info;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activity = info.activity;
    final caption = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          height: ShellxSizes.tmuxRow,
          padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
          decoration: BoxDecoration(
            color: selected ? ShellxDesktopColors.primarySoft : null,
            border: selected
                ? const Border(
                    left: BorderSide(
                      color: ShellxDesktopColors.accent,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      cleanServerText(info.name),
                      style: ShellxText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(l10n.tmuxWindows(info.windows), style: caption),
                ],
              ),
              Row(
                children: [
                  if (activity != null)
                    Text(
                      l10n.tmuxLastActive(
                        relativeTime(activity, DateTime.now(), l10n),
                      ),
                      style: caption,
                    ),
                  if (info.attachedElsewhere) ...[
                    const SizedBox(width: ShellxSpace.s8),
                    Text(
                      l10n.tmuxAttachedElsewhere,
                      style: caption.copyWith(color: ShellxDesktopColors.warn),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A1 §4 button order: macOS `[Cancel] [Primary]`, Windows `[Primary]
/// [Cancel]`.
class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.primary,
    required this.primaryKey,
    required this.onPrimary,
    required this.onCancel,
  });
  final String primary;
  final Key primaryKey;
  final VoidCallback? onPrimary;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cancel = OutlinedButton(
      onPressed: onCancel,
      child: Text(l10n.actionCancel),
    );
    final main = FilledButton(
      key: primaryKey,
      onPressed: onPrimary,
      child: Text(primary),
    );
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: windows
          ? [main, const SizedBox(width: ShellxSpace.s8), cancel]
          : [cancel, const SizedBox(width: ShellxSpace.s8), main],
    );
  }
}
