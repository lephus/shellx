import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/ai/domain/ai_attachments.dart';
import 'package:shellx_mobile/features/ai/presentation/widgets/ai_dock.dart';

import '../../support/app_harness.dart';
import '../../support/fake_image_source.dart';

/// V2-2b B12, B13: the AI composer with images and `@` suggestions.
void main() {
  late TextEditingController text;
  late List<String> taps;

  setUp(() {
    text = TextEditingController();
    taps = [];
  });

  tearDown(() => text.dispose());

  AiPickedImage png() => AiPickedImage(kTinyPng, 'image/png');

  Future<void> pump(
    WidgetTester tester, {
    List<AiPickedImage> images = const [],
    bool attach = true,
    bool running = false,
    bool sending = false,
    ({int sent, int parts})? upload,
    List<String> suggestions = const [],
    String? note,
    void Function(AiPickedImage image)? onRemove,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AiComposer(
              controller: text,
              agentName: 'Claude',
              canSend: true,
              running: running,
              stopping: false,
              canForceStop: false,
              sending: sending,
              onSend: () => taps.add('send'),
              onStop: () => taps.add('stop'),
              onForceStop: () => taps.add('force'),
              images: images,
              onAttach: attach ? () => taps.add('attach') : null,
              onRemoveImage: onRemove ?? (image) => taps.add('remove ${images.indexOf(image)}'),
              upload: upload,
              suggestions: suggestions,
              onSuggestion: (path) => taps.add('pick $path'),
              note: note,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400)); // what had to wait has waited
  }

  IconButton button(WidgetTester tester, String key) => tester.widget<IconButton>(find.byKey(Key(key)));

  testWidgets('the attach button only when the computer takes images; off at five, and while a message goes', (
    tester,
  ) async {
    await pump(tester, attach: false);
    expect(find.byKey(const Key('ai.attach')), findsNothing);
    await pump(tester);
    expect(button(tester, 'ai.attach').tooltip, 'Thêm ảnh');
    await tester.tap(find.byKey(const Key('ai.attach')));
    expect(taps, ['attach']);
    await pump(tester, images: [for (var i = 0; i < 5; i++) png()]);
    expect(button(tester, 'ai.attach').onPressed, isNull);
    await pump(tester, images: [png()], sending: true);
    expect(button(tester, 'ai.attach').onPressed, isNull);
  });

  testWidgets('the images as thumbnails in the order picked; × takes one out, not while they go out', (tester) async {
    final images = [png(), png()];
    await pump(tester, images: images);
    expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    expect(find.byKey(const Key('ai.image.1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.image.remove.1')));
    expect(taps, ['remove 1']);
    await pump(tester, images: images, sending: true);
    expect(button(tester, 'ai.image.remove.0').onPressed, isNull);
  });

  testWidgets('images alone can be sent; while they wait Send stays, Stop does not take its place', (tester) async {
    await pump(tester, images: [png()], running: true);
    expect(find.byKey(const Key('ai.stop')), findsNothing);
    expect(button(tester, 'ai.send').tooltip, 'Xếp hàng');
    await tester.tap(find.byKey(const Key('ai.send')));
    expect(taps, ['send']);
    await pump(tester, running: true); // the images went, the field is empty: Stop comes back
    expect(find.byKey(const Key('ai.stop')), findsOneWidget);
  });

  testWidgets('the images going out: a bar of the parts taken; the note above the field', (tester) async {
    await pump(tester, images: [png()], upload: (sent: 1, parts: 4), note: 'Ảnh chưa gửi được. Thử lại');
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('ai.upload')));
    expect(bar.value, 0.25);
    expect(tester.widget<Text>(find.byKey(const Key('ai.composer.note'))).data, 'Ảnh chưa gửi được. Thử lại');
    await pump(tester);
    expect(find.byKey(const Key('ai.upload')), findsNothing);
    expect(find.byKey(const Key('ai.composer.note')), findsNothing);
  });

  testWidgets('the computer\'s files for the @ being typed; a tap picks one; eight at most', (tester) async {
    await pump(tester, suggestions: [for (var i = 0; i < 10; i++) 'src/f$i.ts']);
    expect(find.byKey(const Key('ai.suggest')), findsOneWidget);
    expect(find.byKey(const Key('ai.suggest.src/f0.ts')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai.suggest.src/f0.ts')));
    expect(taps, ['pick src/f0.ts']);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai.suggest.src/f7.ts')),
      44,
      scrollable: find.descendant(of: find.byKey(const Key('ai.suggest')), matching: find.byType(Scrollable)),
    );
    expect(find.byKey(const Key('ai.suggest.src/f7.ts')), findsOneWidget);
    expect(find.byKey(const Key('ai.suggest.src/f8.ts'), skipOffstage: false), findsNothing);
    await pump(tester);
    expect(find.byKey(const Key('ai.suggest')), findsNothing);
  });
}
