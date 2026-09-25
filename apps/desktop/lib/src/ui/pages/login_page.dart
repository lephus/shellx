import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../form_rules.dart';

/// Login / register window (spec §8.2 step 1).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(agentControllerProvider).email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate(AppLocalizations l10n) {
    if (!looksLikeEmail(_email.text)) return l10n.errorEmailInvalid;
    if (!validPasswordLength(_password.text)) return l10n.errorPasswordLength;
    if (_register && _password.text != _confirm.text) {
      return l10n.errorPasswordMismatch;
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final invalid = _validate(l10n);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(agentControllerProvider.notifier)
          .signIn(
            email: _email.text,
            password: _password.text,
            register: _register,
          );
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
    final notice = ref.watch(
      agentControllerProvider.select((s) => s.signedOutNotice),
    );
    return Padding(
      padding: const EdgeInsets.all(32),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _register ? l10n.authRegisterTitle : l10n.authSignInTitle,
              style: theme.textTheme.headlineSmall,
            ),
            if (notice) ...[
              const SizedBox(height: 12),
              Text(
                l10n.authSignedOutNotice,
                key: const Key('login.notice'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              key: const Key('login.email'),
              controller: _email,
              enabled: !_busy,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.authEmailLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login.password'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.authPasswordLabel),
              onSubmitted: (_) => _register ? null : _submit(),
            ),
            if (_register) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('login.confirm'),
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.authConfirmPasswordLabel,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 16),
            if (_error != null)
              Text(
                _error!,
                key: const Key('login.error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('login.submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _register
                          ? l10n.authRegisterButton
                          : l10n.authSignInButton,
                    ),
            ),
            TextButton(
              key: const Key('login.toggle'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
              child: Text(
                _register ? l10n.authSwitchToSignIn : l10n.authSwitchToRegister,
              ),
            ),
            const Spacer(),
            Text(l10n.authForgotPasswordHint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
