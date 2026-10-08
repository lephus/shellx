import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';

import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';

void main() {
  late VoiceComposerController c;
  late List<String> sent;

  setUp(() async {
    getIt.registerSingleton<PopupHandler>(FakePopupHandler());
    final settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    c = VoiceComposerController(FakeSpeechInput(), settings);
    sent = [];
    c.attach(canSend: () => true, onSubmit: sent.add);
  });

  tearDown(() async {
    c.dispose();
    await getIt.reset();
  });

  test('each terminal keeps its own text in the composer', () {
    final a = DraftHolder(), b = DraftHolder();
    c.useDraft(a);
    c.text.text = 'git status';
    c.useDraft(b);
    expect(c.text.text, '');
    c.text.text = 'ls -la';
    c.useDraft(a);
    expect(c.text.text, 'git status');
    c.useDraft(b);
    expect(c.text.text, 'ls -la');
    expect(a.value, 'git status');
  });

  test('sending clears that terminal\'s draft only', () {
    final a = DraftHolder(), b = DraftHolder()..value = 'keep';
    c.useDraft(a);
    c.text.text = 'go';
    c.sendNow();
    expect(sent, ['go']);
    expect(a.value, '');
    expect(b.value, 'keep');
  });

  test('closing the composer with the cross discards the draft', () {
    final a = DraftHolder();
    c.useDraft(a);
    c.text.text = 'oops';
    c.close();
    expect(a.value, '');
  });

  test('no holder (no tab): the composer is plain and loses nothing', () {
    c.useDraft(null);
    c.text.text = 'x';
    expect(c.text.text, 'x');
  });

  test('going from a terminal to none leaves that terminal\'s draft and empties the field', () {
    final a = DraftHolder();
    c.useDraft(a);
    c.text.text = 'keep me';
    c.useDraft(null);
    expect(a.value, 'keep me');
    expect(c.text.text, '');
  });

  test('a draft is never printed (privacy)', () {
    expect(DraftHolder().toString(), '…');
    expect((DraftHolder()..value = 'secret').toString(), isNot(contains('secret')));
  });
}
