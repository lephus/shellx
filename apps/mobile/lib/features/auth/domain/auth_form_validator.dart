import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/utils.dart' as utils;

/// Client-side checks before a request; the relay stays the authority (spec §5.2).
class AuthFormValidator {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;

  /// Format only (the base's pragmatic regex); disposable domains are rejected by the relay.
  String? validateEmail(String? value) => utils.validateEmailWithMessages(
    value: value,
    requiredMessage: S.current.errorInvalidEmail,
    invalidMessage: S.current.errorInvalidEmail,
  );

  /// Sign-in: any stored password may be typed, only an empty one is refused.
  String? validatePassword(String? value) =>
      value == null || value.isEmpty ? S.current.validationPasswordRequired : null;

  /// Registration: spec §5.2 "8–128 ký tự" and nothing else (no case or digit rules).
  String? validateNewPassword(String? value) {
    final length = passwordLength(value ?? '');
    return length < minPasswordLength || length > maxPasswordLength ? S.current.errorWeakPassword : null;
  }

  /// Characters as the relay counts them: Unicode code points, so an emoji is one character, not
  /// two UTF-16 units. The relay counts after NFC normalisation, which Dart does not provide: an
  /// accent typed as a separate combining mark counts twice here, and the relay's `weak_password`
  /// then shows under the field.
  static int passwordLength(String value) => value.runes.length;
}
