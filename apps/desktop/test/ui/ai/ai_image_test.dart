import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

/// A 2×2 BMP, 24 bits, as Windows puts a screenshot on the clipboard.
Uint8List _bmp() {
  final b = BytesBuilder();
  void le32(int v) =>
      b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  void le16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  b.add([0x42, 0x4D]);
  le32(54 + 16);
  le32(0);
  le32(54);
  le32(40);
  le32(2);
  le32(2);
  le16(1);
  le16(24);
  le32(0);
  le32(16);
  le32(2835);
  le32(2835);
  le32(0);
  le32(0);
  // Rows bottom-up, BGR, each padded to 4 bytes.
  b.add([0, 0, 255, 0, 255, 0, 0, 0]);
  b.add([255, 0, 0, 255, 255, 255, 0, 0]);
  return b.toBytes();
}

/// V2-1 D16: images pasted into the composer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  void mockClipboardText(WidgetTester t, String? text) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' && text != null
          ? {'text': text}
          : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  String composerText(WidgetTester t) => t
      .widget<TextField>(find.byKey(const Key('ai.composer')))
      .controller!
      .text;

  testWidgets('pasted text that starts with @ is only text: no file is '
      'mentioned (D16)', (t) async {
    mockClipboardText(t, '@everyone hello');
    final (fakes, runtime, _) = await dock(t, const FakeScenario());
    await paste(t);
    expect(composerText(t), '@everyone hello');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'text', 'text': '@everyone hello'},
    ]);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a pasted text goes in at the cursor, over the selection', (
    t,
  ) async {
    mockClipboardText(t, 'XY');
    final (_, runtime, _) = await dock(t, const FakeScenario());
    await t.enterText(find.byKey(const Key('ai.composer')), 'abcd');
    t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .controller!
        .selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 3,
    );
    await t.pump();
    await paste(t);
    expect(composerText(t), 'aXYd');
    await runtime.dispose();
  }, variant: mac);

  testWidgets('what is no image falls back to the text on the clipboard', (
    t,
  ) async {
    mockClipboardText(t, 'the text');
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: Uint8List.fromList(utf8.encode('not an image at all')),
    );
    await paste(t);
    expect(ui.images.items, isEmpty);
    expect(composerText(t), 'the text');
    await runtime.dispose();
  }, variant: mac);

  testWidgets('an image over 10 MiB is not attached, like a dropped one', (
    t,
  ) async {
    mockClipboardText(t, null);
    final big = Uint8List((10 << 20) + 1)
      ..setRange(0, 4, [0x89, 0x50, 0x4E, 0x47]);
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: big,
    );
    await paste(t);
    expect(ui.images.items, isEmpty);
    expect(t.takeException(), isNull);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a Windows screenshot (BMP) is attached as a PNG', (t) async {
    mockClipboardText(t, null);
    final (fakes, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _bmp(),
    );
    await paste(t);
    // The codec answers on the engine's own thread: real time.
    for (var i = 0; i < 40 && ui.images.items.isEmpty; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
    }
    expect(ui.images.items, hasLength(1));
    expect(ui.images.items.single.mime, 'image/png');
    expect(aiImageMime(ui.images.items.single.bytes), 'image/png');
    await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect((prompt.last as Map)['mimeType'], 'image/png');
    await runtime.dispose();
  }, variant: mac);

  test('aiPngOf: BMP in, PNG out; what is no image gives null', () async {
    final png = await aiPngOf(_bmp());
    expect(png, isNotNull);
    expect(aiImageMime(png!), 'image/png');
    expect(await aiPngOf(Uint8List.fromList(utf8.encode('BM nope'))), isNull);
    expect(await aiPngOf(Uint8List(0)), isNull);
  });

  testWidgets('"Remove image" keeps the keyboard in the composer', (t) async {
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    final focus = t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .focusNode!;
    await t.tap(
      find.byKey(const Key('ai.image.remove.0')),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
    expect(ui.images.items, isEmpty);
    expect(focus.hasPrimaryFocus, isTrue);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a thumbnail decodes at its own size, not the whole image', (
    t,
  ) async {
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    expect(ui.images.items, hasLength(1));
    final image = t.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('ai.image.0')),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).height, 40);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a pane that is not shown takes no drop (a hidden tab)', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      IndexedStack(index: 1, children: const [AiDock(), SizedBox()]),
      runtime: runtime,
    );
    expect(
      t.widget<DropTarget>(find.byType(DropTarget, skipOffstage: false)).enable,
      isFalse,
    );
    await pumpAiPart(
      t,
      IndexedStack(index: 0, children: const [AiDock(), SizedBox()]),
      runtime: runtime,
    );
    expect(t.widget<DropTarget>(find.byType(DropTarget)).enable, isTrue);
    await runtime.dispose();
  });
}
