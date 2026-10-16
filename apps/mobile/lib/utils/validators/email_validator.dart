import 'package:shellx_mobile/shared/shared.dart';
import '../constants/regex_patterns.dart';

/// Validates email address format
///
/// Returns `null` if valid, error message string if invalid
/// Compatible with Flutter's TextFormField validator
String? validateEmail(String? value) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationEmailRequired;
  }

  final trimmedValue = value.trim();

  if (trimmedValue.isEmpty) {
    return s.validationEmailRequired;
  }

  if (!RegexPatterns.email.hasMatch(trimmedValue)) {
    return s.validationEmailInvalid;
  }

  return null;
}

/// Validates email with custom error messages
String? validateEmailWithMessages({
  required String? value,
  String? requiredMessage,
  String? invalidMessage,
}) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return requiredMessage ?? s.validationEmailRequired;
  }

  final trimmedValue = value.trim();

  if (trimmedValue.isEmpty) {
    return requiredMessage ?? s.validationEmailRequired;
  }

  if (!RegexPatterns.email.hasMatch(trimmedValue)) {
    return invalidMessage ?? s.validationEmailInvalid;
  }

  return null;
}
