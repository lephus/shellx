import 'dart:async';

import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_command_parser.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart'
    show VoiceIssue, VoicePhase;

/// V2-2b B14: speaking into the text field of an AI session. What is heard shows after the text already in the
/// field (each partial result replaces the last one) and the final result stays there, where it can be edited.
/// "gửi" / "send" as the last word sends the field when the session can take it, else the words just stay;
/// "huỷ" / "cancel" as the last word drops what was just said and nothing else (ruling R9: what was typed is never
/// cleared by voice). It listens in the language of the terminal's voice composer (Settings, else the app's), and
/// stops when the page says so: the session is not live or closed, the page leaves, the app is not in front.
///
/// One listen at a time. A listen is "active" from [SpeechInput.start] until its final result, an error or [stop];
/// what any other listen reports is ignored, so a late result never reaches a field it was not meant for.
///
/// A user edit ends the listen (F41): the dictation remembers the text it last showed, and a field that differs from
/// it when the listen next reports was typed in. The listen is cancelled, the field stays exactly as the user left it,
/// and nothing that listen hears afterwards (words, "gửi", "huỷ") touches or sends it. Nothing heard is ever logged.
@injectable
class AiDictation {
  AiDictation(this._speech, this._settings) {
    _events = _speech.events.listen(_onEvent);
  }

  final SpeechInput _speech;
  final AppSettings _settings;
  late final StreamSubscription<SpeechEvent> _events;

  final Signal<VoicePhase> _phase = signal(VoicePhase.idle);
  final Signal<VoiceIssue?> _issue = signal(null);
  final Signal<VoiceLocale> _locale = signal(VoiceLocale.vi);

  TextEditingController? _text;
  bool Function() _canSend = () => false;
  void Function() _onSend = () {};

  /// The field's text when the listen started (trimmed); what is heard goes after it.
  String _committed = '';

  /// The field's text as this listen last left it (as it was when the listen began, untrimmed): a field that differs
  /// was typed in by the user (F41).
  String _shown = '';
  String? _localeId;
  bool _active = false;
  bool _starting = false;
  bool _onDeviceAttempt = false;
  bool _heard = false;

  /// This listen has shown it started (status, partial or final): an earlier listen's late `done` must not end it.
  bool _started = false;

  /// [stop] came while a listen was being set up (permission, locale): it does not start, but what the system answered
  /// (a refusal, a language the phone lacks) is still said (F40). Cleared by [toggle].
  bool _stopped = false;
  bool _disposed = false;

  /// [VoicePhase.listening] while the microphone is on, else [VoicePhase.idle] (never `closed`: the AI field is
  /// always there).
  ReadonlySignal<VoicePhase> get phase => _phase;

  /// Why the last listen could not start or ended early; null once a new one starts.
  ReadonlySignal<VoiceIssue?> get issue => _issue;

  /// The language of the last listen (it words [VoiceIssue.localeUnavailable]).
  ReadonlySignal<VoiceLocale> get locale => _locale;

  /// [text] is the field heard words go to; [canSend] says whether the session can take a message now (and there
  /// is one); [onSend] sends the field as the Send button does.
  void attach({
    required TextEditingController text,
    required bool Function() canSend,
    required void Function() onSend,
  }) {
    _text = text;
    _canSend = canSend;
    _onSend = onSend;
  }

  /// The mic: listens; while listening, stops (the final result still comes and is applied).
  Future<void> toggle(String appLanguageCode) async {
    if (_disposed || _text == null) return;
    _stopped = false;
    if (_phase.peek() == VoicePhase.listening) {
      await _speech.stop();
      return;
    }
    _locale.value = _settings.voiceLocale.peek() ?? VoiceLocale.fromLanguageCode(appLanguageCode);
    await _start();
  }

  /// Stops hearing now, keeping what the field shows; a listen still being set up does not start.
  void stop() {
    if (_disposed) return;
    _stopped = true;
    if (_active) _cancelListen();
  }

