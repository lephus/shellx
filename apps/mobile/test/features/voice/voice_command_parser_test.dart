import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/features/voice/domain/voice_command_parser.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

void main() {
  group('VoiceCommandParser, Vietnamese', () {
    const vi = VoiceLocale.vi;

    test('a trailing "gửi" sends the words before it', () {
      expect(VoiceCommandParser.parse('chạy test gửi', vi), const VoiceSend('chạy test'));
    });

    test('capital letter and trailing punctuation still send (review focus 5)', () {
      expect(VoiceCommandParser.parse('Chạy test. Gửi.', vi), const VoiceSend('Chạy test'));
      expect(VoiceCommandParser.parse('Gửi!', vi), const VoiceSend(''));
    });

    test('"gửi" alone sends an empty line (just Enter)', () {
      expect(VoiceCommandParser.parse('gửi', vi), const VoiceSend(''));
      expect(VoiceCommandParser.parse('  gửi  ', vi), const VoiceSend(''));
    });

    test('"gửi" that is not the last word is text', () {
      expect(VoiceCommandParser.parse('gửi email cho tôi', vi), const VoiceAppend('gửi email cho tôi'));
    });

    test('both spellings of "huỷ" cancel', () {
      expect(VoiceCommandParser.parse('xoá hết đi huỷ', vi), const VoiceCancel());
      expect(VoiceCommandParser.parse('Hủy.', vi), const VoiceCancel());
    });

    test('English keywords are text in Vietnamese', () {
      expect(VoiceCommandParser.parse('git status send', vi), const VoiceAppend('git status send'));
    });

    test('plain text is appended trimmed', () {
      expect(
        VoiceCommandParser.parse('  sửa bug trong auth service ', vi),
        const VoiceAppend('sửa bug trong auth service'),
      );
    });

    test('empty input appends nothing', () {
      expect(VoiceCommandParser.parse('   ', vi), const VoiceAppend(''));
    });
  });

  group('VoiceCommandParser, English', () {
    const en = VoiceLocale.en;

    test('"send" after a comma sends the words before it (review focus 5)', () {
      expect(VoiceCommandParser.parse('run tests, send', en), const VoiceSend('run tests'));
      expect(VoiceCommandParser.parse('Run tests. Send.', en), const VoiceSend('Run tests'));
    });

    test('"cancel" cancels', () {
      expect(VoiceCommandParser.parse('never mind cancel', en), const VoiceCancel());
    });

    test('Vietnamese keywords are text in English', () {
      expect(VoiceCommandParser.parse('hello gửi', en), const VoiceAppend('hello gửi'));
    });
  });

  test('VoiceLocale.fromLanguageCode: vi is Vietnamese, anything else English', () {
    expect(VoiceLocale.fromLanguageCode('vi'), VoiceLocale.vi);
    expect(VoiceLocale.fromLanguageCode('en'), VoiceLocale.en);
    expect(VoiceLocale.fromLanguageCode(null), VoiceLocale.en);
    expect(VoiceLocale.vi.preferredLocaleId, 'vi-VN');
    expect(VoiceLocale.en.preferredLocaleId, 'en-US');
  });
}
