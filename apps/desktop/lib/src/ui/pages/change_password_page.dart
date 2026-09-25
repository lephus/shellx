import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../form_rules.dart';
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
      if (mounted) setState(() => _done = true);
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
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.changePasswordTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.changePasswordNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          if (_done) ...[
            Text(l10n.changePasswordDone, key: const Key('password.done')),
            const Spacer(),
            FilledButton(
              key: const Key('password.close'),
              onPressed: router.close,
              child: Text(l10n.actionClose),
            ),
          ] else ...[
            TextField(
              key: const Key('password.new'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.changePasswordNew),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('password.confirm'),
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.changePasswordConfirm,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                key: const Key('password.error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : router.close,
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('password.submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(l10n.changePasswordSubmit),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
