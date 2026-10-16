import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../form_rules.dart';
import '../dialogs/dialog_informational.dart';
import '../dialogs/dialog_layout.dart';
import '../terminal/shortcut_labels.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// "Đổi mật khẩu…" (spec §8.3): new password twice, no old password (§5.2).
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!validPasswordLength(_password.text)) {
      setState(() => _error = l10n.errorPasswordLength);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = l10n.errorPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .changePassword(_password.text);
      if (mounted) {
        setState(() => _done = true);
        // Only a message and Close are left: a scrim click may close it.
        const DialogInformationalNotification().dispatch(context);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(error, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final router = ref.read(windowRouterProvider.notifier);
    const gap = SizedBox(width: ShellxSpace.s8);
    final submit = FilledButton(
      key: const Key('password.submit'),
      onPressed: _busy ? null : _submit,
      child: Text(l10n.changePasswordSubmit),
    );
    return DialogBody(
      title: l10n.changePasswordTitle,
      content: [
        Text(l10n.changePasswordNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: ShellxSpace.s16),
        if (_done)
          Text(l10n.changePasswordDone, key: const Key('password.done'))
        else ...[
          LabeledField(
            label: l10n.changePasswordNew,
            field: TextField(
              key: const Key('password.new'),
              autofocus: true, // UI §3.7: forms start on the first field.
              controller: _password,
              enabled: !_busy,
              obscureText: true,
            ),
          ),
          const SizedBox(height: ShellxSizes.fieldGap),
          LabeledField(
            label: l10n.changePasswordConfirm,
            field: TextField(
              key: const Key('password.confirm'),
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error != null)
            DialogError(_error!, key: const Key('password.error')),
        ],
      ],
      footer: _done
          ? Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('password.close'),
                autofocus: true,
                onPressed: router.close,
                child: Text(l10n.actionClose),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              // UI §4: macOS [Cancel] [Primary], Windows [Primary] [Cancel].
              children: [
                if (!isMacDesktop) ...[submit, gap],
                OutlinedButton(
                  key: const Key('password.cancel'),
                  onPressed: _busy ? null : router.close,
                  child: Text(l10n.actionCancel),
                ),
                if (isMacDesktop) ...[gap, submit],
              ],
            ),
    );
  }
}
