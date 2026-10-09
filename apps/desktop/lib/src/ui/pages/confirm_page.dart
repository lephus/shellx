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
class ConfirmPage extends StatefulWidget {
  const ConfirmPage({super.key, required this.request});

  final ConfirmRequest request;

  @override
  State<ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends State<ConfirmPage> {
  /// The confirm's own work is running (A5b): spinner, buttons locked.
  bool _busy = false;

  ConfirmRequest get _request => widget.request;

  Future<void> _confirm() async {
    final work = _request.onConfirm;
    if (work == null) {
      _request.complete(true);
      return;
    }
    setState(() => _busy = true);
    var done = false;
    try {
      done = await work();
    } on Object {
      done = false;
    }
    if (done) {
      _request.complete(true);
    } else if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final request = _request;
    final secondary = request.secondaryLabel;
    final cancel = OutlinedButton(
      key: const Key('confirm.cancel'),
      autofocus: request.destructive,
      onPressed: _busy
          ? null
          : secondary != null
          ? request.completeSecondary
          : () => request.complete(false),
      child: Text(secondary ?? request.cancelLabel ?? l10n.actionCancel),
    );
    final ok = FilledButton(
      key: const Key('confirm.ok'),
      autofocus: !request.destructive,
      style: request.destructive ? destructiveButtonStyle() : null,
      onPressed: _busy ? null : _confirm,
      child: _busy
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(request.confirmLabel),
    );
    const gap = SizedBox(width: ShellxSpace.s8);
    return DialogBody(
      title: request.title,
      content: [
        SelectableText(request.body, style: theme.textTheme.bodyMedium),
        if (request.code case final code?) ...[
          const SizedBox(height: ShellxSpace.s8),
          Container(
            key: const Key('confirm.code'),
            padding: const EdgeInsets.all(ShellxSpace.s8),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.rowSelected,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: SelectableText(
              code,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
        ],
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: isMacDesktop ? [cancel, gap, ok] : [ok, gap, cancel],
      ),
    );
  }
}
