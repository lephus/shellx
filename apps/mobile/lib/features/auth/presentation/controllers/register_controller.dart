import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/auth/domain/auth_form_validator.dart';
import 'package:shellx_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Design "Tạo tài khoản": checked while typing (email format, 8–128 characters); the relay's
/// answers about the email (`invalid_email`, `disposable_email`, `email_taken`) or the password
/// (`weak_password`) stay under that field until it changes; the button is dimmed until valid.
@injectable
class RegisterController extends AuthController {
  RegisterController(super.sessionHolder);

  final AuthFormValidator _validator = AuthFormValidator();
  final Signal<String> _email = signal('');
  final Signal<String> _password = signal('');
  final Signal<({String email, String message})?> _emailRejected = signal(null);
  final Signal<({String password, String message})?> _passwordRejected = signal(null);

  late final Computed<String?> _emailError = computed(() {
    final email = _email.value.trim();
    final rejected = _emailRejected.value;
    if (rejected != null && rejected.email == email) return rejected.message;
    return email.isEmpty ? null : _validator.validateEmail(email);
  });

  late final Computed<String?> _passwordError = computed(() {
    final rejected = _passwordRejected.value;
    return rejected != null && rejected.password == _password.value ? rejected.message : null;
  });

  late final Computed<bool> _canSubmit = computed(
    () =>
        _email.value.trim().isNotEmpty &&
        _emailError.value == null &&
        _passwordError.value == null &&
        _validator.validateNewPassword(_password.value) == null &&
        !busy.value,
  );

  ReadonlySignal<String?> get emailError => _emailError;
  ReadonlySignal<String?> get passwordError => _passwordError;
  ReadonlySignal<String> get password => _password;

  /// Both fields are valid and nothing is running: the button is enabled, and only then does
  /// [submit] (also reached from the keyboard's "done") send anything.
  ReadonlySignal<bool> get canSubmit => _canSubmit;

  void setEmail(String value) {
    if (!isDisposed) _email.value = value;
  }

  void setPassword(String value) {
    if (!isDisposed) _password.value = value;
  }

  /// "Từ 8 đến 128 ký tự. Còn thiếu 3 ký tự."
  String passwordHelp(S strings) {
    final length = _password.value.length;
    if (length > 0 && length < AuthFormValidator.minPasswordLength) {
      return '${strings.passwordRule} ${strings.passwordMissing(AuthFormValidator.minPasswordLength - length)}';
    }
    if (length > AuthFormValidator.maxPasswordLength) {
      return '${strings.passwordRule} ${strings.passwordTooLong(length - AuthFormValidator.maxPasswordLength)}';
    }
    return strings.passwordRule;
  }

  @override
  Future<void> submit(String email, String password) async {
    if (isDisposed || !_canSubmit.peek()) return;
    await run(() async {
      try {
        await sessionHolder.register(email, password);
      } on ApiException catch (error) {
        final message = ErrorText(S.current).api(error);
        switch (error.code) {
          case 'invalid_email' || 'disposable_email' || 'email_taken' when error.status != 429:
            if (!isDisposed) _emailRejected.value = (email: email.trim(), message: message);
          case 'weak_password' when error.status != 429:
            if (!isDisposed) _passwordRejected.value = (password: password, message: message);
          default:
            rethrow; // HTTP 429, network: a toast.
        }
      }
    });
  }

  @override
  void dispose() {
    _canSubmit.dispose();
    _emailError.dispose();
    _passwordError.dispose();
    _email.dispose();
    _password.dispose();
    _emailRejected.dispose();
    _passwordRejected.dispose();
    super.dispose();
  }
}
