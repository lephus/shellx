import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_drafts.dart';
import 'package:shellx_mobile/features/ai/domain/ai_image_source.dart';
import 'package:shellx_mobile/features/ai/presentation/controllers/ai_session_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';

import '../../support/app_harness.dart';
import '../../support/fake_image_source.dart';
import '../../support/fake_links.dart';
import '../../support/fake_popup_handler.dart';
import '../../support/fakes.dart';

const sid = 'e.-1';

/// V2-2b B12, B13: photos and `@` files in the composer of the AI session page.
void main() {
  late FakeBackend backend;
  late FakeMachineSession machine;
  late FakeSessionHolder session;
  late FakePopupHandler popups;
  late FakeAiImageSource photos;

  setUp(() {
    backend = FakeBackend(pinnedList: [pinned(agentA)]);
    machine = backend.addMachine(agentA);
    session = FakeSessionHolder(backend);
    popups = FakePopupHandler();
    photos = FakeAiImageSource();
    final drafts = AiDrafts();
    final registry = WorkspaceRegistry(session.backend);
    getIt
      ..registerSingleton<PopupHandler>(popups)
      ..registerSingleton<SessionHolder>(session)
      ..registerSingleton<ExternalLinks>(FakeExternalLinks())
      ..registerSingleton<AiImageSource>(photos)
      ..registerFactoryParam<AiSessionController, String, String>(
        (agentId, sid) => AiSessionController(agentId, sid, session, drafts, registry),
      );
  });

  tearDown(() async => getIt.reset());

  /// The page of [sid] on a computer whose listing offers [features]; its panels have settled.
  Future<FakeAiSession> open(
    WidgetTester tester, {
    Set<String> features = const {AiFeature.blob, AiFeature.files},
  }) async {
    machine.ai
      ..protocolValue = 2
      ..emitListing(AiListing(features: features));
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ai = machine.ai.session(sid);
    await tester.pumpWidget(
      routedApp(
        open: () => AiSessionRoute(agentId: agentA, machineName: 'MacBook', sid: sid),
        routes: [AutoRoute(page: AiSessionRoute.page)],
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

  IconButton button(WidgetTester tester, String key) => tester.widget<IconButton>(find.byKey(Key(key)));

  /// "Thêm ảnh" → [origin] ("ai.attach.library" or "ai.attach.camera").
  Future<void> attach(WidgetTester tester, {String origin = 'ai.attach.library'}) async {
    await tester.tap(find.byKey(const Key('ai.attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(origin)));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('ai.composer')), text);
    await tester.pump();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pumpAndSettle();
  }

  group('photos (B12)', () {
    testWidgets('from the library: the sheet offers both ways in; the photos become thumbnails; × takes one out', (
      tester,
    ) async {
      photos.photos = [kTinyPng, kTinyPng];
      await open(tester);
      await tester.tap(find.byKey(const Key('ai.attach')));
      await tester.pumpAndSettle();
      expect(find.text('Thư viện ảnh'), findsOneWidget);
      expect(find.text('Chụp ảnh'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai.attach.library')));
      await tester.pumpAndSettle();
      expect(photos.limits, [5]);
      expect(find.byKey(const Key('ai.image.1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai.image.remove.1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
      expect(find.byKey(const Key('ai.image.1')), findsNothing);
    });

    testWidgets('from the camera', (tester) async {
      photos.photo = kTinyPng;
      await open(tester);
      await attach(tester, origin: 'ai.attach.camera');
      expect(photos.cameraCalls, 1);
      expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    });

    testWidgets('five at most: the picker is asked for what is left, then the button is off', (tester) async {
      photos.photos = [kTinyPng, kTinyPng, kTinyPng];
      await open(tester);
      await attach(tester);
      await attach(tester);
      expect(photos.limits, [5, 2]);
      expect(find.byKey(const Key('ai.image.4')), findsOneWidget);
      expect(button(tester, 'ai.attach').onPressed, isNull);
    });

    testWidgets('a photo of a type the computer does not take stays out, and the composer says why', (tester) async {
      photos.photos = [
        Uint8List.fromList(const [0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]),
        kTinyPng,
      ];
      await open(tester);
      await attach(tester);
      expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
      expect(find.byKey(const Key('ai.image.1')), findsNothing);
      expect(find.text('Chỉ gửi được ảnh JPEG, PNG, GIF hoặc WebP.'), findsOneWidget);
    });

    testWidgets('one message carries 20 MB of images at most, counting what is already in the row (F34): the photo '
        'that would pass it stays out, and the composer says why', (tester) async {
      photos.photos = [jpegOfSize(8 << 20), jpegOfSize(8 << 20), jpegOfSize(8 << 20)];
      await open(tester);
      await attach(tester);
      expect(find.byKey(const Key('ai.image.1')), findsOneWidget);
      expect(find.byKey(const Key('ai.image.2')), findsNothing, reason: 'the third would make 24 MB');
      expect(find.text('Một tin chỉ mang được tối đa 20 MB ảnh.'), findsOneWidget);
      photos.photos = [jpegOfSize(5 << 20)];
      await attach(tester);
      expect(find.byKey(const Key('ai.image.2')), findsNothing, reason: '16 MB are in the row: 5 MB more pass 20');
      expect(find.text('Một tin chỉ mang được tối đa 20 MB ảnh.'), findsOneWidget);
      photos.photos = [jpegOfSize(4 << 20)];
      await attach(tester);
      expect(find.byKey(const Key('ai.image.2')), findsOneWidget, reason: '16 + 4 are exactly 20 MB');
      expect(find.text('Một tin chỉ mang được tối đa 20 MB ảnh.'), findsNothing);
    });

    testWidgets('the photos go up without their metadata, the place they were taken included (F38)', (tester) async {
      final plain = jpegOfSize(40);
      final located = [...'Exif\u0000\u0000'.codeUnits, ...'GPSLatitude 37.77N GPSLongitude 122.41W'.codeUnits];
      final photo = Uint8List.fromList([
        ...plain.sublist(0, 2), // SOI
        0xFF, 0xE1, (located.length + 2) >> 8, (located.length + 2) & 0xFF, ...located, // an Exif with a location
        ...plain.sublist(2),
      ]);
      expect(photo.length, greaterThan(plain.length));
      photos.photos = [photo];
      await open(tester);
      await attach(tester);
      await send(tester);
      expect(machine.ai.uploads.single.$3, plain.length, reason: 'what goes up is the picture alone');
    });

    testWidgets('a picker that fails (camera refused) says so, and nothing changes', (tester) async {
      photos.error = PlatformException(code: 'camera_access_denied');
      await open(tester);
      await attach(tester, origin: 'ai.attach.camera');
      expect(find.byKey(const Key('ai.images')), findsNothing);
      expect(find.text('Không mở được ảnh. Hãy kiểm tra quyền của ShellX trong Cài đặt.'), findsOneWidget);
    });

    testWidgets('Send: the images go up, then the message names them; the field and the row empty', (tester) async {
      photos.photos = [kTinyPng, kTinyPng];
      await open(tester);
      await attach(tester);
      await type(tester, 'Xem giúp');
      await send(tester);
      expect(machine.ai.uploads.map((u) => u.$1), [1, 2]);
      expect(machine.ai.prompts.single, (sid, 'Xem giúp'));
      expect(machine.ai.promptBlobs.single, [1, 2]);
      expect(find.byKey(const Key('ai.images')), findsNothing);
      expect(field(tester), isEmpty);
    });

    testWidgets('images alone can be sent', (tester) async {
      photos.photos = [kTinyPng];
      await open(tester);
      await attach(tester);
      expect(button(tester, 'ai.send').onPressed, isNotNull);
      await send(tester);
      expect(machine.ai.prompts.single, (sid, ''));
      expect(machine.ai.promptBlobs.single, [1]);
    });

    testWidgets('while the images go up: a bar, and nothing can be added or taken out', (tester) async {
      photos.photos = [kTinyPng];
      machine.ai.uploadGate = Completer<void>();
      await open(tester);
      await attach(tester);
      await tester.tap(find.byKey(const Key('ai.send')));
      await tester.pump();
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const Key('ai.upload'))).value, 0);
      expect(button(tester, 'ai.attach').onPressed, isNull);
      expect(button(tester, 'ai.image.remove.0').onPressed, isNull);
      machine.ai.uploadGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.upload')), findsNothing);
      expect(machine.ai.prompts, hasLength(1));
    });

    testWidgets('an image that does not go up: the text and the images stay, no message went, and the composer '
        'says so; only the next tap tries again', (tester) async {
      photos.photos = [kTinyPng];
      machine.ai.uploadError = const MachineConnectionException(MachineConnectionFailure.agentOffline);
      await open(tester);
      await attach(tester);
      await type(tester, 'Xem giúp');
      await send(tester);
      expect(machine.ai.prompts, isEmpty);
      expect(field(tester), 'Xem giúp');
      expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data, 'Ảnh chưa gửi được. Thử lại');
      await tester.pump(const Duration(minutes: 1));
      expect(machine.ai.uploads, hasLength(1), reason: 'nothing goes again by itself');
      machine.ai.uploadError = null;
      await send(tester);
      expect(machine.ai.promptBlobs.single, [2]);
      expect(find.byKey(const Key('ai.composer.note')), findsNothing);
    });

    // F39: the note of an upload that did not go is gone once the next Send is on its way. That Send's images went
    // up, so what stops its message after them is the popup's to say alone: "Retry" would invite a resend of a
    // message that may have landed (D13), or of one that can never go.
    for (final (label, fail, said) in <(String, void Function(FakeAiMachine), String)>[
      ('a computer too busy', (ai) => ai.failWith = 'busy', 'Quá nhiều yêu cầu cùng lúc. Chờ một lát rồi thử lại.'),
      (
        'a channel lost',
        (ai) => ai.connectFailure = MachineConnectionFailure.agentOffline,
        'Có thể chưa gửi được — kết nối bị gián đoạn. Hãy xem lại phiên trước khi thử lại.',
      ),
      ('an agent that takes no images', (ai) => ai.failWith = 'no_images', 'Claude không nhận ảnh.'),
    ]) {
      testWidgets('an upload failed, then the retried images got through and the message failed ($label): the '
          'note is gone, only the popup speaks (F39)', (tester) async {
        photos.photos = [kTinyPng];
        machine.ai.uploadError = const MachineConnectionException(MachineConnectionFailure.agentOffline);
        await open(tester);
        await attach(tester);
        await type(tester, 'Xem giúp');
        await send(tester);
        expect(tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data, 'Ảnh chưa gửi được. Thử lại');
        machine.ai.uploadError = null;
        fail(machine.ai);
        await send(tester);
        expect(machine.ai.uploads, hasLength(2), reason: 'the images of the second Send went up');
        expect(find.byKey(const Key('ai.composer.note')), findsNothing);
        expect(popups.errors.last, said);
        expect(field(tester), 'Xem giúp');
        expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
      });
    }

    testWidgets('an agent that takes no images: said with its name, and nothing is lost', (tester) async {
      photos.photos = [kTinyPng];
      machine.ai.failWith = 'no_images';
      await open(tester);
      await attach(tester);
      await type(tester, 'Xem giúp');
      await send(tester);
      expect(popups.errors.last, 'Claude không nhận ảnh.');
      expect(field(tester), 'Xem giúp');
      expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    });

    testWidgets('a computer that takes no images: no attach button — until a listing offers them', (tester) async {
      await open(tester, features: const {});
      expect(find.byKey(const Key('ai.attach')), findsNothing);
      machine.ai.emitListing(const AiListing(features: {AiFeature.blob}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai.attach')), findsOneWidget);
    });

    testWidgets('the bubble of a message with images says how many', (tester) async {
      final ai = machine.ai.session(sid);
      ai.desktop.beginTurn(const [
        TextBlock('Xem'),
        ImageBlock(data: 'AA==', mimeType: 'image/png'),
        ImageBlock(data: 'AA==', mimeType: 'image/jpeg'),
      ], DateTime.now());
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('ai.user.images'))).data, '2 ảnh');
    });
  });

  group('@ files (B13)', () {
    testWidgets('after a pause the computer\'s files for the @ being typed; a tap writes @path; the files still '
        'mentioned go with the message', (tester) async {
      machine.ai.fileHits = const ['src/main.ts', 'src/app.ts'];
      await open(tester);
      await type(tester, 'Sửa @s');
      await tester.pump(const Duration(milliseconds: 50));
      await type(tester, 'Sửa @sr');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(machine.ai.fileQueries, [(sid, 'sr')], reason: 'one question, after the pause');
      await tester.tap(find.byKey(const Key('ai.suggest.src/main.ts')));
      await tester.pump();
      expect(field(tester), 'Sửa @src/main.ts ');
      expect(find.byKey(const Key('ai.suggest')), findsNothing);
      await type(tester, 'Sửa @src/main.ts cho gọn');
      await send(tester);
      expect(machine.ai.promptFiles.single, ['src/main.ts']);
    });

    testWidgets('a mention taken out of the text does not go', (tester) async {
      machine.ai.fileHits = const ['src/main.ts'];
      await open(tester);
      await type(tester, '@ma');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.suggest.src/main.ts')));
      await tester.pump();
      await type(tester, 'Thôi, sửa chỗ khác');
      await send(tester);
      expect(machine.ai.promptFiles.single, isEmpty);
    });

    testWidgets('a computer that offers no files is asked nothing', (tester) async {
      await open(tester, features: const {AiFeature.blob});
      await type(tester, 'Sửa @sr');
      await tester.pump(const Duration(milliseconds: 300));
      expect(machine.ai.fileQueries, isEmpty);
      expect(find.byKey(const Key('ai.suggest')), findsNothing);
    });
  });
}
