import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/validators/password_validator.dart';

void main() {
  // Initialize S.current for tests
  setUpAll(() async {
    await S.load(const Locale('en'));
  });

  group('validatePassword', () {
    group('with standard requirements', () {
      test('returns error when password is null', () {
        expect(validatePassword(null), equals('Password is required'));
      });

      test('returns error when password is empty', () {
        expect(validatePassword(''), equals('Password is required'));
      });

      test('returns error when password is too short', () {
        expect(
          validatePassword('Abc1'),
          equals('Password must be at least 8 characters'),
        );
      });

      test('returns error when missing uppercase', () {
        expect(
          validatePassword('abcdefgh1'),
          equals('Password must contain at least one uppercase letter'),
        );
      });

      test('returns error when missing lowercase', () {
        expect(
          validatePassword('ABCDEFGH1'),
          equals('Password must contain at least one lowercase letter'),
        );
      });

      test('returns error when missing digit', () {
        expect(
          validatePassword('Abcdefgh'),
          equals('Password must contain at least one number'),
        );
      });

      test('returns null for valid password', () {
        expect(validatePassword('SecurePass123'), isNull);
      });

      test('returns null for valid password with special chars', () {
        expect(validatePassword('SecurePass123!@#'), isNull);
      });
    });

    group('with weak requirements', () {
      test('accepts short password', () {
        expect(
          validatePassword('simple', requirements: PasswordRequirements.weak),
          isNull,
        );
      });

      test('accepts password without uppercase', () {
        expect(
          validatePassword('simple', requirements: PasswordRequirements.weak),
          isNull,
        );
      });
    });

    group('with strong requirements', () {
      test('requires minimum 12 characters', () {
        expect(
          validatePassword('Test123!', requirements: PasswordRequirements.strong),
          equals('Password must be at least 12 characters'),
        );
      });

      test('requires special character', () {
        expect(
          validatePassword(
            'SecurePass123',
            requirements: PasswordRequirements.strong,
          ),
          equals('Password must contain at least one special character'),
        );
      });

      test('accepts valid strong password', () {
        expect(
          validatePassword(
            'SecurePass123!',
            requirements: PasswordRequirements.strong,
          ),
          isNull,
        );
      });
    });

    group('with custom requirements', () {
      test('respects custom minimum length', () {
        final customReq = PasswordRequirements(
          minLength: 10,
          requireUppercase: false,
          requireLowercase: false,
          requireDigit: false,
        );

        expect(validatePassword('short', requirements: customReq), isNotNull);
        expect(validatePassword('longenough', requirements: customReq), isNull);
      });

      test('respects disabled requirements', () {
        final customReq = PasswordRequirements(
          minLength: 6,
          requireUppercase: false,
          requireLowercase: false,
          requireDigit: false,
          requireSpecialChar: false,
        );

        expect(validatePassword('simple', requirements: customReq), isNull);
      });
    });
  });

  group('validatePasswordConfirmation', () {
    test('returns error when confirmation is null', () {
      expect(
        validatePasswordConfirmation(null, 'password'),
        equals('Please confirm your password'),
      );
    });

    test('returns error when confirmation is empty', () {
      expect(
        validatePasswordConfirmation('', 'password'),
        equals('Please confirm your password'),
      );
    });

    test('returns error when passwords do not match', () {
      expect(
        validatePasswordConfirmation('password1', 'password2'),
        equals('Passwords do not match'),
      );
    });

    test('returns null when passwords match', () {
      expect(
        validatePasswordConfirmation('SecurePass123', 'SecurePass123'),
        isNull,
      );
    });

    test('is case sensitive', () {
      expect(
        validatePasswordConfirmation('Password', 'password'),
        equals('Passwords do not match'),
      );
    });
  });

  group('calculatePasswordStrength', () {
    test('returns 0.0 for empty password', () {
      expect(calculatePasswordStrength(''), equals(0.0));
    });

    test('returns low strength for simple password', () {
      final strength = calculatePasswordStrength('password');
      expect(strength, lessThan(0.4));
    });

    test('returns medium strength for decent password', () {
      final strength = calculatePasswordStrength('Password1');
      expect(strength, greaterThan(0.4));
      expect(strength, lessThan(0.8));
    });

    test('returns high strength for strong password', () {
      final strength = calculatePasswordStrength('SecurePass123!@#');
      expect(strength, greaterThan(0.8));
    });

    test('increases strength with length', () {
      final short = calculatePasswordStrength('Pass1');
      final medium = calculatePasswordStrength('Password123');
      final long = calculatePasswordStrength('VeryLongPassword123');

      expect(medium, greaterThan(short));
      expect(long, greaterThan(medium));
    });

    test('increases strength with character variety', () {
      final lower = calculatePasswordStrength('passwordpassword');
      final lowerUpper = calculatePasswordStrength('PasswordPassword');
      final withDigit = calculatePasswordStrength('Password12345678');
      final withSpecial = calculatePasswordStrength('Password123!@#\$%');

      expect(lowerUpper, greaterThan(lower));
      expect(withDigit, greaterThan(lowerUpper));
      expect(withSpecial, greaterThan(withDigit));
    });

    test('never exceeds 1.0', () {
      final strength = calculatePasswordStrength(
        'VerySecureP@ssw0rd!WithLots0fCharacters123',
      );
      expect(strength, lessThanOrEqualTo(1.0));
    });
  });
}
