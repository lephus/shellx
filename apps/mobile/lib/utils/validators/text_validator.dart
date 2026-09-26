import 'package:shellx_mobile/shared/shared.dart';
import '../constants/regex_patterns.dart';

/// Validates required text field
///
/// Returns `null` if valid, error message string if invalid
String? validateRequired(String? value) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationTextRequired;
  }

  if (value.trim().isEmpty) {
    return s.validationTextRequired;
  }

  return null;
}

/// Validates minimum length
String? validateMinLength(
  String? value,
  int minLength,
) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationTextRequired;
  }

  if (value.length < minLength) {
    return s.validationTextMinLength(minLength);
  }

  return null;
}

/// Validates maximum length
String? validateMaxLength(
  String? value,
  int maxLength,
) {
  final s = S.current;

  if (value != null && value.length > maxLength) {
    return s.validationTextMaxLength(maxLength);
  }

  return null;
}

/// Validates length range
String? validateLengthRange(
  String? value,
  int minLength,
  int maxLength,
) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationTextRequired;
  }

  if (value.length < minLength) {
    return s.validationTextMinLength(minLength);
  }

  if (value.length > maxLength) {
    return s.validationTextMaxLength(maxLength);
  }

  return null;
}

/// Validates name (letters, spaces, hyphens, apostrophes)
String? validateName(String? value, {String fieldName = 'Name'}) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationTextRequired;
  }

  final trimmedValue = value.trim();

  if (trimmedValue.isEmpty) {
    return s.validationTextRequired;
  }

  if (trimmedValue.length < 2) {
    return s.validationTextMinLength(2);
  }

  if (!RegexPatterns.name.hasMatch(trimmedValue)) {
    return s.validationTextRequired; // Using generic message for now
  }

  return null;
}

/// Validates alphanumeric text
String? validateAlphanumeric(String? value) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationTextRequired;
  }

  if (!RegexPatterns.alphanumeric.hasMatch(value)) {
    return s.validationTextRequired; // Using generic message
  }

  return null;
}

/// Validates optional alphanumeric code (like referral code)
String? validateOptionalCode(String? value) {
  // If empty, it's valid (optional field)
  if (value == null || value.isEmpty || value.trim().isEmpty) {
    return null;
  }

  if (!RegexPatterns.alphanumeric.hasMatch(value)) {
    return S.current.validationTextRequired; // Using generic message
  }

  return null;
}

/// Combines multiple validators
String? combineValidators(
  String? value,
  List<String? Function(String?)> validators,
) {
  for (final validator in validators) {
    final error = validator(value);
    if (error != null) {
      return error;
    }
  }
  return null;
}
