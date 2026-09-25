/// Common regex patterns used throughout the app
class RegexPatterns {
  RegexPatterns._();

  /// Email validation pattern
  /// Matches most common email formats
  static final RegExp email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// Phone number pattern (digits only, 10-15 characters)
  /// Adjust based on your specific phone number requirements
  static final RegExp phone = RegExp(
    r'^\d{10,15}$',
  );

  /// Phone number with optional country code and separators
  static final RegExp phoneWithFormat = RegExp(
    r'^\+?[\d\s\-\(\)]{10,20}$',
  );

  /// Password strength patterns
  static final RegExp hasUppercase = RegExp(r'[A-Z]');
  static final RegExp hasLowercase = RegExp(r'[a-z]');
  static final RegExp hasDigit = RegExp(r'\d');
  static final RegExp hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

  /// Name validation (letters, spaces, hyphens)
  static final RegExp name = RegExp(r"^[a-zA-Z\s\-']+$");

  /// Alphanumeric only
  static final RegExp alphanumeric = RegExp(r'^[a-zA-Z0-9]+$');
}
