import 'dart:async';

import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart' show DraftHolder;
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_command_parser.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

enum VoicePhase { closed, idle, listening }

/// What the composer's issue line says (voice spec §5); `noMatch` and interruptions say nothing.
enum VoiceIssue { noPermission, unsupported, localeUnavailable, network, failed }

/// The voice composer of the terminal page (voice spec §3, §4.1): what was heard lands in [text],
/// where it can be edited; a trailing send keyword or the Send button hands the line to the page.
///
/// One listen at a time. A listen is "active" from [SpeechInput.start] until its final result, an
/// error, [pause], [close] or [dispose]; partials and the final result of anything else are
/// ignored, so a late result never reaches a closed composer or a page that left.
@injectable
class VoiceComposerController extends Controller {
  VoiceComposerController(this._speech, this._settings) {
    _events = _speech.events.listen(_onEvent);
    // An assignment to a String, kept in memory only (a draft may hold a password): no debounce needed.
    text.addListener(_saveDraft);
  }

  final SpeechInput _speech;
  final AppSettings _settings;
  late final StreamSubscription<SpeechEvent> _events;

  final TextEditingController text = TextEditingController();
  final Signal<VoicePhase> _phase = signal(VoicePhase.closed);
  final Signal<VoiceIssue?> _issue = signal(null);
  final Signal<VoiceLocale> _locale = signal(VoiceLocale.vi);
  final Signal<Set<VoiceLocale>> _unavailable = signal(const {});

  bool Function() _canSend = () => false;
  void Function(String line) _onSubmit = (_) {};

  /// The composer text when the listen started; partials are shown after it.
  String _committed = '';
  String? _localeId;
  bool _active = false;
  bool _starting = false;
  bool _onDeviceAttempt = false;
  bool _heard = false;

  /// [pause] came while a listen was being set up: do not start it. Cleared by the next mic tap.
  bool _paused = false;

  /// This listen has shown it started (status, partial or final): an earlier listen's late `done` must
  /// not end it.
  bool _started = false;
  bool _disposed = false;

  ReadonlySignal<VoicePhase> get phase => _phase;
  ReadonlySignal<VoiceIssue?> get issue => _issue;
  ReadonlySignal<VoiceLocale> get locale => _locale;
  ReadonlySignal<Set<VoiceLocale>> get unavailable => _unavailable;

  DraftHolder? _draft;

  /// A11 D29: the composer shows the draft of the terminal in front. The text typed so far is kept in
  /// the holder of the terminal being left; [holder] null (no tab) leaves a plain composer. Partial
  /// speech belongs to the previous terminal and is dropped.
  void useDraft(DraftHolder? holder) {
    if (_disposed || identical(holder, _draft)) return;
    _saveDraft();
    _draft = holder;
    _committed = '';
    if (_active) _cancelListen();
    text.text = holder?.value ?? '';
  }

  void _saveDraft() {
    _draft?.value = text.text;
    _hasDraft.value = text.text.isNotEmpty;
  }

  final Signal<bool> _hasDraft = signal(false);

  /// The composer holds text (this terminal's draft); with the composer closed the mic says so.
  ReadonlySignal<bool> get hasDraft => _hasDraft;

  /// [canSend]: the active tab is live. [onSubmit]: sends one line with Enter.
  void attach({required bool Function() canSend, required void Function(String line) onSubmit}) {
    _canSend = canSend;
    _onSubmit = onSubmit;
  }

  /// The mic: opens the composer and listens; while listening, stops (the final result still
  /// comes and is applied).
  Future<void> toggleMic(String appLanguageCode) async {
    if (_disposed) return;
    _paused = false;
    if (_phase.peek() == VoicePhase.listening) {
      await _speech.stop();
      return;
    }
    if (_phase.peek() == VoicePhase.closed) {
      _locale.value = _settings.voiceLocale.peek() ?? VoiceLocale.fromLanguageCode(appLanguageCode);
      // A language marked earlier gets another try (the phone may have it by now).
      _unavailable.value = const {};
      _phase.value = VoicePhase.idle;
    }
    await _startListening();
  }

  Future<void> setLocale(VoiceLocale locale) async {
    if (_disposed) return;
    if (_active) _cancelListen();
    _locale.value = locale;
    _issue.value = null;
    await _settings.setVoiceLocale(locale);
  }

