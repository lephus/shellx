import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_images.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// V2-1 D16: images pasted into the composer.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  test('image types by their first bytes', () {
    expect(aiImageMime(_png), 'image/png');
    expect(
      aiImageMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(aiImageMime(Uint8List.fromList(utf8.encode('hello'))), isNull);
  });

  Future<(FakeAiRuntimes, AiRuntime, AiPaneUi)> dock(
    WidgetTester t,
    FakeScenario scenario, {
    Uint8List? clipboard,
  }) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    part.ui.clipboardImage = () async => clipboard;
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime, part.ui);
  }

  Future<void> paste(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    await t.pump();
  }

  testWidgets('⌘V with an image attaches it; it goes as an image block, '
      'with or without text', (t) async {
    final (fakes, runtime, _) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'text', 'text': 'what is this'},
      {'type': 'image', 'data': base64Encode(_png), 'mimeType': 'image/png'},
    ]);
    expect(find.byKey(const Key('ai.image.0')), findsNothing);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('"Remove image" takes it off', (t) async {
    final (_, runtime, _) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    await t.tap(find.byKey(const Key('ai.image.remove.0')));
    await t.pump();
    expect(find.byKey(const Key('ai.image.0')), findsNothing);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('an agent that takes no images says so', (t) async {
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(image: false),
      clipboard: _png,
    );
    await paste(t);
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(ui.images.items, isEmpty);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('without an image, ⌘V pastes the text at the cursor', (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'hello'} : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final (_, runtime, _) = await dock(t, const FakeScenario());
    await paste(t);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      'hello',
    );
    await runtime.dispose();
  }, variant: mac);
}
