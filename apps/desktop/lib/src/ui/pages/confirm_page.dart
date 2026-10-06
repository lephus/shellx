import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../terminal/shortcut_labels.dart';
import '../dialogs/dialog_layout.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// A confirm dialog body (UI §4): title → 8 → body → 24 → actions; as
/// tall as its text, and a long body scrolls under pinned actions. macOS `[Cancel] [Action]`, Windows `[Action] [Cancel]`, so the
/// Tab order matches what is seen. A destructive confirm starts on Cancel;
/// any other starts on its action (Enter confirms).
class ConfirmPage extends StatelessWidget {
  const ConfirmPage({super.key, required this.request});

  final ConfirmRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cancel = OutlinedButton(
      key: const Key('confirm.cancel'),
      autofocus: request.destructive,
      onPressed: () => request.complete(false),
      child: Text(l10n.actionCancel),
    );
    final ok = FilledButton(
      key: const Key('confirm.ok'),
      autofocus: !request.destructive,
      style: request.destructive ? destructiveButtonStyle() : null,
      onPressed: () => request.complete(true),
      child: Text(request.confirmLabel),
    );
    const gap = SizedBox(width: ShellxSpace.s8);
    return DialogBody(
      title: request.title,
      content: [
        SelectableText(request.body, style: theme.textTheme.bodyMedium),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: isMacDesktop ? [cancel, gap, ok] : [ok, gap, cancel],
      ),
    );
  }
}