  Future<void> _start() async {
    if (_starting) return;
    // `done` without a final result leaves a drained listen: drop it, then start afresh.
    if (_active) _cancelListen();
    _starting = true;
    try {
      _issue.value = null;
      final permission = await _speech.ensurePermission();
      if (_disposed) return;
      if (permission != SpeechPermission.granted) {
        _issue.value = permission == SpeechPermission.denied ? VoiceIssue.noPermission : VoiceIssue.unsupported;
        return;
      }
      final localeId = await _speech.resolveLocale(_locale.peek());
      if (_disposed) return;
      if (localeId == null) {
        _issue.value = VoiceIssue.localeUnavailable;
        return;
      }
      // F40: the system's prompt takes the app out of the front, and the page stops the dictation then. That stop ends
      // the setup only here, after what was answered (a refusal, a language the phone lacks) has been said above.
      if (_stopped) return;
      _localeId = localeId;
      _committed = _text!.text.trim();
      _shown = _text!.text;
      _heard = false;
      _started = false;
      _onDeviceAttempt = _speech.tryOnDeviceFirst;
      _active = true;
      _phase.value = VoicePhase.listening;
      await _speech.start(localeId, onDevice: _onDeviceAttempt);
    } finally {
      _starting = false;
    }
  }

  void _onEvent(SpeechEvent event) {
    if (_disposed || !_active) return;
    // F41: a field that is not what this listen last showed was typed in. The listen is over, whatever it reports, and
    // the field stays as the user left it.
    if (_text?.text != _shown) {
      _cancelListen();
      return;
    }
    switch (event) {
      case SpeechPartial(:final text):
        _heard = true;
        _started = true;
        _show(_join(_committed, text));
      case SpeechFinal(:final text):
        _heard = true;
        _started = true;
        _active = false;
        _phase.value = VoicePhase.idle;
        _apply(VoiceCommandParser.parse(text, _locale.peek()));
      case SpeechFailed(:final kind):
        _onFailed(kind);
      case SpeechListening(:final listening):
        if (listening) {
          _started = true;
          _phase.value = VoicePhase.listening;
        } else if (_started) {
          // `done` may come before the final result: the listen stays active for it.
          _phase.value = VoicePhase.idle;
        }
    }
  }

  void _apply(VoiceCommand command) {
    switch (command) {
      case VoiceAppend(:final text):
        _show(_join(_committed, text));
      case VoiceCancel():
        // R9: only what was just said goes.
        _show(_committed);
      case VoiceSend(:final text):
        _show(_join(_committed, text));
        if (_canSend()) _onSend();
    }
    _committed = _text?.text.trim() ?? '';
  }

  /// Voice spec V4: on-device first where the recognizer can fall back ([SpeechInput.tryOnDeviceFirst]); a phone
  /// that cannot do it on the device fails before any words, and gets one more try with the OS cloud recognizer.
  void _onFailed(SpeechErrorKind kind) {
    final retry =
        _onDeviceAttempt && !_heard && (kind == SpeechErrorKind.localeUnavailable || kind == SpeechErrorKind.other);
    if (retry) {
      _onDeviceAttempt = false;
      _started = false;
      unawaited(_speech.start(_localeId!, onDevice: false));
      return;
    }
    _active = false;
    _phase.value = VoicePhase.idle;
    _committed = _text?.text.trim() ?? '';
    _issue.value = switch (kind) {
      SpeechErrorKind.noPermission => VoiceIssue.noPermission,
      SpeechErrorKind.unsupported => VoiceIssue.unsupported,
      SpeechErrorKind.localeUnavailable => VoiceIssue.localeUnavailable,
      SpeechErrorKind.network => VoiceIssue.network,
      SpeechErrorKind.other => VoiceIssue.failed,
      SpeechErrorKind.noMatch || SpeechErrorKind.interrupted => null,
    };
  }

  void _cancelListen() {
    _active = false;
    unawaited(_speech.cancel());
    _committed = _text?.text.trim() ?? '';
    _phase.value = VoicePhase.idle;
  }

  void _show(String value) {
    final text = _text;
    if (text == null) return;
    _shown = value;
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  static String _join(String before, String after) =>
      [before.trim(), after.trim()].where((part) => part.isNotEmpty).join(' ');

  void dispose() {
    if (_disposed) return;
    if (_active) {
      _active = false;
      unawaited(_speech.cancel());
    }
    _disposed = true;
    unawaited(_events.cancel());
    _phase.dispose();
    _issue.dispose();
    _locale.dispose();
  }
}
