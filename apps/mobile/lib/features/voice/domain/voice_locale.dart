/// The two languages the composer listens in (voice spec V2). The keywords belong to one language
/// each: "send" said while listening in Vietnamese is just a word.
enum VoiceLocale {
  vi(languageCode: 'vi', preferredLocaleId: 'vi-VN', sendWords: {'gửi'}, cancelWords: {'huỷ', 'hủy'}),
  en(languageCode: 'en', preferredLocaleId: 'en-US', sendWords: {'send'}, cancelWords: {'cancel'});

  const VoiceLocale({
    required this.languageCode,
    required this.preferredLocaleId,
    required this.sendWords,
    required this.cancelWords,
  });

  final String languageCode;

  /// The recognizer locale to pick when the phone offers several for [languageCode].
  final String preferredLocaleId;

  /// Lower case; compared with the lower-cased last word (spec §3.2).
  final Set<String> sendWords;
  final Set<String> cancelWords;

  /// The app is Vietnamese or English; anything that is not Vietnamese listens in English.
  static VoiceLocale fromLanguageCode(String? code) => code == 'vi' ? vi : en;
}
