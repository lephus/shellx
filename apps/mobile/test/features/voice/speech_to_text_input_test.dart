import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/voice/data/speech_to_text_input.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

void main() {
  group('pickLocaleId', () {
    test('prefers the exact preferred locale in either separator style', () {
      expect(pickLocaleId(['en-GB', 'vi-VN', 'en-US'], VoiceLocale.vi), 'vi-VN');
      expect(pickLocaleId(['en_GB', 'en_US', 'vi_VN'], VoiceLocale.en), 'en_US');
    });

    test('falls back to any locale of the language', () {
      expect(pickLocaleId(['en-GB', 'fr-FR'], VoiceLocale.en), 'en-GB');
    });

    test('null when the phone has no locale of the language', () {
      expect(pickLocaleId(['en-US', 'fr-FR'], VoiceLocale.vi), isNull);
      expect(pickLocaleId([], VoiceLocale.en), isNull);
    });

    test('a language prefix must be the whole language ("vi" is not "vie")', () {
      expect(pickLocaleId(['vie-XX'], VoiceLocale.vi), isNull);
    });
  });

  group('localeIdOrPreferred', () {
    test('the picked id when the phone lists the language', () {
      expect(localeIdOrPreferred(['vi_VN', 'en_US'], VoiceLocale.vi), 'vi_VN');
      expect(localeIdOrPreferred(['en-GB'], VoiceLocale.en), 'en-GB');
    });

    test('the preferred id when the list is empty or lacks the language (Android 13+ on-device list)', () {
      expect(localeIdOrPreferred([], VoiceLocale.vi), 'vi-VN');
      expect(localeIdOrPreferred(['en_US'], VoiceLocale.vi), 'vi-VN');
    });

    test('the preferred id when the locales could not be read (timeout or error)', () {
      expect(localeIdOrPreferred(null, VoiceLocale.en), 'en-US');
    });
  });

  group('speechErrorKind', () {
    test('maps the platform error names', () {
      expect(speechErrorKind('error_insufficient_permissions'), SpeechErrorKind.noPermission);
      expect(speechErrorKind('error_permission'), SpeechErrorKind.noPermission);
      expect(speechErrorKind('error_network'), SpeechErrorKind.network);
      expect(speechErrorKind('error_network_timeout'), SpeechErrorKind.network);
      expect(speechErrorKind('error_server'), SpeechErrorKind.network);
      expect(speechErrorKind('error_server_disconnected'), SpeechErrorKind.network);
      expect(speechErrorKind('error_no_match'), SpeechErrorKind.noMatch);
      expect(speechErrorKind('error_speech_timeout'), SpeechErrorKind.noMatch);
      expect(speechErrorKind('error_language_not_supported'), SpeechErrorKind.localeUnavailable);
      expect(speechErrorKind('error_language_unavailable'), SpeechErrorKind.localeUnavailable);
      expect(speechErrorKind('error_audio_error'), SpeechErrorKind.interrupted);
      // iOS (SpeechToTextPlugin.swift).
      expect(speechErrorKind('error_retry'), SpeechErrorKind.network);
      expect(speechErrorKind('error_speech_recognizer_connection_invalidated'), SpeechErrorKind.network);
      expect(speechErrorKind('error_speech_recognizer_connection_interrupted'), SpeechErrorKind.network);
      expect(speechErrorKind('error_assets_not_installed'), SpeechErrorKind.localeUnavailable);
      expect(speechErrorKind('error_speech_recognizer_disabled'), SpeechErrorKind.unsupported);
      expect(speechErrorKind('error_busy'), SpeechErrorKind.other);
      expect(speechErrorKind('error_listen_failed'), SpeechErrorKind.other);
      expect(speechErrorKind('something new'), SpeechErrorKind.other);
    });
  });
}
