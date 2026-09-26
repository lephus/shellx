import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/register_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #1 and the design's "Tạo tài khoản": errors under the field that is wrong, the
/// 8–128 hint with how many characters are missing, the button dimmed until valid, the terms line.
@RoutePage()
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _controller = getIt<RegisterController>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() => _controller.submit(_emailController.text, _passwordController.text);

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final fine = context.typo.metadata12.copyWith(color: colors.disable, height: 1.5);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.registerTitle, style: context.typo.heading28.heavy),
                6.sizedHeight,
                Text(strings.registerSubtitle, style: context.typo.subHeader15.copyWith(color: colors.secondaryText)),
                20.sizedHeight,
                Watch(
                  (context) => AppTextField(
                    label: strings.emailLabel,
                    hintText: strings.emailHint,
                    controller: _emailController,
                    errorText: _controller.emailError.value,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onChanged: _controller.setEmail,
                  ),
                ),
                20.sizedHeight,
                Watch(
                  (context) => PasswordTextField(
                    label: strings.passwordLabel,
                    hintText: strings.passwordHint,
                    controller: _passwordController,
                    errorText: _controller.passwordError.value,
                    helperText: _controller.passwordHelp(strings),
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: _controller.setPassword,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ),
                20.sizedHeight,
                Watch((context) {
                  final state = _controller.busy.value
                      ? ButtonState.loading
                      : _controller.canSubmit.value
                      ? ButtonState.available
                      : ButtonState.disable;
                  return AppButton(title: strings.registerButton, state: state, onTap: _submit);
                }),
                14.sizedHeight,
                HighlightedText(
                  strings.termsNotice(strings.termsLink, strings.privacyLink),
                  parts: {
                    strings.termsLink: () => getIt<ExternalLinks>().openOrToast(AppConfig.termsPage),
                    strings.privacyLink: () => getIt<ExternalLinks>().openOrToast(AppConfig.privacyPage),
                  },
                  textAlign: TextAlign.center,
                  style: fine,
                  partStyle: fine.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
