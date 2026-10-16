import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../dialogs/dialog_layout.dart';
import '../form_rules.dart';
import '../theme/shellx_desktop_theme.dart';

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
    } on Object catch (error) {
      // E.g. the keychain refused the device key or the token: never an
      // unhandled error, never its message (it may hold secrets).
      debugPrint('ShellX: sign-in failed: ${error.runtimeType}');
      if (mounted) setState(() => _error = l10n.errorUnexpected('internal'));
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
    const fieldGap = SizedBox(height: ShellxSizes.fieldGap);
    return AutofillGroup(
      child: DialogBody(
        title: _register ? l10n.authRegisterTitle : l10n.authSignInTitle,
        content: [
          if (notice) ...[
            Text(
              l10n.authSignedOutNotice,
              key: const Key('login.notice'),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: ShellxDesktopColors.errDialog,
              ),
            ),
          ],
          const SizedBox(height: ShellxSpace.s8),
          LabeledField(
            label: l10n.authEmailLabel,
            field: TextField(
              key: const Key('login.email'),
              autofocus: true, // UI §3.7: forms start on the first field.
              controller: _email,
              enabled: !_busy,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          fieldGap,
          LabeledField(
            label: l10n.authPasswordLabel,
            field: TextField(
              key: const Key('login.password'),
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _register ? null : _submit(),
            ),
          ),
          if (_register) ...[
            fieldGap,
            LabeledField(
              label: l10n.authConfirmPasswordLabel,
              field: TextField(
                key: const Key('login.confirm'),
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
          if (_error != null)
            DialogError(_error!, key: const Key('login.error')),
          const SizedBox(height: ShellxSpace.s24),
          FilledButton(
            key: const Key('login.submit'),
            onPressed: _busy ? null : _submit,
            // UI §3.3 loading: the label stays, a spinner leads it.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy) ...[
                  const SizedBox.square(
                    dimension: ShellxSizes.buttonSpinner,
                    child: CircularProgressIndicator(
                      strokeWidth: ShellxSizes.spinnerStroke,
                    ),
                  ),
                  const SizedBox(width: ShellxSpace.s8),
                ],
                Text(
                  _register ? l10n.authRegisterButton : l10n.authSignInButton,
                ),
              ],
            ),
          ),
          const SizedBox(height: ShellxSpace.s8),
          Center(
            child: TextButton(
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
          ),
          const SizedBox(height: ShellxSpace.s16),
          Text(l10n.authForgotPasswordHint, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
