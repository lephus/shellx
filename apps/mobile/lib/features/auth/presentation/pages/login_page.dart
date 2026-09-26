import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/login_controller.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §9.2 #1 and the design's "Đăng nhập": two fields, the forgot-password hint (passwords are
/// changed on a signed-in computer, spec §5.2), "Tạo tài khoản"; after a 4002 the banner
/// "Phiên đăng nhập đã hết hiệu lực. Hãy đăng nhập lại." with the email prefilled.
@RoutePage()
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = getIt<LoginController>();
  final _validator = AuthFormValidator();
  late final _emailController = TextEditingController(text: _controller.lastEmail);
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_controller.busy.peek()) return;
    if (_formKey.currentState?.validate() ?? false) {
      await _controller.submit(_emailController.text, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    final notice = switch (_controller.signOutReason) {
      SignOutReason.revoked => (strings.signedOutExpired, Icons.lock_outline),
      SignOutReason.accountDeleted => (strings.signedOutAccountDeleted, Icons.info_outline),
      SignOutReason.loggedOut || null => null,
    };
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(alignment: Alignment.centerLeft, child: ShellxLogo()),
                        22.sizedHeight,
                        Text(strings.loginTitle, style: context.typo.heading28.heavy),
                        if (notice == null) ...[
                          6.sizedHeight,
                          Text(
                            strings.loginSubtitle,
                            style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
                          ),
                        ] else ...[
                          16.sizedHeight,
                          NoticeBanner(text: notice.$1, tone: NoticeTone.info, leading: Icon(notice.$2)),
                        ],
                        22.sizedHeight,
                        AppTextField(
                          label: strings.emailLabel,
                          hintText: strings.emailHint,
                          controller: _emailController,
                          validator: _validator.validateEmail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                        ),
                        22.sizedHeight,
                        PasswordTextField(
                          label: strings.passwordLabel,
                          hintText: strings.passwordHint,
                          controller: _passwordController,
                          validator: _validator.validatePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _handleSubmit(),
                        ),
                        22.sizedHeight,
                        Watch((context) {
                          return AppButton(
                            title: strings.loginButton,
                            state: _controller.busy.value ? ButtonState.loading : ButtonState.available,
                            onTap: _handleSubmit,
                          );
                        }),
                        16.sizedHeight,
                        Text(
                          strings.forgotPasswordHint,
                          textAlign: TextAlign.center,
                          style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                        ),
                        const Spacer(),
                        24.sizedHeight,
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(strings.noAccountPrompt, style: context.typo.subHeader15),
                            TextButton(
                              onPressed: () => context.router.push(const RegisterRoute()),
                              child: Text(
                                strings.createAccountLink,
                                style: context.typo.subHeader15.bold.copyWith(color: colors.primary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
