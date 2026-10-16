import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_embed.dart';
import '../../tools/tool_entry.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart';
import '../theme/shellx_desktop_theme.dart';
import 'tool_actions.dart';

/// D21: the workspaces whose "Tools" group is folded (this run only).
final toolGroupsFoldedProvider =
    NotifierProvider<ToolGroupsFolded, Set<String>>(ToolGroupsFolded.new);

class ToolGroupsFolded extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String ws) =>
      state = state.contains(ws) ? ({...state}..remove(ws)) : {...state, ws};
}

enum _ToolMenu { open, browser, edit, phone, delete }

/// D21: under a workspace with tools, the foldable "Tools" group: one row
/// per tool — 🧩, the name, `host:port` (with "· on phone too"), ↗ when
/// tools open in the browser (D20). The row of the tool on show in an open
/// dock is lit. Rows are buttons (D18); the keyboard reaches tools through
/// the palette and ⌘⇧B (ruling R11).
class ToolSidebarGroup extends ConsumerWidget {
  const ToolSidebarGroup({
    super.key,
    required this.workspaceId,
    required this.tools,
  });

  final String workspaceId;
  final List<ToolEntry> tools;

  static const double _header = 24;
  static const double _row = 36;

  static double _headerHeight(TextScaler scaler) =>
      math.max(_header, scaler.scale(13) + 8);

  /// A row holds two text lines — the name (`small`, 16 px) over the
  /// `host:port` (`caption`, 14 px) — and 3 px above and below: 36 px at
  /// 1x, and tall enough for both lines at any text size (D18).
  static double _rowHeight(TextScaler scaler) =>
      math.max(_row, scaler.scale(30) + 6);

  /// The group's height, which the sidebar's lazy list adds up.
  static double heightFor(
    TextScaler scaler, {
    required int count,
    required bool folded,
  }) => _headerHeight(scaler) + (folded ? 0 : _rowHeight(scaler) * count);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final folded = ref.watch(
      toolGroupsFoldedProvider.select((s) => s.contains(workspaceId)),
    );
    final dock = ref.watch(toolDockProvider.select((d) => d.of(workspaceId)));
    final embedded = ref.watch(toolsEmbeddedProvider);
    final header = _headerHeight(scaler);
    final row = _rowHeight(scaler);
    return SizedBox(
      height: heightFor(scaler, count: tools.length, folded: folded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: header,
            child: Semantics(
              button: true,
              expanded: !folded,
              label: l10n.toolsGroup,
              child: InkWell(
                key: Key('sidebar.tools.$workspaceId'),
                onTap: () => ref
                    .read(toolGroupsFoldedProvider.notifier)
                    .toggle(workspaceId),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        folded ? Icons.chevron_right : Icons.expand_more,
                        size: 14,
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: ShellxSpace.s4),
                    ExcludeSemantics(
                      child: Text(
                        l10n.toolsGroup,
                        style: ShellxText.caption.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!folded)
            for (final t in tools)
              SizedBox(
                height: row,
                child: _ToolRow(
                  tool: t,
                  lit: dock.open && dock.active == t.id,
                  embedded: embedded,
                ),
              ),
        ],
      ),
    );
  }
}

class _ToolRow extends ConsumerWidget {
  const _ToolRow({
    required this.tool,
    required this.lit,
    required this.embedded,
  });

  final ToolEntry tool;
  final bool lit;
  final bool embedded;

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final actions = ToolActions(ref);
    final choice = await showShellxMenu<_ToolMenu>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('tool.row.menu.open'),
          value: _ToolMenu.open,
          label: l10n.toolMenuOpen,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.browser'),
          value: _ToolMenu.browser,
          label: l10n.toolOpenInBrowser,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.edit'),
          value: _ToolMenu.edit,
          label: l10n.toolMenuEdit,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.phone'),
          value: _ToolMenu.phone,
          label: l10n.toolDialogPhone,
          checked: tool.phoneOn,
          enabled: tool.phoneAllowed,
          tooltip: tool.phoneAllowed ? null : l10n.toolPhoneOnlyLocal,
        ),
        ShellxMenuEntry(
          key: const Key('tool.row.menu.delete'),
          value: _ToolMenu.delete,
          label: l10n.toolMenuDelete,
          dividerBefore: true,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case _ToolMenu.open:
        Actions.maybeInvoke(context, OpenToolIntent(tool.id));
      case _ToolMenu.browser:
        unawaited(actions.openInBrowser(tool));
      case _ToolMenu.edit:
        unawaited(actions.edit(context, tool));
      case _ToolMenu.phone:
        actions.togglePhone(tool);
      case _ToolMenu.delete:
        unawaited(actions.delete(tool));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sub = tool.phoneOn
        ? '${tool.hostPort} ${l10n.toolAlsoPhone}'
        : tool.hostPort;
    return Semantics(
      button: true,
      selected: lit,
      label: '${tool.name}, $sub',
      child: GestureDetector(
        onSecondaryTapUp: (d) =>
            unawaited(_menu(context, ref, d.globalPosition)),
        child: InkWell(
          key: Key('sidebar.tool.${tool.id}'),
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          onTap: () => Actions.maybeInvoke(context, OpenToolIntent(tool.id)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
            decoration: BoxDecoration(
              color: lit ? ShellxDesktopColors.rowSelected : null,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const Icon(
                    Icons.extension_outlined,
                    size: 14,
                    color: ShellxDesktopColors.accent,
                  ),
                  const SizedBox(width: ShellxSpace.s6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tool.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!embedded)
                    const Icon(
                      Icons.open_in_new,
                      key: Key('sidebar.tool.browserMark'),
                      size: 12,
                      color: ShellxDesktopColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
