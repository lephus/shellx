import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../terminal/shortcut_labels.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// A confirm dialog body (UI §4): title → 8 → body (scrolls) → 24 →
/// actions. macOS `[Cancel] [Action]`, Windows `[Action] [Cancel]`, so the
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
    return Padding(
      padding: const EdgeInsets.all(ShellxSpace.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Windows: clear of the close button (28 at inset 12).
            padding: EdgeInsets.only(
              right: isMacDesktop
                  ? 0
                  : ShellxSizes.iconHit + ShellxSpace.s12 - ShellxSpace.s24,
            ),
            child: Text(request.title, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: ShellxSpace.s8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                request.body,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: ShellxSpace.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: isMacDesktop ? [cancel, gap, ok] : [ok, gap, cancel],
          ),
        ],
      ),
    );
  }
}
