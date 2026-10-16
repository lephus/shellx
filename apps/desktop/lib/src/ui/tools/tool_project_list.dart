import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../tools/tool_pages.dart';
import '../../tools/tool_registry.dart';
import '../terminal/terminal_intents.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'tool_actions.dart';

/// D22: a project card's tools — name, URL, the phone flag, open, edit,
/// delete — and "Add tool".
class ToolProjectList extends ConsumerWidget {
  const ToolProjectList({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actions = ToolActions(ref);
    final tools = [
      for (final t in ref.watch(toolRegistryProvider))
        if (t.ws == workspaceId) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.toolsGroup,
          style: ShellxText.caption.copyWith(
            color: ShellxDesktopColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final t in tools)
          Row(
            key: Key('settings.tool.${t.id}'),
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      t.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: t.phoneAllowed
                    ? l10n.toolDialogPhone
                    : l10n.toolPhoneOnlyLocal,
                child: Switch(
                  key: Key('settings.tool.${t.id}.phone'),
                  value: t.phoneOn,
                  onChanged: t.phoneAllowed
                      ? (_) => actions.togglePhone(t)
                      : null,
                ),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.open'),
                tooltip: l10n.toolMenuOpen,
                icon: const Icon(Icons.extension_outlined, size: 18),
                onPressed: () =>
                    Actions.maybeInvoke(context, OpenToolIntent(t.id)),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.edit'),
                tooltip: l10n.toolMenuEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => unawaited(actions.edit(context, t)),
              ),
              IconButton(
                key: Key('settings.tool.${t.id}.delete'),
                tooltip: l10n.toolMenuDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => unawaited(actions.delete(t)),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('settings.project.$workspaceId.addTool'),
            onPressed: () => unawaited(actions.add(context, workspaceId)),
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.toolAdd),
          ),
        ),
      ],
    );
  }
}

/// D22: "Clear tool data…": asks, then signs every tool out (one store,
/// D8).
Future<void> confirmClearToolData(WidgetRef ref, AppLocalizations l10n) async {
  final yes = await ref
      .read(windowRouterProvider.notifier)
      .confirm(
        ConfirmRequest(
          title: l10n.toolClearDataConfirm,
          body: l10n.toolClearDataNote,
          confirmLabel: l10n.toolClearDataAction,
        ),
      );
  if (!yes) return;
  try {
    await ref.read(toolDataStoreProvider).clearAll();
  } on Object catch (error) {
    debugPrint('tool data not cleared (${error.runtimeType})');
  }
}
