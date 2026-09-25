import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/validators/text_validator.dart';

void main() {
  // Initialize S.current for tests
  setUpAll(() async {
    // Initialize the intl system
    await S.load(const Locale('en'));
  });

  group('validateRequired', () {
    test('returns error when value is null', () {
      expect(validateRequired(null), equals('This field is required'));
    });

    test('returns error when value is empty', () {
      expect(validateRequired(''), equals('This field is required'));
    });

    test('returns error when value is only whitespace', () {
      expect(validateRequired('   '), equals('This field is required'));
    });

    test('returns null for valid value', () {
      expect(validateRequired('value'), isNull);
    });
  });

  group('validateMinLength', () {
    test('returns error when value is null', () {
      expect(validateMinLength(null, 5), isNotNull);
    });

    test('returns error when value is too short', () {
      expect(
        validateMinLength('abc', 5),
        equals('Must be at least 5 characters'),
      );
    });

    test('returns null when value meets minimum', () {
      expect(validateMinLength('12345', 5), isNull);
    });

    test('returns null when value exceeds minimum', () {
      expect(validateMinLength('123456', 5), isNull);
    });
  });

  group('validateMaxLength', () {
    test('returns null when value is null', () {
      expect(validateMaxLength(null, 10), isNull);
    });

    test('returns error when value exceeds maximum', () {
      expect(
        validateMaxLength('12345678901', 10),
        equals('Must be at most 10 characters'),
      );
    });

    test('returns null when value is within limit', () {
      expect(validateMaxLength('123456789', 10), isNull);
    });

    test('returns null when value equals maximum', () {
      expect(validateMaxLength('1234567890', 10), isNull);
    });
  });

  group('validateLengthRange', () {
    test('returns error when value is null', () {
      expect(validateLengthRange(null, 5, 10), isNotNull);
    });

    test('returns error when value is too short', () {
      expect(
        validateLengthRange('abc', 5, 10),
        equals('Must be at least 5 characters'),
      );
    });

    test('returns error when value is too long', () {
      expect(
        validateLengthRange('12345678901', 5, 10),
        equals('Must be at most 10 characters'),
      );
    });

    test('returns null when value is minimum length', () {
      expect(validateLengthRange('12345', 5, 10), isNull);
    });

    test('returns null when value is maximum length', () {
      expect(validateLengthRange('1234567890', 5, 10), isNull);
    });

    test('returns null when value is within range', () {
      expect(validateLengthRange('1234567', 5, 10), isNull);
    });
  });

  group('validateName', () {
    test('returns error when value is null', () {
      expect(validateName(null), equals('This field is required'));
    });

    test('returns error when value is empty', () {
      expect(validateName(''), equals('This field is required'));
    });

    test('returns error when value is whitespace', () {
      expect(validateName('   '), equals('This field is required'));
    });

    test('returns error when name is too short', () {
      expect(validateName('A'), equals('Must be at least 2 characters'));
    });

    test('returns error when name contains numbers', () {
      expect(
        validateName('John123'),
        equals('This field is required'), // Generic message for invalid format
      );
    });

    test('returns error when name contains special chars', () {
      expect(
        validateName('John@Doe'),
        equals('This field is required'), // Generic message for invalid format
      );
    });

    test('returns null for simple name', () {
      expect(validateName('John'), isNull);
    });

    test('returns null for name with space', () {
      expect(validateName('John Doe'), isNull);
    });

    test('returns null for hyphenated name', () {
      expect(validateName('Mary-Jane'), isNull);
    });

    test('returns null for name with apostrophe', () {
      expect(validateName("O'Connor"), isNull);
    });

    test('returns null for multiple words', () {
      expect(validateName('Jean-Luc Picard'), isNull);
    });

    test('trims whitespace', () {
      expect(validateName('  John  '), isNull);
    });
  });

  group('validateAlphanumeric', () {
    test('returns error when value is null', () {
      expect(validateAlphanumeric(null), isNotNull);
    });

    test('returns error when value is empty', () {
      expect(validateAlphanumeric(''), isNotNull);
    });

    test('returns error when value contains spaces', () {
      expect(
        validateAlphanumeric('abc 123'),
        equals('This field is required'), // Generic message
      );
    });

    test('returns error when value contains special chars', () {
      expect(
        validateAlphanumeric('abc-123'),
        equals('This field is required'), // Generic message
      );
    });

    test('returns null for letters only', () {
      expect(validateAlphanumeric('abcdef'), isNull);
    });

    test('returns null for numbers only', () {
      expect(validateAlphanumeric('123456'), isNull);
    });

    test('returns null for mixed alphanumeric', () {
      expect(validateAlphanumeric('abc123'), isNull);
    });

    test('returns null for uppercase and lowercase', () {
      expect(validateAlphanumeric('AbC123'), isNull);
    });
  });

  group('validateOptionalCode', () {
    test('returns null when value is null', () {
      expect(validateOptionalCode(null), isNull);
    });

    test('returns null when value is empty', () {
      expect(validateOptionalCode(''), isNull);
    });

    test('returns null when value is whitespace', () {
      expect(validateOptionalCode('   '), isNull);
    });

    test('returns null for valid alphanumeric code', () {
      expect(validateOptionalCode('ABC123'), isNull);
    });

    test('returns error for code with special chars', () {
      expect(
        validateOptionalCode('ABC-123'),
        equals('This field is required'), // Generic message
      );
    });

    test('returns error for code with spaces', () {
      expect(
        validateOptionalCode('ABC 123'),
        equals('This field is required'), // Generic message
      );
    });
  });

  group('combineValidators', () {
    test('returns null when all validators pass', () {
      final result = combineValidators('test', [
        (v) => validateRequired(v),
        (v) => validateMinLength(v, 2),
        (v) => validateMaxLength(v, 10),
      ]);
      expect(result, isNull);
    });

    test('returns first error when validator fails', () {
      final result = combineValidators(null, [
        (v) => validateRequired(v),
        (v) => validateMinLength(v, 2),
      ]);
      expect(result, equals('This field is required'));
    });

    test('stops at first error', () {
      var secondValidatorCalled = false;

      final result = combineValidators('a', [
        (v) => validateMinLength(v, 5),
        (v) {
          secondValidatorCalled = true;
          return null;
        },
      ]);

      expect(result, isNotNull);
      expect(secondValidatorCalled, isFalse);
    });

    test('handles empty validator list', () {
      final result = combineValidators('test', []);
      expect(result, isNull);
    });

    test('executes validators in order', () {
      final executionOrder = <String>[];

      combineValidators('test', [
        (v) {
          executionOrder.add('first');
          return null;
        },
        (v) {
          executionOrder.add('second');
          return null;
        },
        (v) {
          executionOrder.add('third');
          return null;
        },
      ]);

      expect(executionOrder, equals(['first', 'second', 'third']));
    });
  });
}
