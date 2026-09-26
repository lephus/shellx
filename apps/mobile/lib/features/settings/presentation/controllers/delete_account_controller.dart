import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §5.2 (App Store 5.1.1(v)): delete the account after re-entering the password.
@injectable
class DeleteAccountController extends Controller {
  DeleteAccountController(this._session);

  final SessionHolder _session;
  final Signal<bool> _busy = signal(false);
  final Signal<String?> _error = signal(null);
  bool _disposed = false;

  /// While true, the page blocks back navigation and disables "Hủy": a logout landing in this
  /// deletion's DELETE window would join it as a plain sign-out and keep the device key and pins.
  ReadonlySignal<bool> get busy => _busy;

  /// Shown under the password field: "Mật khẩu không đúng.", "Thử lại sau ít phút.", …
  ReadonlySignal<String?> get error => _error;

  String get email => _session.session.peek()?.email ?? '';

  void clearError() => _error.value = null;

  /// On success `SessionEnforcer` leaves the signed-in pages.
  Future<void> delete(String password) async {
    _busy.value = true;
    _error.value = null;
    await guard(
      () async {
        try {
          await _session.deleteAccount(password);
        } catch (error) {
          if (!_disposed) _error.value = _message(error);
          rethrow;
        }
      },
      showError: false,
    );
    if (!_disposed) _busy.value = false;
  }

  String _message(Object error) => switch (error) {
    ApiException(code: 'invalid_credentials') => S.current.errorWrongPassword,
    _ => errorFactory.fromException(error).title,
  };

  void dispose() {
    _disposed = true;
    _busy.dispose();
    _error.dispose();
  }
}
