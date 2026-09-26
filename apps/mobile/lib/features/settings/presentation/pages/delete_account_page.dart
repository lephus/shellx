import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/presentation/widgets/password_text_field.dart';
import 'package:shellx_mobile/features/settings/presentation/controllers/delete_account_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §5.2 / §9.2 #5 and the design's "Xóa tài khoản": what is lost, password re-entry, the
/// error under the field, a red button and "Hủy".
@RoutePage()
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final DeleteAccountController _controller = getIt<DeleteAccountController>();
  final TextEditingController _password = TextEditingController();
  final Signal<bool> _hasPassword = signal(false);

  @override
  void dispose() {
    _password.dispose();
    _hasPassword.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final colors = context.colors;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
          Expanded(
            child: Text(text, style: context.typo.paragraph.copyWith(color: colors.secondaryText)),
          ),
        ],
      ),
    );
    // A logout landing in this deletion's DELETE window would join it as a plain sign-out and
    // keep the device key and pins (spec §5.2 vs §5.2 amended): while busy, back navigation and
    // "Hủy" are both blocked, so the user cannot reach Settings' "Đăng xuất" until it settles.
    return Watch((context) {
      final busy = _controller.busy.value;
      return PopScope(
        canPop: !busy,
        child: Scaffold(
          backgroundColor: colors.background,
          appBar: AppBar(title: Text(strings.deleteAccountTitle)),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                          decoration: BoxDecoration(color: colors.errorSoft, borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strings.deleteAccountWarningTitle,
                                style: context.typo.subHeader15.bold.copyWith(color: colors.error),
                              ),
                              6.sizedHeight,
                              bullet(strings.deleteAccountLoseAccount(_controller.email)),
                              bullet(strings.deleteAccountLoseComputers),
                              bullet(strings.deleteAccountLoseSessions),
                            ],
                          ),
                        ),
                        18.sizedHeight,
                        Watch(
                          (context) => PasswordTextField(
                            label: strings.deleteAccountPasswordLabel,
                            hintText: strings.passwordHint,
                            controller: _password,
                            errorText: _controller.error.value,
                            autofillHints: const [AutofillHints.password],
                            onChanged: (value) {
                              _hasPassword.value = value.isNotEmpty;
                              _controller.clearError();
                            },
                          ),
                        ),
                        const Spacer(),
                        24.sizedHeight,
                        Watch((context) {
                          final state = busy
                              ? ButtonState.loading
                              : _hasPassword.value
                              ? ButtonState.available
                              : ButtonState.disable;
                          return AppButton(
                            title: strings.deleteAccountButton,
                            width: double.infinity,
                            backgroundColor: colors.error,
                            textColor: colors.white,
                            state: state,
                            onTap: () => _controller.delete(_password.text),
                          );
                        }),
                        4.sizedHeight,
                        AppButton(
                          title: strings.actionCancel,
                          width: double.infinity,
                          backgroundColor: Colors.transparent,
                          textColor: colors.primary,
                          state: busy ? ButtonState.disable : ButtonState.available,
                          onTap: () => context.router.maybePop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
