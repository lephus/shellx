import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart' show InMemoryKeyValueStore;
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_image_source.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_dictation.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_items.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/voice/domain/speech_input.dart';
import 'package:shellx_mobile/features/voice/domain/voice_locale.dart';

import '../../support/app_harness.dart';
import '../../support/fake_image_source.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fake_speech.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

/// V2-2b B14: the mic of the AI composer, on the session page.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late FakeSpeechInput speech;

  setUp(() async {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    speech = FakeSpeechInput();
    final settings = AppSettings(InMemoryKeyValueStore());
    await settings.load();
    final drafts = AiDrafts();
    final registry = WorkspaceRegistry(session.backend);
    getIt
      ..registerSingleton<PopupHandler>(FakePopupHandler())
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerFactory<AiDictation>(() => AiDictation(speech, settings))
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, drafts, registry),
      );
  });

  tearDown(() async => getIt.reset());

  Future<FakeAiSession> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ai = machine.ai.session(sid);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [
          AutoRoute(page: AiSessionRoute.page),
          AutoRoute(page: AiItemRoute.page),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ai.sync();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return ai;
  }

  String field(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('ai.composer'))).controller!.text;

  IconButton mic(WidgetTester tester) => tester.widget<IconButton>(find.byKey(const Key('ai.mic')));

  /// A tap on the mic, and the recognizer says it hears.
  Future<void> listen(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pump();
    speech.emit(const SpeechListening(true));
    await tester.pump();
  }

  testWidgets('words go in the field as they come; "gửi" at the end sends the message', (tester) async {
    await open(tester);
    expect(mic(tester).tooltip, 'Nói tin nhắn');
    await listen(tester);
    expect(speech.starts.single, (localeId: 'vi-VN', onDevice: true));
    expect(mic(tester).tooltip, 'Dừng nghe');
    speech.emit(const SpeechPartial('thêm nút'));
    await tester.pump();
    expect(field(tester), 'thêm nút');
    speech.emit(const SpeechFinal('thêm nút đăng xuất gửi'));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts.single, (sid, 'thêm nút đăng xuất'));
    expect(field(tester), isEmpty);
    expect(mic(tester).tooltip, 'Nói tin nhắn');
  });

  testWidgets('"gửi" while the session cannot take the message: the words stay, nothing is sent', (tester) async {
    final ai = await open(tester);
    ai.lose(); // the channel is gone: the link waits for the next one
    await tester.pump();
    await listen(tester);
    speech.emit(const SpeechFinal('xin chào gửi'));
    await tester.pumpAndSettle();
    expect(field(tester), 'xin chào');
    expect(machine.ai.prompts, isEmpty);
  });

  testWidgets('a session that stops being live stops the mic; what was heard stays', (tester) async {
    final ai = await open(tester);
    await listen(tester);
    speech.emit(const SpeechPartial('sửa lỗi'));
    await tester.pump();
    ai.lose();
    await tester.pump();
    expect(speech.cancels, 1);
    expect(field(tester), 'sửa lỗi');
    expect(mic(tester).tooltip, 'Nói tin nhắn');
  });

  testWidgets('the app leaving the front stops the mic', (tester) async {
    await open(tester);
    await listen(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(speech.cancels, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('leaving the page stops the mic', (tester) async {
    await open(tester);
    await listen(tester);
    await tester.tap(find.byKey(const Key('ai.back')));
    await tester.pumpAndSettle();
    expect(speech.cancels, 1);
  });

  testWidgets('a page pushed over the session (Xem đủ) stops the mic: a "gửi" heard later sends nothing', (
    tester,
  ) async {
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.item}))
      ..fullItems[0] = const AiFullView(kind: 'tool', title: 'npm test', output: 'dòng 0');
    machine.ai
        .session(sid)
        .desktop
        .applyUpdate(
          SessionUpdate.fromJson({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'c1',
            'title': 'npm test',
            'kind': 'execute',
            'status': 'completed',
            'content': [
              {
                'type': 'content',
                'content': {
                  'type': 'text',
                  'text': [for (var i = 0; i < 3000; i++) 'dòng $i'].join('\n'),
                },
              },
            ],
          }),
          DateTime.now(),
        );
    await open(tester);
    await tester.tap(find.byType(AiToolCard));
    await tester.pumpAndSettle();
    await listen(tester);
    speech.emit(const SpeechPartial('sửa lỗi'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('ai.viewAll.0')));
    await tester.tap(find.byKey(const Key('ai.viewAll.0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.item.title')), findsOneWidget);
    expect(speech.cancels, 1, reason: 'the mic stopped when the page went over the session');
    speech.emit(const SpeechFinal('sửa lỗi gửi'));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts, isEmpty);
  });

  testWidgets('a sheet over the session (the photos) stops the mic: a "gửi" heard later sends nothing', (
    tester,
  ) async {
    getIt.registerSingleton<AiImageSource>(FakeAiImageSource());
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.blob}));
    await open(tester);
    await listen(tester);
    speech.emit(const SpeechPartial('xem ảnh'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.attach')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.attach.library')), findsOneWidget);
    expect(speech.cancels, 1);
    speech.emit(const SpeechFinal('xem ảnh gửi'));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts, isEmpty);
  });

  testWidgets('Send while the mic hears: the mic stops, the message goes as it is', (tester) async {
    await open(tester);
    await listen(tester);
    speech.emit(const SpeechPartial('chạy test'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pumpAndSettle();
    expect(speech.cancels, 1);
    expect(machine.ai.prompts.single, (sid, 'chạy test'));
    speech.emit(const SpeechPartial('chạy test nữa')); // late: the listen is over
    await tester.pump();
    expect(field(tester), isEmpty);
  });

  testWidgets('a refused microphone is said in the composer', (tester) async {
    speech.permission = SpeechPermission.denied;
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data,
      'Cần quyền micro và nhận dạng giọng nói để nói lệnh',
    );
    expect(speech.starts, isEmpty);
  });

  testWidgets('the mic is there whatever the computer offers (the words stay on the phone until sent)', (
    tester,
  ) async {
    machine.ai.emitListing(const AiListing()); // no V2-2b feature at all
    await open(tester);
    expect(find.byKey(const Key('ai.mic')), findsOneWidget);
  });

  testWidgets('a phone without the language says which one, in the terminal\'s words; nothing is heard', (
    tester,
  ) async {
    speech.localeIds = {VoiceLocale.vi: null, VoiceLocale.en: 'en-US'};
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data,
      'Máy chưa hỗ trợ nhận dạng tiếng Việt — thử EN',
    );
    expect(speech.starts, isEmpty);
  });

  testWidgets('"gửi" with nothing to send sends nothing and says nothing', (tester) async {
    await open(tester);
    await listen(tester);
    speech.emit(const SpeechFinal('gửi'));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts, isEmpty);
    expect((getIt<PopupHandler>() as FakePopupHandler).errors, isEmpty);
    expect(field(tester), isEmpty);
  });

  testWidgets('"gửi" with images alone sends them: images alone make a message', (tester) async {
    getIt.registerSingleton<AiImageSource>(FakeAiImageSource()..photos = [kTinyPng]);
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.blob}));
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.attach.library')));
    await tester.pumpAndSettle();
    await listen(tester);
    speech.emit(const SpeechFinal('gửi'));
    await tester.pumpAndSettle();
    expect(machine.ai.prompts.single, (sid, ''));
    expect(machine.ai.promptBlobs.single, [1]);
    expect(find.byKey(const Key('ai.images')), findsNothing);
  });

  testWidgets('a refusal at the first prompt is said, though the prompt took the app out of the front (F40)', (
    tester,
  ) async {
    speech
      ..permission = SpeechPermission.denied
      ..permissionGate = Completer<void>();
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pump();
    // The system asks: the app is not in front while the prompt is up, and the answer is "Don't Allow".
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    speech.permissionGate!.complete();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data,
      'Cần quyền micro và nhận dạng giọng nói để nói lệnh',
    );
    expect(speech.starts, isEmpty);
  });

  testWidgets('the mic fills when the listen starts after the tap\'s own rebuild: the permission answer comes later', (
    tester,
  ) async {
    speech.permissionGate = Completer<void>();
    await open(tester);
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pump();
    expect(mic(tester).tooltip, 'Nói tin nhắn', reason: 'nothing hears while the system still asks');
    speech.permissionGate!.complete();
    await tester.pump();
    speech.emit(const SpeechListening(true));
    await tester.pump();
    expect(speech.starts, hasLength(1));
    expect(mic(tester).tooltip, 'Dừng nghe');
  });

  testWidgets('a voice problem is still said after an image note came and went while the dock ran again', (
    tester,
  ) async {
    final photos = FakeAiImageSource();
    getIt.registerSingleton<AiImageSource>(photos);
    machine.ai
      ..protocolValue = 2
      ..emitListing(const AiListing(features: {AiFeature.blob}));
    final ai = await open(tester);
    await listen(tester); // the dictation is made, the permission is granted
    speech.emit(const SpeechFinal('xong'));
    await tester.pump();
    Future<void> pickPhoto() async {
      await tester.tap(find.byKey(const Key('ai.attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai.attach.library')));
      await tester.pumpAndSettle();
    }

    // A photo of a type the computer refuses: the composer says why.
    photos.photos = [
      Uint8List.fromList(const [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]),
    ];
    await pickPhoto();
    expect(find.byKey(const Key('ai.composer.note')), findsOneWidget);
    ai.lose(); // the dock runs again with that note on screen
    await tester.pump();
    ai.sync();
    await tester.pumpAndSettle();
    photos.photos = [kTinyPng];
    await pickPhoto();
    expect(find.byKey(const Key('ai.composer.note')), findsNothing);
    speech.permission = SpeechPermission.denied;
    await tester.tap(find.byKey(const Key('ai.mic')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data,
      'Cần quyền micro và nhận dạng giọng nói để nói lệnh',
    );
  });

  testWidgets('typing while the mic hears: what was typed stays and the listen ends at the next words (F41)', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('ai.composer')), 'xin chào');
    await tester.pump();
    await listen(tester);
    await tester.enterText(find.byKey(const Key('ai.composer')), 'xin chào!');
    await tester.pump();
    speech.emit(const SpeechPartial('các bạn'));
    await tester.pump();
    expect(field(tester), 'xin chào!');
    expect(mic(tester).tooltip, 'Nói tin nhắn');
    expect(speech.cancels, 1);
  });
}
