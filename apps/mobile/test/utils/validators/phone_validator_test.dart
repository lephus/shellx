import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/validators/phone_validator.dart';

void main() {
  // Initialize S.current for tests
  setUpAll(() async {
    await S.load(const Locale('en'));
  });

  group('validatePhone', () {
    group('without formatting (default)', () {
      test('returns error when phone is null', () {
        expect(validatePhone(null), equals('Phone number is required'));
      });

      test('returns error when phone is empty', () {
        expect(validatePhone(''), equals('Phone number is required'));
      });

      test('returns error when phone is only whitespace', () {
        expect(validatePhone('   '), equals('Phone number is required'));
      });

      test('returns error when phone is too short', () {
        expect(
          validatePhone('123456'),
          equals('Please enter a valid phone number'),
        );
      });

      test('returns error when phone is too long', () {
        expect(
          validatePhone('1234567890123456'),
          equals('Please enter a valid phone number'),
        );
      });

      test('returns error when phone contains letters', () {
        expect(
          validatePhone('12345abcde'),
          equals('Please enter a valid phone number'),
        );
      });

      test('returns error when phone contains special characters', () {
        expect(
          validatePhone('123-456-7890'),
          equals('Please enter a valid phone number'),
        );
      });

      test('returns null for valid 10-digit phone', () {
        expect(validatePhone('1234567890'), isNull);
      });

      test('returns null for valid 11-digit phone', () {
        expect(validatePhone('12345678901'), isNull);
      });

      test('returns null for valid 15-digit phone', () {
        expect(validatePhone('123456789012345'), isNull);
      });

      test('trims whitespace', () {
        expect(validatePhone('  1234567890  '), isNull);
      });

      test('returns error for phone with + (requires allowFormatting)', () {
        expect(
          validatePhone('+84386412929'),
          equals('Please enter a valid phone number'),
        );
      });
    });

    group('with formatting allowed', () {
      test('accepts phone with hyphens', () {
        expect(validatePhone('123-456-7890', allowFormatting: true), isNull);
      });

      test('accepts phone with spaces', () {
        expect(validatePhone('123 456 7890', allowFormatting: true), isNull);
      });

      test('accepts phone with parentheses', () {
        expect(validatePhone('(123) 456-7890', allowFormatting: true), isNull);
      });

      test('accepts phone with country code', () {
        expect(validatePhone('+1 123 456 7890', allowFormatting: true), isNull);
      });

      test('accepts international format', () {
        expect(validatePhone('+44 20 1234 5678', allowFormatting: true), isNull);
      });

      test('returns error for invalid format', () {
        expect(
          validatePhone('abc-def-ghij', allowFormatting: true),
          equals('Please enter a valid phone number'),
        );
      });

      test('returns error when too short even with formatting', () {
        expect(
          validatePhone('123', allowFormatting: true),
          equals('Please enter a valid phone number'),
        );
      });

      test('accepts Vietnamese phone with country code (no spaces)', () {
        expect(validatePhone('+84386412929', allowFormatting: true), isNull);
      });

      test('accepts Vietnamese phone with country code (with spaces)', () {
        expect(validatePhone('+84 386 412 929', allowFormatting: true), isNull);
      });

      test('accepts Vietnamese phone without country code', () {
        expect(validatePhone('0386412929', allowFormatting: true), isNull);
      });
    });
  });

  group('validatePhoneWithMessages', () {
    test('uses custom required message', () {
      expect(
        validatePhoneWithMessages(
          value: null,
          requiredMessage: 'Custom required message',
        ),
        equals('Custom required message'),
      );
    });

    test('uses custom invalid message', () {
      expect(
        validatePhoneWithMessages(
          value: '123',
          invalidMessage: 'Custom invalid message',
        ),
        equals('Custom invalid message'),
      );
    });

    test('uses default messages when custom not provided', () {
      expect(
        validatePhoneWithMessages(value: null),
        equals('Phone number is required'),
      );
    });
  });

  group('stripPhoneFormatting', () {
    test('removes hyphens', () {
      expect(stripPhoneFormatting('123-456-7890'), equals('1234567890'));
    });

    test('removes spaces', () {
      expect(stripPhoneFormatting('123 456 7890'), equals('1234567890'));
    });

    test('removes parentheses', () {
      expect(stripPhoneFormatting('(123) 456-7890'), equals('1234567890'));
    });

    test('removes plus sign', () {
      expect(stripPhoneFormatting('+1234567890'), equals('1234567890'));
    });

    test('removes all formatting characters', () {
      expect(
        stripPhoneFormatting('+1 (123) 456-7890'),
        equals('11234567890'),
      );
    });

    test('returns same string if already digits only', () {
      expect(stripPhoneFormatting('1234567890'), equals('1234567890'));
    });

    test('handles empty string', () {
      expect(stripPhoneFormatting(''), equals(''));
    });
  });
}
