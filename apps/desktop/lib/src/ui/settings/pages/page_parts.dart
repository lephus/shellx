import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../config/settings_schema.dart';
import '../../../tray/tray_action.dart';
import '../../../tray/tray_actions.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart';

/// The row of [def] (an action row for the two switches that are buttons).
Widget settingWidget(
  SettingDef def, {
  String? pageCaption,
  VoidCallback? onJump,
  String? note,
  bool enabled = true,
  SettingPreviewHook? onPreview,
}) => def.id == 'cli-path'
    ? CliPathRow(key: Key('setting.${def.id}'), enabled: enabled)
    : SettingRow(
        key: ValueKey('row.${def.id}'),
        def: def,
        pageCaption: pageCaption,
        onJump: onJump,
        note: note,
        enabled: enabled,
        onPreview: onPreview,
      );

/// The page's rows of the catalogue by id (the catalogue is the one list).
SettingDef settingById(String id) => kSettings.firstWhere((d) => d.id == id);

/// A page: a scrolling column of [children] with the "Open configuration
/// file" link first (D9).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children, this.scroll = true});
  final List<Widget> children;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = SettingsScope.of(context);
    final link = Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: TextButton(
          key: const Key('settings.open-file'),
          onPressed: scope.onOpenFile,
          child: Text(l10n.settingsOpenFile),
        ),
      ),
    );
    if (!scroll) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [link, ...children],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [link, ...children],
    );
  }
}

/// A group heading inside a page.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Text(
        text.toUpperCase(),
        style: ShellxText.caption.copyWith(
          color: ShellxDesktopColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// A label with one button at the right (the tray items that are actions).
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.label,
    required this.button,
    required this.onPressed,
    this.caption,
  });
  final String label;
  final String button;
  final VoidCallback? onPressed;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    // The label is the button's own (an action with no separate caption).
    if (label == button && caption == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: onPressed, child: Text(button)),
        ),
      );
    }
    return _labelled();
  }

  Widget _labelled() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ShellxText.body.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: onPressed, child: Text(button)),
      ],
    ),
  );
}

/// "Install shellx for every terminal" / "Remove it": the tray item, same
/// action, label by state.
class CliPathRow extends ConsumerWidget {
  const CliPathRow({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final installed = ref.watch(
      trayLocalStateProvider.select((s) => s.cliPathInstalled),
    );
    final label = installed ? l10n.trayCliRemovePath : l10n.trayCliInstallPath;
    return ActionRow(
      label: label,
      button: label,
      onPressed: enabled
          ? () => unawaited(
              ref.read(trayActionsProvider).handle(const ToggleCliPath()),
            )
          : null,
    );
  }
}
