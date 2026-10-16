import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/l10n/app_localizations_en.dart';
import 'package:shellx_desktop/src/ui/form_rules.dart';

/// Binding ruling (Task 10 brief cannot know it): the relay counts
/// **Unicode code points after NFC** (8-128), not UTF-16 code units. An
/// emoji is one code point but two UTF-16 code units (a surrogate pair), so
/// `String.length` would accept a 4-emoji password (`length == 8`) that the
/// relay rejects, and reject an 8-emoji one (`length == 16`) that the relay
/// accepts. `validPasswordLength` must use `.runes.length` to agree with the
/// relay's `password-policy.ts` (NFC normalisation is not attempted
/// client-side; the relay stays authoritative and its error is shown).
void main() {
  group('validPasswordLength (code points, not UTF-16 code units)', () {
    test('an 8-emoji password is valid even though .length is 16', () {
      final eightEmoji = '😀' * 8;
      expect(eightEmoji.length, 16, reason: 'sanity: UTF-16 code units');
      expect(eightEmoji.runes.length, 8, reason: 'sanity: code points');
      expect(validPasswordLength(eightEmoji), isTrue);
    });

    test('a 4-emoji password is invalid even though .length is 8', () {
      final fourEmoji = '😀' * 4;
      expect(fourEmoji.length, 8, reason: 'sanity: UTF-16 code units');
      expect(fourEmoji.runes.length, 4, reason: 'sanity: code points');
      expect(validPasswordLength(fourEmoji), isFalse);
    });

    test('accepts exactly 8 and exactly 128 ASCII characters', () {
      expect(validPasswordLength('a' * 8), isTrue);
      expect(validPasswordLength('a' * 128), isTrue);
    });

    test('rejects 7 and 129 ASCII characters', () {
      expect(validPasswordLength('a' * 7), isFalse);
      expect(validPasswordLength('a' * 129), isFalse);
    });
  });

  group('apiErrorText — unexpected/new relay codes never leak raw text', () {
    final l10n = AppLocalizationsEn();

    test('413 payload_too_large maps to the generic error text', () {
      const error = ApiException(
        status: 413,
        code: 'payload_too_large',
        message: 'Payload too large',
      );
      expect(
        apiErrorText(error, l10n),
        l10n.errorUnexpected('payload_too_large'),
      );
    });

    test('401 invalid_credentials (oversized login password) is friendly', () {
      const error = ApiException(
        status: 401,
        code: 'invalid_credentials',
        message: 'Invalid credentials',
      );
      expect(apiErrorText(error, l10n), l10n.errorInvalidCredentials);
    });

    test('429 always wins, regardless of the body code', () {
      const error = ApiException(
        status: 429,
        code: 'rate_limited',
        message: 'Too many requests',
      );
      expect(apiErrorText(error, l10n), l10n.errorRateLimited);
    });
  });
}
