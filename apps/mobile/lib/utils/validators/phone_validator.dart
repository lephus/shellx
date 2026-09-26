import 'package:shellx_mobile/shared/shared.dart';
import '../constants/regex_patterns.dart';

/// Validates phone number format
///
/// By default, expects digits only (10-15 characters)
/// Returns `null` if valid, error message string if invalid
String? validatePhone(
  String? value, {
  bool allowFormatting = false,
}) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationPhoneRequired;
  }

  final trimmedValue = value.trim();

  if (trimmedValue.isEmpty) {
    return s.validationPhoneRequired;
  }

  // Use appropriate pattern based on allowFormatting
  final pattern = allowFormatting ? RegexPatterns.phoneWithFormat : RegexPatterns.phone;

  if (!pattern.hasMatch(trimmedValue)) {
    return s.validationPhoneInvalid;
  }

  return null;
}

/// Validates phone with custom error messages
String? validatePhoneWithMessages({
  required String? value,
  String? requiredMessage,
  String? invalidMessage,
  bool allowFormatting = false,
}) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return requiredMessage ?? s.validationPhoneRequired;
  }

  final trimmedValue = value.trim();

  if (trimmedValue.isEmpty) {
    return requiredMessage ?? s.validationPhoneRequired;
  }

  final pattern = allowFormatting ? RegexPatterns.phoneWithFormat : RegexPatterns.phone;

  if (!pattern.hasMatch(trimmedValue)) {
    return invalidMessage ?? s.validationPhoneInvalid;
  }

  return null;
}

/// Strips phone number to digits only
String stripPhoneFormatting(String phone) {
  return phone.replaceAll(RegExp(r'[^\d]'), '');
}