  /// The Send button: the text as edited, without surrounding blank space (a trailing newline
  /// would be a second Enter).
  void sendNow() {
    if (_disposed || !_canSend()) return;
    if (_active) _cancelListen();
    final line = text.text.trim();
    text.clear();
    _committed = '';
    _onSubmit(line);
  }

  /// The app went inactive (call, lock, background): stop hearing, keep what is shown. A listen
  /// still being set up (permission, locale) does not start.
  void pause() {
    if (_disposed) return;
    _paused = true;
    if (_active) _cancelListen();
  }

  /// ✕: nothing is sent; the next mic tap opens an empty composer.
  void close() {
    if (_disposed) return;
    if (_active) _cancelListen();
    text.clear();
    _committed = '';
    _issue.value = null;
    _phase.value = VoicePhase.closed;
  }

  Future<void> _startListening() async {
    if (_starting) return;
    // `done` without a result leaves a drained listen: drop it, then start fresh.
    if (_active) {
      if (_phase.peek() == VoicePhase.listening) return;
      _cancelListen();
    }
    _starting = true;
    try {
      _issue.value = null;
      final permission = await _speech.ensurePermission();
      if (_disposed || _phase.peek() == VoicePhase.closed) return;
      if (permission != SpeechPermission.granted) {
        _issue.value = permission == SpeechPermission.denied ? VoiceIssue.noPermission : VoiceIssue.unsupported;
        return;
      }
      final locale = _locale.peek();
      final localeId = await _speech.resolveLocale(locale);
      if (_disposed || _phase.peek() == VoicePhase.closed) return;
      if (localeId == null) {
        _markUnavailable(locale);
        return;
      }
      if (_paused) return;
      _localeId = localeId;
      _committed = text.text.trim();
      _heard = false;
      _onDeviceAttempt = _speech.tryOnDeviceFirst;
      _started = false;
      _active = true;
      _phase.value = VoicePhase.listening;
      await _speech.start(localeId, onDevice: _onDeviceAttempt);
    } finally {
      _starting = false;
    }
  }

  void _onEvent(SpeechEvent event) {
    if (_disposed || !_active) return;
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
          // `done` may come before the final result: keep the listen active for it.
          _phase.value = VoicePhase.idle;
        }
    }
  }

  void _apply(VoiceCommand command) {
    switch (command) {
      case VoiceAppend(:final text):
        _show(_join(_committed, text));
      case VoiceCancel():
        text.clear();
      case VoiceSend(:final text):
        final line = _join(_committed, text);
        if (_canSend()) {
          this.text.clear();
          _onSubmit(line);
        } else {
          _show(line);
        }
    }
    _committed = text.text;
  }

  /// Spec V4: on-device first where the recognizer can fall back ([SpeechInput.tryOnDeviceFirst]);
  /// a phone that cannot do it on the device fails before any words, and gets one more try with the
  /// OS cloud recognizer.
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
    _committed = text.text;
    switch (kind) {
      case SpeechErrorKind.noPermission:
        _issue.value = VoiceIssue.noPermission;
      case SpeechErrorKind.unsupported:
        _issue.value = VoiceIssue.unsupported;
      case SpeechErrorKind.localeUnavailable:
        _markUnavailable(_locale.peek());
      case SpeechErrorKind.network:
        _issue.value = VoiceIssue.network;
      case SpeechErrorKind.other:
        _issue.value = VoiceIssue.failed;
      case SpeechErrorKind.noMatch || SpeechErrorKind.interrupted:
        break;
    }
  }

  void _markUnavailable(VoiceLocale locale) {
    _unavailable.value = {..._unavailable.peek(), locale};
    _issue.value = VoiceIssue.localeUnavailable;
  }

  void _cancelListen() {
    _active = false;
    unawaited(_speech.cancel());
    _committed = text.text;
    _phase.value = VoicePhase.idle;
  }

  void _show(String value) {
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  static String _join(String before, String after) =>
      [before.trim(), after.trim()].where((part) => part.isNotEmpty).join(' ');

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_active) {
      _active = false;
      unawaited(_speech.cancel());
    }
    unawaited(_events.cancel());
    text.removeListener(_saveDraft);
    text.dispose();
    _phase.dispose();
    _issue.dispose();
    _locale.dispose();
    _unavailable.dispose();
    _hasDraft.dispose();
  }
}
