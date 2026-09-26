import 'package:shellx_mobile/core/core.dart';

/// Shared by sign-in and registration. Success is routed by `SessionEnforcer`; failures show the
/// spec §12 texts ("Email hoặc mật khẩu không đúng.", "Thử lại sau ít phút.", …).
abstract class AuthController extends Controller {
  AuthController(this.sessionHolder);

  final SessionHolder sessionHolder;
  final Signal<bool> _busy = signal(false);
  bool _disposed = false;

  /// A request is running (it may first wait for a sign-out still in flight): the form sends
  /// nothing else meanwhile.
  ReadonlySignal<bool> get busy => _busy;

  /// The page is gone: signals must not be written any more.
  @protected
  bool get isDisposed => _disposed;

  /// Prefills the email field with the last account on this phone.
  String? get lastEmail => sessionHolder.lastEmail;

  /// Why the user is back on this page (revoked, account deleted), shown above the form.
  SignOutReason? get signOutReason => sessionHolder.signOutReason.peek();

  Future<void> submit(String email, String password);

  /// Runs [action] unless one is already running — the button, the keyboard's "done" and autofill
  /// can all submit.
  Future<void> run(Future<void> Function() action) async {
    if (_disposed || _busy.peek()) return;
    _busy.value = true;
    await guard(action);
    if (!_disposed) _busy.value = false;
  }

  void dispose() {
    _disposed = true;
    _busy.dispose();
  }
}
