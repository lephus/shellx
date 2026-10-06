import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// [locale]'s preferred id if the phone has it, else any id of the same language; ids come as
/// `vi-VN` (iOS) or `vi_VN` (Android).
String? pickLocaleId(Iterable<String> available, VoiceLocale locale) {
  String norm(String id) => id.toLowerCase().replaceAll('_', '-');
  final preferred = norm(locale.preferredLocaleId);
  String? sameLanguage;
  for (final id in available) {
    final n = norm(id);
    if (n == preferred) return id;
    if (sameLanguage == null && (n == locale.languageCode || n.startsWith('${locale.languageCode}-'))) {
      sameLanguage = id;
    }
  }
  return sameLanguage;
}

/// The plugin reports Android `SpeechRecognizer` error names and a few iOS ones as strings.
SpeechErrorKind speechErrorKind(String errorMsg) => switch (errorMsg) {
  'error_insufficient_permissions' || 'error_permission' => SpeechErrorKind.noPermission,
  'error_network' || 'error_network_timeout' || 'error_server' || 'error_server_disconnected' =>
    SpeechErrorKind.network,
  'error_no_match' || 'error_speech_timeout' => SpeechErrorKind.noMatch,
  'error_language_not_supported' || 'error_language_unavailable' => SpeechErrorKind.localeUnavailable,
  'error_audio_error' => SpeechErrorKind.interrupted,
  _ => SpeechErrorKind.other,
};

/// [SpeechInput] over `speech_to_text` (voice spec V4, V7). Only names of errors are logged, never
/// what was said.
@LazySingleton(as: SpeechInput)
class SpeechToTextInput implements SpeechInput {
  final SpeechToText _speech = SpeechToText();
  final StreamController<SpeechEvent> _events = StreamController<SpeechEvent>.broadcast();
  bool _ready = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechPermission> ensurePermission() async {
    try {
      // The first call shows the microphone and speech recognition prompts.
      if (!_ready) _ready = await _speech.initialize(onError: _onError, onStatus: _onStatus);
      if (_ready) return SpeechPermission.granted;
      return await _speech.hasPermission ? SpeechPermission.unsupported : SpeechPermission.denied;
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput init error: ${error.runtimeType}');
      return SpeechPermission.denied;
    }
  }

  @override
  Future<String?> resolveLocale(VoiceLocale locale) async {
    try {
      final locales = await _speech.locales();
      return pickLocaleId(locales.map((l) => l.localeId), locale);
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput locales error: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> start(String localeId, {required bool onDevice}) async {
    try {
      // In 7.4.0 listenFor, pauseFor and localeId are deprecated as arguments of listen(); they
      // live in SpeechListenOptions.
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 60),
          partialResults: true,
          onDevice: onDevice,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput listen error: ${error.runtimeType}');
      _events.add(const SpeechFailed(SpeechErrorKind.other));
    }
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  void _onResult(SpeechRecognitionResult result) {
    _events.add(result.finalResult ? SpeechFinal(result.recognizedWords) : SpeechPartial(result.recognizedWords));
  }

  void _onError(SpeechRecognitionError error) {
    if (kDebugMode) debugPrint('SpeechToTextInput error: ${error.errorMsg}');
    _events.add(SpeechFailed(speechErrorKind(error.errorMsg)));
  }

  /// `notListening` comes before the final result; only `done` means the listen is over.
  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) _events.add(const SpeechListening(true));
    if (status == SpeechToText.doneStatus) _events.add(const SpeechListening(false));
  }
}
