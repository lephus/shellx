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

  // F40: the first permission prompt takes the app out of the front, and the page stops the dictation then. A stop
  // that lands while the system asks must not swallow the answer: a refusal is said, a listen does not start.
  group('stop() while the permission prompt is up (F40)', () {
    Future<void> stoppedDuringPrompt() async {
      speech.permissionGate = Completer<void>();
      final starting = dictation.toggle('vi');
      dictation.stop();
      speech.permissionGate!.complete();
      await starting;
    }

    test('a refusal is still said', () async {
      speech.permission = SpeechPermission.denied;
      await stoppedDuringPrompt();
      expect(dictation.issue.value, VoiceIssue.noPermission);
      expect(speech.starts, isEmpty);
      expect(dictation.phase.value, VoicePhase.idle);
    });

    test('so is a phone without speech recognition', () async {
      speech.permission = SpeechPermission.unsupported;
      await stoppedDuringPrompt();
      expect(dictation.issue.value, VoiceIssue.unsupported);
      expect(speech.starts, isEmpty);
    });

    test('so is a phone without the language', () async {
      speech.localeIds = {VoiceLocale.vi: null, VoiceLocale.en: 'en-US'};
      await stoppedDuringPrompt();
      expect(dictation.issue.value, VoiceIssue.localeUnavailable);
      expect(speech.starts, isEmpty);
    });

    test('a granted permission: nothing is said and the listen still does not start; the next tap does', () async {
      await stoppedDuringPrompt();
      expect(dictation.issue.value, isNull);
      expect(speech.starts, isEmpty);
      expect(dictation.phase.value, VoicePhase.idle);
      await listen();
      expect(speech.starts.single, (localeId: 'vi-VN', onDevice: true));
    });
  });

  // F41: the user types while it listens. What was typed is theirs: the listen ends at the next thing it hears, and
  // nothing of that listen touches the field again.
  group('the user edits the field while it listens (F41)', () {
    test('typed text survives the next partial, and the listen is over', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!'; // the user types
      speech.emit(const SpeechPartial('các bạn'));
      expect(field.text, 'xin chào!');
      expect(dictation.phase.value, VoicePhase.idle);
      expect(speech.cancels, 1);
    });

    test('so does text typed after words that were already heard', () async {
      field.text = 'xin chào';
      await listen();
      speech.emit(const SpeechPartial('các'));
      expect(field.text, 'xin chào các');
      field.text = 'xin chào các!';
      speech.emit(const SpeechPartial('các bạn'));
      expect(field.text, 'xin chào các!');
      expect(dictation.phase.value, VoicePhase.idle);
    });

    test('typed text survives a "huỷ" final: it was not said', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!';
      speech.emit(const SpeechFinal('huỷ'));
      expect((field.text, sends), ('xin chào!', 0));
    });

    test('a "gửi" final after an edit sends nothing and leaves the field', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!';
      speech.emit(const SpeechFinal('các bạn gửi'));
      expect((field.text, sends), ('xin chào!', 0));
    });

    test('the phase is idle once the edit is seen, and late words of that listen are nobody\'s', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!';
      speech.emit(const SpeechPartial('các'));
      expect(dictation.phase.value, VoicePhase.idle);
      speech.emit(const SpeechPartial('các bạn'));
      speech.emit(const SpeechFinal('các bạn gửi'));
      expect((field.text, sends), ('xin chào!', 0));
      expect(speech.cancels, 1);
    });

    test('the next listen goes on from the edited field', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!';
      speech.emit(const SpeechPartial('các'));
      await listen();
      speech.emit(const SpeechFinal('các bạn'));
      expect(field.text, 'xin chào! các bạn');
    });

    test('a failure after an edit neither retries in the cloud nor says anything: the listen is over', () async {
      field.text = 'xin chào';
      await listen();
      field.text = 'xin chào!';
      speech.emit(const SpeechFailed(SpeechErrorKind.other));
      expect(speech.starts, hasLength(1));
      expect(dictation.issue.value, isNull);
      expect(dictation.phase.value, VoicePhase.idle);
    });

    // Not edits: nothing here may end the listen.
    test('text typed while the prompt was still up is part of the field the words go after', () async {
      speech.permissionGate = Completer<void>();
      final starting = dictation.toggle('vi');
      field.text = 'gõ trước'; // the listen has not begun: this is the field it starts from
      speech.permissionGate!.complete();
      await starting;
      speech.emit(const SpeechListening(true));
      speech.emit(const SpeechPartial('rồi nói'));
      expect(field.text, 'gõ trước rồi nói');
      expect(dictation.phase.value, VoicePhase.listening);
    });

    test('a field that ends in a blank is not an edit', () async {
      field.text = 'xin chào ';
      await listen();
      speech.emit(const SpeechPartial('các bạn'));
      expect(field.text, 'xin chào các bạn');
      expect(dictation.phase.value, VoicePhase.listening);
    });

    test('a move of the cursor is not an edit', () async {
      field.text = 'xin chào';
      await listen();
      speech.emit(const SpeechPartial('các'));
      field.selection = const TextSelection.collapsed(offset: 3);
      speech.emit(const SpeechPartial('các bạn'));
      expect(field.text, 'xin chào các bạn');
      expect(dictation.phase.value, VoicePhase.listening);
    });
  });
}
