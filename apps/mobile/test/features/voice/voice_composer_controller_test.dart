// apps/mobile/test/features/voice/voice_composer_controller_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';

void main() {
  late FakeSpeechInput speech;
  late AppSettings settings;
  late VoiceComposerController voice;
  late List<String> sent;
  late bool live;

  setUp(() async {
    getIt.registerSingleton<PopupHandler>(FakePopupHandler());
    speech = FakeSpeechInput();
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    voice = VoiceComposerController(speech, settings);
    sent = [];
    live = true;
    voice.attach(canSend: () => live, onSubmit: sent.add);
  });

  tearDown(() async {
    voice.dispose();
    await getIt.reset();
  });

  Future<void> listen({String app = 'vi'}) async {
    await voice.toggleMic(app);
    speech.emit(const SpeechListening(true));
  }

  test('first tap opens, listens in the app language, on-device first', () async {
    await listen();
    expect(voice.phase.value, VoicePhase.listening);
    expect(voice.locale.value, VoiceLocale.vi);
    expect(speech.starts.single, (localeId: 'vi-VN', onDevice: true));
  });

  test('a chosen language wins over the app language', () async {
    await settings.setVoiceLocale(VoiceLocale.en);
    await listen(app: 'vi');
    expect(speech.starts.single.localeId, 'en-US');
  });

  test('partials show after the text already there; the final replaces them', () async {
    voice.text.text = 'cd app';
    await listen();
    speech.emit(const SpeechPartial('và chạy'));
    expect(voice.text.text, 'cd app và chạy');
    speech.emit(const SpeechPartial('và chạy test'));
    expect(voice.text.text, 'cd app và chạy test');
    speech.emit(const SpeechFinal('và chạy test'));
    speech.emit(const SpeechListening(false));
    expect(voice.text.text, 'cd app và chạy test');
    expect(voice.phase.value, VoicePhase.idle);
    expect(sent, isEmpty);
  });

  test('a trailing "gửi" sends the whole composer and clears it', () async {
    voice.text.text = 'sửa bug';
    await listen();
    speech.emit(const SpeechFinal('trong auth gửi'));
    expect(sent, ['sửa bug trong auth']);
    expect(voice.text.text, isEmpty);
    expect(voice.phase.value, isNot(VoicePhase.closed));
  });

  test('"gửi" alone on an empty composer sends an empty line', () async {
    await listen();
    speech.emit(const SpeechFinal('gửi'));
    expect(sent, ['']);
  });

  test('"huỷ" clears without sending', () async {
    voice.text.text = 'rm -rf build';
    await listen();
    speech.emit(const SpeechFinal('thôi huỷ'));
    expect(sent, isEmpty);
    expect(voice.text.text, isEmpty);
  });

  test('not live: "gửi" keeps the text (keyword dropped) and sends nothing', () async {
    live = false;
    await listen();
    speech.emit(const SpeechFinal('chạy test gửi'));
    expect(sent, isEmpty);
    expect(voice.text.text, 'chạy test');
  });

  test('a final that arrives after done still applies', () async {
    await listen();
    speech.emit(const SpeechListening(false));
    speech.emit(const SpeechFinal('git status gửi'));
    expect(sent, ['git status']);
  });

  test('tap while listening stops (the final result still comes)', () async {
    await listen();
    await voice.toggleMic('vi');
    expect(speech.stops, 1);
    expect(speech.starts, hasLength(1));
  });

  test('double tap while permission is pending starts one listen (review focus 4)', () async {
    speech.permissionGate = Completer<void>();
    final first = voice.toggleMic('vi');
    final second = voice.toggleMic('vi');
    speech.permissionGate!.complete();
    await Future.wait([first, second]);
    expect(speech.permissionCalls, 1);
    expect(speech.starts, hasLength(1));
  });

  test('permission refused: open, idle, noPermission, no listen', () async {
    speech.permission = SpeechPermission.denied;
    await voice.toggleMic('vi');
    expect(voice.phase.value, VoicePhase.idle);
    expect(voice.issue.value, VoiceIssue.noPermission);
    expect(speech.starts, isEmpty);
  });

  test('no recognizer on the phone: unsupported', () async {
    speech.permission = SpeechPermission.unsupported;
    await voice.toggleMic('vi');
    expect(voice.issue.value, VoiceIssue.unsupported);
  });

  test('language missing on the phone: localeUnavailable and the chip is marked', () async {
    speech.localeIds = {VoiceLocale.vi: null, VoiceLocale.en: 'en-US'};
    await voice.toggleMic('vi');
    expect(voice.issue.value, VoiceIssue.localeUnavailable);
    expect(voice.unavailable.value, {VoiceLocale.vi});
    expect(speech.starts, isEmpty);
  });

  test('on-device failure before any words retries once with the cloud recognizer', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    expect(speech.starts, [(localeId: 'vi-VN', onDevice: true), (localeId: 'vi-VN', onDevice: false)]);
    expect(voice.phase.value, VoicePhase.listening);
    expect(voice.issue.value, isNull);
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    expect(speech.starts, hasLength(2));
    expect(voice.issue.value, VoiceIssue.localeUnavailable);
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('network error keeps the text and says so', () async {
    voice.text.text = 'giữ lại';
    await listen();
    speech.emit(const SpeechPartial('chữ'));
    speech.emit(const SpeechFailed(SpeechErrorKind.network));
    expect(voice.issue.value, VoiceIssue.network);
    expect(voice.text.text, 'giữ lại chữ');
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('no match is quiet', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.noMatch));
    expect(voice.issue.value, isNull);
    expect(voice.phase.value, VoicePhase.idle);
  });

  test('switching language while listening cancels and remembers the choice', () async {
    await listen();
    await voice.setLocale(VoiceLocale.en);
    expect(speech.cancels, 1);
    expect(voice.phase.value, VoicePhase.idle);
    expect(settings.voiceLocale.value, VoiceLocale.en);
    await voice.toggleMic('vi');
    expect(speech.starts.last.localeId, 'en-US');
  });

  test('Send button sends the trimmed text, gated on live', () async {
    voice.text.text = '  git log  \n';
    live = false;
    voice.sendNow();
    expect(sent, isEmpty);
    live = true;
    voice.sendNow();
    expect(sent, ['git log']);
    expect(voice.text.text, isEmpty);
  });

  test('pause cancels the listen and keeps what was heard; later results are ignored', () async {
    await listen();
    speech.emit(const SpeechPartial('nửa câu'));
    voice.pause();
    expect(speech.cancels, 1);
    expect(voice.phase.value, VoicePhase.idle);
    speech.emit(const SpeechFinal('nửa câu gửi'));
    expect(sent, isEmpty);
    expect(voice.text.text, 'nửa câu');
  });

  test('close clears and ignores late results (review focus 3)', () async {
    await listen();
    voice.close();
    expect(voice.phase.value, VoicePhase.closed);
    expect(voice.text.text, isEmpty);
    speech.emit(const SpeechFinal('muộn gửi'));
    expect(sent, isEmpty);
  });

  test('results after dispose write nothing and send nothing (review focus 3)', () async {
    await listen();
    voice.dispose();
    expect(speech.cancels, 1);
    speech.emit(const SpeechFinal('muộn gửi'));
    expect(sent, isEmpty);
    // tearDown disposes again: dispose must be idempotent.
  });

  test('a listen that ended with done and no result is replaced by the next mic tap', () async {
    await listen();
    speech.emit(const SpeechListening(false));
    await voice.toggleMic('vi');
    expect(speech.cancels, 1);
    expect(speech.starts, hasLength(2));
    expect(voice.phase.value, VoicePhase.listening);
  });

  test('the old listen\'s done after the cloud retry started does not end the new listen', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    speech.emit(const SpeechListening(false));
    expect(voice.phase.value, VoicePhase.listening);
    speech.emit(const SpeechFinal('x gửi'));
    expect(sent, ['x']);
  });

  test('after the retry, the started status brings the phase back to listening', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.localeUnavailable));
    speech.emit(const SpeechListening(true));
    expect(voice.phase.value, VoicePhase.listening);
    speech.emit(const SpeechListening(false));
    expect(voice.phase.value, VoicePhase.idle);
  });
}
