import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Turns contract exceptions and failure codes into the user-facing texts of
/// spec §12 (Vietnamese) and their English equivalents.
///
/// Every user-visible failure goes through this class — never an exception's
/// `toString()` (an [ApiException] or relay failure can carry request
/// details, overview §2).
///
/// Machine-level vs. per-tab wording (context for Tasks 12/14): when a
/// pinned machine's channel goes `untrusted`, `MachineClient` both moves to
/// `MachineFailed(untrusted)` *and* ends every open tab on that machine with
/// `TabError(AppErrorCode.sessionNotFound)`. The machine-level text from
/// [machine] ("Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.") must
/// be what the user sees for the machine; the per-tab [appError] text for
/// `sessionNotFound` ("Phiên đã kết thúc") is correct for an ordinary
/// session-vanished tab, but is not the right explanation when the real
/// cause is the machine no longer trusting this phone — the UI should prefer
/// the machine-level failure when both are available for the same event.
final class ErrorText {
  const ErrorText(this.strings);

  final S strings;

  String describe(Object error) => switch (error) {
    ApiException() => api(error),
    PairingException(:final failure) => pairing(failure),
    AppErrorException(:final code, :final message) => appError(code, message),
    MachineFailed(:final failure) => machine(failure),
    MachineConnectionException(:final failure) => machine(failure),
    _ => strings.errorUnknown(error.runtimeType.toString()),
  };

  /// HTTP 429 is recognised by status, never by code (plan 02). Any other
  /// code this app does not special-case (e.g. the relay's `413
  /// payload_too_large`, `410 pairing_removed`) falls through to the
  /// generic, localized "Đã có lỗi xảy ra (…)" text.
  String api(ApiException error) {
    if (error.status == 429) return strings.errorRateLimited;
    return switch (error.code) {
      'network' => strings.errorNetwork,
      'unauthorized' => strings.signedOutExpired,
      'invalid_email' => strings.errorInvalidEmail,
      'disposable_email' => strings.errorDisposableEmail,
      'weak_password' => strings.errorWeakPassword,
      'email_taken' => strings.errorEmailTaken,
      'invalid_credentials' => strings.errorInvalidCredentials,
      _ => strings.errorUnknown(error.code),
    };
  }

  /// `invalidOrExpired` uses the fuller §12 text (the §5.3 text is its first sentence).
  String pairing(PairingFailure failure) => switch (failure) {
    PairingFailure.notInAccount => strings.errorNotInAccount,
    PairingFailure.invalidOrExpired => strings.errorQrInvalid,
    PairingFailure.agentOffline => strings.errorAgentOffline,
    PairingFailure.protocolUnsupported => strings.updateRequiredTitle,
    PairingFailure.timeout => strings.errorTimeout,
  };

  String machine(MachineConnectionFailure failure) => switch (failure) {
    MachineConnectionFailure.untrusted => strings.errorUntrusted,
    MachineConnectionFailure.protocolUnsupported => strings.updateRequiredTitle,
    MachineConnectionFailure.agentOffline => strings.machineOffline,
    MachineConnectionFailure.timeout => strings.errorTimeout,
  };

  String appError(AppErrorCode code, String message) => switch (code) {
    AppErrorCode.sessionLimit => strings.errorSessionLimit,
    AppErrorCode.sessionNotFound => strings.sessionEnded,
    AppErrorCode.spawnFailed => strings.errorSpawnFailed(message),
  };
}
