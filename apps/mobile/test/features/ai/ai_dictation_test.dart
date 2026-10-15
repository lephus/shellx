import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_dictation.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart'
    show VoiceIssue, VoicePhase;

import '../../support/fake_speech.dart';

/// V2-2b B14: speaking into the AI composer.
void main() {
  late FakeSpeechInput speech;
  late AppSettings settings;
  late AiDictation dictation;
  late TextEditingController field;
  late int sends;
  late bool canSend;

  setUp(() async {
    speech = FakeSpeechInput();
    settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    dictation = AiDictation(speech, settings);
    field = TextEditingController();
    sends = 0;
    canSend = true;
    dictation.attach(text: field, canSend: () => canSend, onSend: () => sends++);
  });

  tearDown(() {
    dictation.dispose();
    field.dispose();
  });

  Future<void> listen({String app = 'vi'}) async {
    await dictation.toggle(app);
    speech.emit(const SpeechListening(true));
  }

  test('the mic listens in the app language, on the device first; a language chosen in Settings wins', () async {
    await listen();
    expect(dictation.phase.value, VoicePhase.listening);
    expect(speech.starts.single, (localeId: 'vi-VN', onDevice: true));
    dictation.stop();
    await settings.setVoiceLocale(VoiceLocale.en);
    await listen(app: 'vi');
    expect(speech.starts.last.localeId, 'en-US');
  });

  test('what is heard shows after what was typed; the final result stays, nothing is sent', () async {
    field.text = 'Sửa lỗi';
    await listen();
    speech.emit(const SpeechPartial('trong'));
    expect(field.text, 'Sửa lỗi trong');
    speech.emit(const SpeechPartial('trong trang đăng nhập'));
    expect(field.text, 'Sửa lỗi trong trang đăng nhập');
    speech.emit(const SpeechFinal('trong trang đăng nhập'));
    speech.emit(const SpeechListening(false));
    expect(field.text, 'Sửa lỗi trong trang đăng nhập');
    expect(field.selection, const TextSelection.collapsed(offset: 'Sửa lỗi trong trang đăng nhập'.length));
    expect(dictation.phase.value, VoicePhase.idle);
    expect(sends, 0);
  });

  test('"gửi" as the last word sends the field when the session can take it', () async {
    field.text = 'Thêm nút';
    await listen();
    speech.emit(const SpeechFinal('đăng xuất gửi'));
    expect(field.text, 'Thêm nút đăng xuất', reason: 'the page sends what the field holds');
    expect(sends, 1);
  });

  test('"send" in English, and "gửi" while listening in English is just a word', () async {
    await listen(app: 'en');
    speech.emit(const SpeechFinal('add a logout button send'));
    expect((field.text, sends), ('add a logout button', 1));
    field.clear();
    await listen(app: 'en');
    speech.emit(const SpeechFinal('xin chào gửi'));
    expect((field.text, sends), ('xin chào gửi', 1));
  });

  test('"gửi" while the session cannot take a message leaves the words in the field', () async {
    canSend = false;
    await listen();
    speech.emit(const SpeechFinal('chạy test gửi'));
    expect((field.text, sends), ('chạy test', 0));
  });

  test('"huỷ" drops what was just said, never what was typed (R9)', () async {
    field.text = 'Đừng xoá câu này';
    await listen();
    speech.emit(const SpeechPartial('ơ nhầm'));
    expect(field.text, 'Đừng xoá câu này ơ nhầm');
    speech.emit(const SpeechFinal('ơ nhầm huỷ'));
    expect((field.text, sends), ('Đừng xoá câu này', 0));
    // The next utterance goes on from what the field holds.
    await listen();
    speech.emit(const SpeechFinal('nhé'));
    expect(field.text, 'Đừng xoá câu này nhé');
  });

  test('a tap while listening stops the recognizer; its final result still lands', () async {
    await listen();
    await dictation.toggle('vi');
    expect(speech.stops, 1);
    speech.emit(const SpeechFinal('xong'));
    expect(field.text, 'xong');
  });

  test('stop() ends the listen at once and keeps the field; a late result is ignored', () async {
    field.text = 'Giữ nguyên';
    await listen();
    speech.emit(const SpeechPartial('thêm'));
    dictation.stop();
    expect(speech.cancels, 1);
    expect(dictation.phase.value, VoicePhase.idle);
    expect(field.text, 'Giữ nguyên thêm');
    speech.emit(const SpeechFinal('thêm nữa gửi'));
    expect((field.text, sends), ('Giữ nguyên thêm', 0));
  });

  test('stop() while the permission prompt is up: the listen never starts', () async {
    speech.permissionGate = Completer<void>();
    final starting = dictation.toggle('vi');
    dictation.stop();
    speech.permissionGate!.complete();
    await starting;
    expect(speech.starts, isEmpty);
    expect(dictation.phase.value, VoicePhase.idle);
  });

  test('a refused permission, a phone without the language: said, nothing heard', () async {
    speech.permission = SpeechPermission.denied;
    await dictation.toggle('vi');
    expect(dictation.issue.value, VoiceIssue.noPermission);
    expect(speech.starts, isEmpty);
    speech
      ..permission = SpeechPermission.granted
      ..localeIds = {VoiceLocale.vi: null, VoiceLocale.en: 'en-US'};
    await dictation.toggle('vi');
    expect(dictation.issue.value, VoiceIssue.localeUnavailable);
    expect(speech.starts, isEmpty);
  });

  test('on the device first; a failure before any word tries the cloud once', () async {
    await listen();
    speech.emit(const SpeechFailed(SpeechErrorKind.other));
    expect(speech.starts, [(localeId: 'vi-VN', onDevice: true), (localeId: 'vi-VN', onDevice: false)]);
    expect(dictation.phase.value, VoicePhase.listening);
    speech.emit(const SpeechFailed(SpeechErrorKind.network));
    expect(dictation.issue.value, VoiceIssue.network);
    expect(dictation.phase.value, VoicePhase.idle);
  });

  test('dispose ends a listen; nothing heard afterwards touches the field', () async {
    await listen();
    dictation.dispose();
    expect(speech.cancels, 1);
    speech.emit(const SpeechFinal('muộn'));
    expect(field.text, isEmpty);
  });
}
