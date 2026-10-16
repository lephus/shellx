import 'package:shellx_mobile/shared/shared.dart';
import '../constants/regex_patterns.dart';

/// Password validation configuration
class PasswordRequirements {
  final int minLength;
  final bool requireUppercase;
  final bool requireLowercase;
  final bool requireDigit;
  final bool requireSpecialChar;

  const PasswordRequirements({
    this.minLength = 8,
    this.requireUppercase = true,
    this.requireLowercase = true,
    this.requireDigit = true,
    this.requireSpecialChar = false,
  });

  /// Default password requirements
  static const standard = PasswordRequirements();

  /// Weak password requirements (only length check)
  static const weak = PasswordRequirements(
    minLength: 6,
    requireUppercase: false,
    requireLowercase: false,
    requireDigit: false,
    requireSpecialChar: false,
  );

  /// Strong password requirements
  static const strong = PasswordRequirements(
    minLength: 12,
    requireUppercase: true,
    requireLowercase: true,
    requireDigit: true,
    requireSpecialChar: true,
  );
}

/// Validates password with standard requirements
///
/// Default requirements: min 8 chars, uppercase, lowercase, digit
/// Returns `null` if valid, error message string if invalid
String? validatePassword(
  String? value, {
  PasswordRequirements requirements = PasswordRequirements.standard,
}) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationPasswordRequired;
  }

  if (value.length < requirements.minLength) {
    return s.validationPasswordMinLength(requirements.minLength);
  }

  if (requirements.requireUppercase && !RegexPatterns.hasUppercase.hasMatch(value)) {
    return s.validationPasswordUppercase;
  }

  if (requirements.requireLowercase && !RegexPatterns.hasLowercase.hasMatch(value)) {
    return s.validationPasswordLowercase;
  }

  if (requirements.requireDigit && !RegexPatterns.hasDigit.hasMatch(value)) {
    return s.validationPasswordDigit;
  }

  if (requirements.requireSpecialChar && !RegexPatterns.hasSpecialChar.hasMatch(value)) {
    return s.validationPasswordSpecialChar;
  }

  return null;
}

/// Validates password confirmation matches original password
String? validatePasswordConfirmation(
  String? value,
  String? originalPassword,
) {
  final s = S.current;

  if (value == null || value.isEmpty) {
    return s.validationPasswordConfirmRequired;
  }

  if (value != originalPassword) {
    return s.validationPasswordNotMatch;
  }

  return null;
}

/// Calculates password strength (0.0 to 1.0)
double calculatePasswordStrength(String password) {
  if (password.isEmpty) return 0.0;

  double strength = 0.0;

  // Length score (up to 0.3)
  if (password.length >= 8) strength += 0.1;
  if (password.length >= 12) strength += 0.1;
  if (password.length >= 16) strength += 0.1;

  // Character variety score (up to 0.7)
  if (RegexPatterns.hasLowercase.hasMatch(password)) strength += 0.15;
  if (RegexPatterns.hasUppercase.hasMatch(password)) strength += 0.15;
  if (RegexPatterns.hasDigit.hasMatch(password)) strength += 0.2;
  if (RegexPatterns.hasSpecialChar.hasMatch(password)) strength += 0.2;

  return strength.clamp(0.0, 1.0);
}
