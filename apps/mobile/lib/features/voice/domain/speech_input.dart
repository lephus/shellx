import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

enum SpeechPermission {
  granted,

  /// The user refused the microphone or speech recognition prompt (now or earlier).
  denied,

  /// The phone has no speech recognizer at all (e.g. an Android build without one).
  unsupported,
}

enum SpeechErrorKind {
  noPermission,
  localeUnavailable,
  network,
  noMatch,
  interrupted,

  /// Speech recognition is turned off on the phone (iOS Settings → Siri, or a restriction).
  unsupported,
  other,
}

/// What the recognizer reports while the composer listens (voice spec §4.1).
sealed class SpeechEvent {
  const SpeechEvent();
}

/// The words so far; replaced by the next partial or by the final result.
final class SpeechPartial extends SpeechEvent {
  const SpeechPartial(this.text);

  final String text;
}

/// The whole utterance; the listen is over once this arrives.
final class SpeechFinal extends SpeechEvent {
  const SpeechFinal(this.text);

  final String text;
}

final class SpeechFailed extends SpeechEvent {
  const SpeechFailed(this.kind);

  final SpeechErrorKind kind;
}

/// `true` when the recognizer started hearing, `false` when the listen is fully over.
final class SpeechListening extends SpeechEvent {
  const SpeechListening(this.listening);

  final bool listening;
}

/// The OS speech recognizer, behind an interface so the composer is tested without a microphone.
abstract interface class SpeechInput {
  /// Broadcast: every event of every listen.
  Stream<SpeechEvent> get events;

  /// Whether the first listen should ask for on-device recognition (a failure before any words is
  /// then retried with the cloud recognizer).
  bool get tryOnDeviceFirst;

  /// Asks for the microphone and speech recognition permissions the first time.
  Future<SpeechPermission> ensurePermission();

  /// The recognizer's locale id for [locale], or null when the phone cannot recognize it.
  Future<String?> resolveLocale(VoiceLocale locale);

  /// One listen; it ends on its own after 2 s of silence or 60 s.
  Future<void> start(String localeId, {required bool onDevice});

  /// Ends the listen; the final result still arrives.
  Future<void> stop();

  /// Ends the listen without a final result.
  Future<void> cancel();
}
