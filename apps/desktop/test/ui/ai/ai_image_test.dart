import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart'
    show AgentCapabilities, InitializeResult, PromptCapabilities;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart' show AgentPhase;
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
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

/// A PNG over the size from which base64 runs off the UI isolate.
Uint8List _bigPng() =>
    Uint8List.fromList([..._png, ...Uint8List(kAiInlineEncodeBytes)]);

/// Off-thread work that waits until a test opens the gate: the encode of a big
/// image is in flight, as it is while it runs on another isolate.
final class _Gate {
  final _waiting = <void Function()>[];

  int get waiting => _waiting.length;

  Future<R> call<Q, R>(R Function(Q input) work, Q input) {
    final done = Completer<R>();
    _waiting.add(() => done.complete(work(input)));
    return done.future;
  }

  void open() {
    final all = [..._waiting];
    _waiting.clear();
    for (final work in all) {
      work();
    }
  }
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

  /// What the system clipboard holds as text ([text] null: none, as with a
  /// screenshot). A paste reads the text first; a test that gives no answer
  /// would wait for the platform for ever.
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

  testWidgets('⌘V with an image attaches it; it goes as an image block, '
      'with or without text', (t) async {
    mockClipboardText(t, null);
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
    mockClipboardText(t, null);
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
    mockClipboardText(t, null);
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
    for (var i = 0; i < 100 && ui.images.items.isEmpty; i++) {
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
    mockClipboardText(t, null);
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
    mockClipboardText(t, null);
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
  }, variant: mac);
  // ---- I-2: a paste whose clipboard has text and a picture ----------------

  const cells = 'Region\tSales\nNorth\t120\nSouth\t95';

  /// A runtime that has not said what it takes: nothing has started, so no
  /// `initialize` has answered (a tab in its first seconds).
  Future<(FakeAiRuntimes, AiRuntime, AiPaneUi)> unknownAgent(
    WidgetTester t,
    FakeScenario scenario, {
    Uint8List? clipboard,
    List<Override> overrides = const [],
  }) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    final part = await pumpAiPart(
      t,
      const AiDock(),
      runtime: runtime,
      overrides: overrides,
    );
    part.ui.clipboardImage = () async => clipboard;
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime, part.ui);
  }

  for (final (who, scenario, started) in [
    ('an agent that takes images', const FakeScenario(), true),
    ('an agent that takes none', const FakeScenario(image: false), true),
    ('an agent that is still starting', const FakeScenario(), false),
  ]) {
    testWidgets('cells copied from a spreadsheet are text and a picture of '
        'them: with $who the text is pasted, as in the terminal (I-2)', (
      t,
    ) async {
      mockClipboardText(t, cells);
      final (_, runtime, ui) = started
          ? await dock(t, scenario, clipboard: _png)
          : await unknownAgent(t, scenario, clipboard: _png);
      await paste(t);
      expect(composerText(t), cells);
      expect(ui.images.items, isEmpty, reason: 'no picture of the cells');
      expect(ui.images.note, isNull, reason: 'nothing was refused');
      await runtime.dispose();
    }, variant: mac);
  }

  testWidgets('a screenshot has no text: it still attaches', (t) async {
    mockClipboardText(t, null);
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    expect(ui.images.items, hasLength(1));
    expect(composerText(t), isEmpty);
    await runtime.dispose();
  }, variant: mac);

  // ---- an agent that has not answered `initialize` ------------------------

  testWidgets('before the agent has said what it takes, an image is accepted '
      'and nothing says it takes none', (t) async {
    mockClipboardText(t, null);
    final (_, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(image: false),
      clipboard: _png,
    );
    await paste(t);
    expect(ui.images.items, hasLength(1));
    expect(ui.images.note, isNull);
    expect(find.textContaining('does not take images'), findsNothing);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('sending once the agent has said it takes no images is '
      'refused: the text, the image and the file come back or stay, and '
      'the reason is said', (t) async {
    mockClipboardText(t, null);
    final (fakes, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(image: false),
      clipboard: _png,
    );
    await paste(t);
    ui.mention('lib/a.dart');
    await t.pump();
    await t.enterText(find.byKey(const Key('ai.composer')), 'look @lib/a.dart');
    // The agent starts and says it takes no images.
    await runtime.start();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(composerText(t), 'look @lib/a.dart');
    expect(ui.images.items, hasLength(1));
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(fakes.agent().params['session/prompt'], isNull);
    // Take the image off and the same message goes, with its file.
    await t.tap(find.byKey(const Key('ai.image.remove.0')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.first, {'type': 'text', 'text': 'look @lib/a.dart'});
    expect((prompt.last as Map)['type'], 'resource_link');
    await runtime.dispose();
  }, variant: mac);

  testWidgets('sent while the agent starts, and then found to take no images: '
      'the message leaves the queue and comes back whole', (t) async {
    mockClipboardText(t, null);
    final (fakes, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(image: false),
      clipboard: _png,
    );
    await paste(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    // Sending starts the agent; its `initialize` says: no images.
    for (var i = 0; i < 12; i++) {
      await t.pump();
    }
    await runtime.whenIdle();
    await t.pump();
    expect(composerText(t), 'what is this');
    expect(ui.images.items, hasLength(1));
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(runtime.state.queue, isEmpty);
    expect(fakes.agent().params['session/prompt'], isNull, reason: 'not sent');
    await runtime.dispose();
  }, variant: mac);

  testWidgets('the same message to an agent that takes images goes on its '
      'way, image and all', (t) async {
    mockClipboardText(t, null);
    final (fakes, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 12; i++) {
      await t.pump();
    }
    await runtime.whenIdle();
    await t.pump();
    expect(composerText(t), isEmpty);
    expect(ui.images.items, isEmpty);
    expect(ui.images.note, isNull);
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.last, {
      'type': 'image',
      'data': base64Encode(_png),
      'mimeType': 'image/png',
    });
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a message waiting in the queue for `initialize` comes back '
      'when it answers with no images, and not before', (t) async {
    mockClipboardText(t, null);
    final (fakes, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    // The agent is starting; `initialize` has not answered.
    runtime.state.setPhase(AgentPhase.starting);
    await paste(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'queued text');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(runtime.state.queue, hasLength(1), reason: 'it waits');
    expect(composerText(t), isEmpty);
    expect(find.textContaining('does not take images'), findsNothing);
    runtime.state.setAgent(
      const InitializeResult(
        protocolVersion: 1,
        capabilities: AgentCapabilities(
          prompt: PromptCapabilities(image: false),
        ),
      ),
    );
    await t.pump();
    await t.pump();
    expect(runtime.state.queue, isEmpty);
    expect(composerText(t), 'queued text');
    expect(ui.images.items, hasLength(1));
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(fakes.launcher.channels, isEmpty, reason: 'nothing was started');
  }, variant: mac);

  testWidgets('a message waiting for `initialize` that the user took out of '
      'the queue stays out; a closed composer is not written to', (t) async {
    mockClipboardText(t, null);
    final (_, runtime, ui) = await unknownAgent(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    runtime.state.setPhase(AgentPhase.starting);
    await paste(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'one');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    runtime.state.removeQueued(runtime.state.queue.single.id);
    runtime.state.setAgent(
      const InitializeResult(
        protocolVersion: 1,
        capabilities: AgentCapabilities(
          prompt: PromptCapabilities(image: false),
        ),
      ),
    );
    await t.pump();
    expect(composerText(t), isEmpty);
    expect(ui.images.items, isEmpty);
    // And the other way: the composer goes away first.
    final (_, runtime2, _) = await unknownAgent(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    runtime2.state.setPhase(AgentPhase.starting);
    await paste(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'two');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    expect(runtime2.state.queue, hasLength(1));
    await t.pumpWidget(const SizedBox());
    runtime2.state.setAgent(
      const InitializeResult(
        protocolVersion: 1,
        capabilities: AgentCapabilities(
          prompt: PromptCapabilities(image: false),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  }, variant: mac);

  // ---- `initialize` answers while the images are encoded ------------------

  /// The message is sent while the agent has said nothing: its images (over
  /// 256 KB) are being encoded off the UI isolate, which the gate holds.
  Future<(FakeAiRuntimes, AiRuntime, AiPaneUi, _Gate)> encoding(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    mockClipboardText(t, null);
    final gate = _Gate();
    final (fakes, runtime, ui) = await unknownAgent(
      t,
      scenario,
      clipboard: _bigPng(),
      overrides: [aiOffThreadProvider.overrideWithValue(gate.call)],
    );
    await paste(t);
    expect(ui.images.items, hasLength(1));
    ui.mention('lib/a.dart');
    await t.pump();
    await t.enterText(find.byKey(const Key('ai.composer')), 'look @lib/a.dart');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(gate.waiting, 1, reason: 'the encode is under way');
    expect(composerText(t), isEmpty, reason: 'the message left');
    expect(ui.images.items, isEmpty);
    return (fakes, runtime, ui, gate);
  }

  testWidgets('the agent says it takes no images while the images are '
      'encoded: nothing is sent; the text, the image and the file come back '
      'and the reason is said', (t) async {
    final (fakes, runtime, ui, gate) = await encoding(
      t,
      const FakeScenario(image: false),
    );
    // The agent starts and answers `initialize`: no images. Then the encode
    // ends, and the message would go on its way.
    await runtime.start();
    await t.pump();
    gate.open();
    await t.pump();
    await t.pump();
    expect(fakes.agent().params['session/prompt'], isNull, reason: 'not sent');
    expect(runtime.state.queue, isEmpty);
    expect(composerText(t), 'look @lib/a.dart');
    expect(ui.images.items, hasLength(1));
    expect(find.text('Claude does not take images.'), findsOneWidget);
    // Nothing is lost: without the image the same message goes, with its file.
    await t.tap(find.byKey(const Key('ai.image.remove.0')));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.first, {'type': 'text', 'text': 'look @lib/a.dart'});
    expect((prompt.last as Map)['type'], 'resource_link');
    await runtime.dispose();
  }, variant: mac);

  testWidgets('the same while the agent is starting, where the message would '
      'wait in the queue: it does not join it', (t) async {
    final (fakes, runtime, ui, gate) = await encoding(t, const FakeScenario());
    runtime.state.setPhase(AgentPhase.starting);
    runtime.state.setAgent(
      const InitializeResult(
        protocolVersion: 1,
        capabilities: AgentCapabilities(
          prompt: PromptCapabilities(image: false),
        ),
      ),
    );
    gate.open();
    await t.pump();
    await t.pump();
    expect(runtime.state.queue, isEmpty);
    expect(composerText(t), 'look @lib/a.dart');
    expect(ui.images.items, hasLength(1));
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(fakes.launcher.channels, isEmpty, reason: 'nothing was started');
  }, variant: mac);

  testWidgets('what was typed while the images were encoded stays after the '
      'message that comes back', (t) async {
    final (_, runtime, ui, gate) = await encoding(
      t,
      const FakeScenario(image: false),
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'and this');
    await runtime.start();
    await t.pump();
    gate.open();
    await t.pump();
    await t.pump();
    expect(composerText(t), 'look @lib/a.dart\nand this');
    expect(ui.images.items, hasLength(1));
    await runtime.dispose();
  }, variant: mac);

  testWidgets('an agent that turns out to take images gets the message with '
      'its image, as before', (t) async {
    final (fakes, runtime, ui, gate) = await encoding(t, const FakeScenario());
    await runtime.start();
    await t.pump();
    gate.open();
    await t.pump();
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.map((b) => (b as Map)['type']), [
      'text',
      'image',
      'resource_link',
    ]);
    expect(composerText(t), isEmpty);
    expect(ui.images.items, isEmpty);
    expect(ui.images.note, isNull);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a composer that is gone by then is not written to, and the '
      'image is still not sent', (t) async {
    final (fakes, runtime, ui, gate) = await encoding(
      t,
      const FakeScenario(image: false),
    );
    await runtime.start();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    gate.open();
    await t.pump();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(fakes.agent().params['session/prompt'], isNull);
    expect(runtime.state.queue, isEmpty);
    expect(ui.images.items, isEmpty);
    await runtime.dispose();
  }, variant: mac);

  // ---- the limits are said ------------------------------------------------

  testWidgets('an image over 10 MiB is said to be too large; so is one '
      'pasted with no text', (t) async {
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
    expect(find.text('The image is too large (at most 10 MB).'), findsOne);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('an empty text on the clipboard is no text: the picture '
      'attaches', (t) async {
    mockClipboardText(t, '');
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    expect(ui.images.items, hasLength(1));
    expect(composerText(t), isEmpty);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a BMP over 64 MiB is said to be too large, not decoded', (
    t,
  ) async {
    mockClipboardText(t, null);
    final bmp = Uint8List((64 << 20) + 1)..setRange(0, 2, [0x42, 0x4D]);
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: bmp,
    );
    await paste(t);
    expect(ui.images.items, isEmpty);
    expect(find.text('The image is too large (at most 10 MB).'), findsOne);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('a sixth image is said to be one too many; five stay', (t) async {
    mockClipboardText(t, null);
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    for (var i = 0; i < 5; i++) {
      await paste(t);
    }
    expect(ui.images.items, hasLength(5));
    expect(find.text('At most 5 images per message.'), findsNothing);
    await paste(t);
    expect(ui.images.items, hasLength(5));
    expect(find.text('At most 5 images per message.'), findsOneWidget);
    await runtime.dispose();
  }, variant: mac);

  group('a drop', () {
    DropDoneDetails dropped(List<DropItemFile> files) => DropDoneDetails(
      files: files,
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    );

    /// A dropped file of [size] bytes at [path]: its size is known without
    /// asking the disk (a path made up for a test has no file, and the disk
    /// never answers under the fake clock of a widget test).
    DropItemFile file(String path, int size) =>
        DropItemFile.fromData(Uint8List(0), path: path, length: size);

    /// The pane's reader (`AiPaneView._readImage`) looks at a file's size
    /// first and answers null for one over 10 MiB, without reading it; this
    /// one does the same with the sizes it is told.
    Future<(AiRuntime, AiPaneUi, List<String>)> target(
      WidgetTester t, {
      Map<String, int> sizes = const {},
    }) async {
      final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
      await runtime.start();
      final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
      final read = <String>[];
      part.ui.readImageFile = (path) async {
        read.add(path);
        return (sizes[path] ?? 0) > (10 << 20) ? null : _png;
      };
      return (runtime, part.ui, read);
    }

    Future<void> drop(WidgetTester t, List<DropItemFile> files) async {
      t.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(dropped(files));
      for (var i = 0; i < 5; i++) {
        await t.pump();
      }
    }

    testWidgets('images attach, at most five; the sixth is said and its file '
        'is not read', (t) async {
      final (runtime, ui, read) = await target(t);
      await drop(t, [for (var i = 0; i < 7; i++) file('/shots/$i.png', 1000)]);
      expect(ui.images.items, hasLength(5));
      expect(read, [
        '/shots/0.png',
        '/shots/1.png',
        '/shots/2.png',
        '/shots/3.png',
        '/shots/4.png',
      ], reason: 'no more is read');
      expect(find.text('At most 5 images per message.'), findsOneWidget);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('an image over 10 MiB is said to be too large; the next one '
        'still attaches', (t) async {
      final (runtime, ui, read) = await target(
        t,
        sizes: {'/shots/huge.png': (10 << 20) + 1},
      );
      await drop(t, [
        file('/shots/huge.png', (10 << 20) + 1),
        file('/shots/ok.png', 1000),
      ]);
      // The reader looks at the size before it reads, and gives up on it.
      expect(read, ['/shots/huge.png', '/shots/ok.png']);
      expect(ui.images.items, hasLength(1));
      // The note of the big one is cleared by the next one attached.
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('the big one alone leaves its note', (t) async {
      final (runtime, ui, read) = await target(
        t,
        sizes: {'/shots/huge.jpg': 12 << 20},
      );
      await drop(t, [file('/shots/huge.jpg', 12 << 20)]);
      expect(read, ['/shots/huge.jpg']);
      expect(ui.images.items, isEmpty);
      expect(find.text('The image is too large (at most 10 MB).'), findsOne);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('a big file that is no image, and one that cannot be read, '
        'say nothing', (t) async {
      final (runtime, ui, read) = await target(
        t,
        sizes: {'/backup.zip': 50 << 20},
      );
      await drop(t, [file('/backup.zip', 50 << 20)]);
      expect(read, ['/backup.zip']);
      // An image the reader cannot read, and that is not over the limit.
      ui.readImageFile = (path) async => null;
      await drop(t, [file('/shots/broken.png', 10)]);
      expect(ui.images.items, isEmpty);
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('a path that is not on the disk (as the terminal\'s drop '
        'tests make them) drops like any other', (t) async {
      final (runtime, ui, read) = await target(t);
      await drop(t, [DropItemFile('/never/there.png')]);
      expect(read, ['/never/there.png']);
      expect(ui.images.items, hasLength(1));
      await runtime.dispose();
    }, variant: mac);

    testWidgets('a file that is no image is not read past the cap, and says '
        'nothing about images', (t) async {
      final (runtime, ui, read) = await target(t);
      await drop(t, [
        for (var i = 0; i < 5; i++) file('/shots/$i.png', 10),
        file('/notes/todo.txt', 10),
      ]);
      expect(ui.images.items, hasLength(5));
      expect(read, hasLength(5));
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);
  });

  // ---- ⌘V of files copied in Finder / Explorer ---------------------------

  group('⌘V with files on the clipboard', () {
    /// The pane with the clipboard holding [files] (and [text] and [image],
    /// as Finder puts the name of a copied file as text next to it); the
    /// pane's reader gives the [bytes] of a path, else null. The paths read.
    Future<(AiRuntime, AiPaneUi, List<String>)> clipboard(
      WidgetTester t, {
      required List<String> files,
      String? text,
      Uint8List? image,
      Map<String, Uint8List> bytes = const {},
      FakeScenario scenario = const FakeScenario(),
    }) async {
      mockClipboardText(t, text);
      final (_, runtime, ui) = await dock(t, scenario, clipboard: image);
      final read = <String>[];
      ui.clipboardFiles = () async => files;
      ui.readImageFile = (path) async {
        read.add(path);
        return bytes[path];
      };
      return (runtime, ui, read);
    }

    testWidgets('an image file copied in Finder attaches: the picture, '
        'not the name Finder also puts on the clipboard as text', (t) async {
      const file = '/Users/me/Desktop/shot.png';
      final (runtime, ui, read) = await clipboard(
        t,
        files: [file],
        text: 'shot.png',
        // Finder may offer the icon of the file as a picture too.
        image: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        bytes: {file: _png},
      );
      await paste(t);
      expect(read, [file]);
      expect(ui.images.items, hasLength(1));
      expect(ui.images.items.single.bytes, _png);
      expect(ui.images.items.single.mime, 'image/png');
      expect(composerText(t), isEmpty, reason: 'the name is not pasted');
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('it goes with the next message as an image block, like a '
        'dropped one', (t) async {
      const file = '/Users/me/Desktop/shot.png';
      mockClipboardText(t, 'shot.png');
      final (fakes, runtime, ui) = await dock(t, const FakeScenario());
      ui.clipboardFiles = () async => [file];
      ui.readImageFile = (path) async => _png;
      await paste(t);
      await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
      expect(prompt, [
        {'type': 'text', 'text': 'what is this'},
        {'type': 'image', 'data': base64Encode(_png), 'mimeType': 'image/png'},
      ]);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('every type the drop takes is taken, in any case of its '
        'extension', (t) async {
      final files = [
        '/p/a.png',
        '/p/b.JPG',
        '/p/c.jpeg',
        '/p/d.gif',
        '/p/e.WebP',
      ];
      final (runtime, ui, read) = await clipboard(
        t,
        files: files,
        text: files.join('\n'),
        bytes: {for (final f in files) f: _png},
      );
      await paste(t);
      expect(read, files);
      expect(ui.images.items, hasLength(5));
      expect(composerText(t), isEmpty);
      await runtime.dispose();
    }, variant: mac);

    for (final ext in ['bmp', 'tif', 'tiff']) {
      testWidgets('a .$ext file is attached as a PNG, as when dropped', (
        t,
      ) async {
        final file = '/p/scan.$ext';
        final (runtime, ui, read) = await clipboard(
          t,
          files: [file],
          text: 'scan.$ext',
          bytes: {file: _bmp()},
        );
        await paste(t);
        // The codec answers on the engine's own thread: real time.
        for (var i = 0; i < 100 && ui.images.items.isEmpty; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await t.pump();
        }
        expect(read, [file]);
        expect(ui.images.items, hasLength(1));
        expect(ui.images.items.single.mime, 'image/png');
        expect(composerText(t), isEmpty);
        await runtime.dispose();
      }, variant: mac);
    }

    testWidgets('files that are no images: the text on the clipboard is '
        'pasted as now, and the files are not read', (t) async {
      const names = 'report.pdf\nnotes.txt';
      final (runtime, ui, read) = await clipboard(
        t,
        files: ['/docs/report.pdf', '/docs/notes.txt'],
        text: names,
        image: _png,
      );
      await paste(t);
      expect(composerText(t), names);
      expect(read, isEmpty);
      expect(ui.images.items, isEmpty);
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('images among other files: the images attach, the others '
        'are left alone, and no text is pasted', (t) async {
      const files = ['/d/report.pdf', '/d/a.png', '/d/notes.txt', '/d/b.jpg'];
      final (runtime, ui, read) = await clipboard(
        t,
        files: files,
        text: 'report.pdf\na.png\nnotes.txt\nb.jpg',
        bytes: {'/d/a.png': _png, '/d/b.jpg': _png},
      );
      await paste(t);
      expect(read, ['/d/a.png', '/d/b.jpg']);
      expect(ui.images.items, hasLength(2));
      expect(composerText(t), isEmpty);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('no file, but text and a picture of it (cells of a '
        'spreadsheet): the text wins, as before', (t) async {
      final (runtime, ui, read) = await clipboard(
        t,
        files: const [],
        text: cells,
        image: _png,
      );
      await paste(t);
      expect(composerText(t), cells);
      expect(ui.images.items, isEmpty);
      expect(ui.images.note, isNull);
      expect(read, isEmpty);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('no file and no text (a screenshot): the picture still '
        'attaches', (t) async {
      final (runtime, ui, read) = await clipboard(
        t,
        files: const [],
        image: _png,
      );
      await paste(t);
      expect(ui.images.items, hasLength(1));
      expect(composerText(t), isEmpty);
      expect(read, isEmpty);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('the limits are the drop\'s: at most five, the sixth is said '
        'and no file past the fifth is read', (t) async {
      final files = [for (var i = 0; i < 7; i++) '/shots/$i.png'];
      final (runtime, ui, read) = await clipboard(
        t,
        files: files,
        text: files.join('\n'),
        bytes: {for (final f in files) f: _png},
      );
      await paste(t);
      expect(ui.images.items, hasLength(5));
      expect(read, files.take(5));
      expect(find.text('At most 5 images per message.'), findsOneWidget);
      expect(composerText(t), isEmpty);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('images already attached count: a copied file is a sixth '
        'one too many', (t) async {
      mockClipboardText(t, null);
      final (_, runtime, ui) = await dock(
        t,
        const FakeScenario(),
        clipboard: _png,
      );
      for (var i = 0; i < 5; i++) {
        await paste(t);
      }
      expect(ui.images.items, hasLength(5));
      // Now a file is copied (Finder has no picture of it to offer).
      ui.clipboardImage = () async => null;
      ui.clipboardFiles = () async => ['/shots/6.png'];
      ui.readImageFile = (path) async => fail('nothing is read past the cap');
      await paste(t);
      expect(ui.images.items, hasLength(5));
      expect(find.text('At most 5 images per message.'), findsOneWidget);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('an agent that takes no images says so: nothing is attached '
        'and no name is pasted', (t) async {
      const file = '/Users/me/Desktop/shot.png';
      final (runtime, ui, _) = await clipboard(
        t,
        files: [file],
        text: 'shot.png',
        bytes: {file: _png},
        scenario: const FakeScenario(image: false),
      );
      await paste(t);
      expect(ui.images.items, isEmpty);
      expect(find.text('Claude does not take images.'), findsOneWidget);
      expect(composerText(t), isEmpty);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('a file that cannot be read (gone since it was copied) '
        'attaches nothing and says nothing', (t) async {
      final (runtime, ui, read) = await clipboard(
        t,
        files: ['/gone/shot.png'],
        text: 'shot.png',
      );
      await paste(t);
      // Why it could not be read is asked of the disk, in real time.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
      expect(read, ['/gone/shot.png']);
      expect(ui.images.items, isEmpty);
      expect(ui.images.note, isNull);
      await runtime.dispose();
    }, variant: mac);

    testWidgets('an image file over 10 MiB is said to be too large, as when '
        'dropped', (t) async {
      final dir = Directory.systemTemp.createTempSync('ai_paste_');
      addTearDown(() => dir.deleteSync(recursive: true));
      // A file one byte over the limit (nothing in it: it is not read).
      final big = File('${dir.path}/huge.png');
      final file = big.openSync(mode: FileMode.write);
      file.truncateSync(kAiImageMaxBytes + 1);
      file.closeSync();
      final (runtime, ui, read) = await clipboard(
        t,
        files: [big.path],
        text: 'huge.png',
      );
      await paste(t);
      for (var i = 0; i < 100 && ui.images.note == null; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await t.pump();
      }
      expect(read, [big.path], reason: 'the pane\'s reader gives up on it');
      expect(ui.images.items, isEmpty);
      expect(find.text('The image is too large (at most 10 MB).'), findsOne);
      expect(composerText(t), isEmpty);
      await runtime.dispose();
    }, variant: mac);
  });
}
