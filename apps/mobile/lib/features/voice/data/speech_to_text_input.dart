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

/// The id to listen with: the phone's own id for the language when [available] lists it, else
/// [VoiceLocale.preferredLocaleId] — also when the list could not be read (null). Android 13+ lists
/// only on-device languages, yet the cloud recognizer may still know the language; when it does
/// not, the listen fails with a language error and the chip is marked then.
String localeIdOrPreferred(Iterable<String>? available, VoiceLocale locale) =>
    (available == null ? null : pickLocaleId(available, locale)) ?? locale.preferredLocaleId;

/// The plugin reports Android `SpeechRecognizer` error names and the iOS ones of
/// `SpeechToTextPlugin.swift` as strings.
SpeechErrorKind speechErrorKind(String errorMsg) => switch (errorMsg) {
  'error_insufficient_permissions' || 'error_permission' => SpeechErrorKind.noPermission,
  'error_network' ||
  'error_network_timeout' ||
  'error_server' ||
  'error_server_disconnected' ||
  'error_retry' ||
  'error_speech_recognizer_connection_invalidated' ||
  'error_speech_recognizer_connection_interrupted' => SpeechErrorKind.network,
  'error_no_match' || 'error_speech_timeout' => SpeechErrorKind.noMatch,
  'error_language_not_supported' ||
  'error_language_unavailable' ||
  'error_assets_not_installed' => SpeechErrorKind.localeUnavailable,
  'error_speech_recognizer_disabled' => SpeechErrorKind.unsupported,
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

  /// On iOS the plugin cannot fall back from on-device to the cloud within one listen, so iOS asks
  /// Apple's recognizer directly and lets it choose.
  @override
  bool get tryOnDeviceFirst => defaultTargetPlatform == TargetPlatform.android;

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

  /// Never null: a language the phone does not list is still tried (see [localeIdOrPreferred]).
  /// On Android 13+ the plugin may never answer `locales()`, hence the timeout.
  @override
  Future<String?> resolveLocale(VoiceLocale locale) async {
    Iterable<String>? available;
    try {
      final locales = await _speech.locales().timeout(const Duration(seconds: 2));
      available = locales.map((l) => l.localeId);
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput locales error: ${error.runtimeType}');
    }
    return localeIdOrPreferred(available, locale);
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
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput stop error: ${error.runtimeType}');
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (error) {
      if (kDebugMode) debugPrint('SpeechToTextInput cancel error: ${error.runtimeType}');
    }
  }

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
