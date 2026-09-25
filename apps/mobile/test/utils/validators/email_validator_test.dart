import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:shellx_mobile/utils/validators/email_validator.dart';

void main() {
  // Initialize S.current for tests
  setUpAll(() async {
    await S.load(const Locale('en'));
  });

  group('validateEmail', () {
    group('should return error message when', () {
      test('value is null', () {
        expect(validateEmail(null), equals('Email is required'));
      });

      test('value is empty string', () {
        expect(validateEmail(''), equals('Email is required'));
      });

      test('value is only whitespace', () {
        expect(validateEmail('   '), equals('Email is required'));
      });

      test('email format is invalid - missing @', () {
        expect(
          validateEmail('invalidemail.com'),
          equals('Please enter a valid email address'),
        );
      });

      test('email format is invalid - missing domain', () {
        expect(
          validateEmail('test@'),
          equals('Please enter a valid email address'),
        );
      });

      test('email format is invalid - missing TLD', () {
        expect(
          validateEmail('test@domain'),
          equals('Please enter a valid email address'),
        );
      });

      test('email format is invalid - spaces in email', () {
        expect(
          validateEmail('test @domain.com'),
          equals('Please enter a valid email address'),
        );
      });
    });

    group('should return null (valid) when', () {
      test('email is valid - simple format', () {
        expect(validateEmail('test@example.com'), isNull);
      });

      test('email is valid - with subdomain', () {
        expect(validateEmail('user@mail.example.com'), isNull);
      });

      test('email is valid - with plus sign', () {
        expect(validateEmail('user+tag@example.com'), isNull);
      });

      test('email is valid - with dots', () {
        expect(validateEmail('first.last@example.com'), isNull);
      });

      test('email is valid - with numbers', () {
        expect(validateEmail('user123@example.com'), isNull);
      });

      test('email is valid - with hyphen', () {
        expect(validateEmail('user-name@example.com'), isNull);
      });

      test('email is valid - with underscore', () {
        expect(validateEmail('user_name@example.com'), isNull);
      });

      test('email is valid - long TLD', () {
        expect(validateEmail('user@example.museum'), isNull);
      });

      test('email trims whitespace', () {
        expect(validateEmail('  test@example.com  '), isNull);
      });
    });
  });

  group('validateEmailWithMessages', () {
    test('uses custom required message', () {
      expect(
        validateEmailWithMessages(
          value: null,
          requiredMessage: 'Custom required message',
        ),
        equals('Custom required message'),
      );
    });

    test('uses custom invalid message', () {
      expect(
        validateEmailWithMessages(
          value: 'invalid',
          invalidMessage: 'Custom invalid message',
        ),
        equals('Custom invalid message'),
      );
    });

    test('uses default messages when custom not provided', () {
      expect(
        validateEmailWithMessages(value: null),
        equals('Email is required'),
      );
      expect(
        validateEmailWithMessages(value: 'invalid'),
        equals('Please enter a valid email address'),
      );
    });
  });
}
