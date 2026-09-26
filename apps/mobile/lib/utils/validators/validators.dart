/// Form validators for common validation scenarios
///
/// Usage example:
/// ```dart
/// TextFormField(
///   validator: validateEmail,
///   // or with custom requirements
///   validator: (value) => validatePassword(
///     value,
///     requirements: PasswordRequirements.strong,
///   ),
/// )
/// ```
library;

export 'email_validator.dart';
export 'password_validator.dart';
export 'phone_validator.dart';
export 'text_validator.dart';
