import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';
import 'package:shellx_desktop/src/terminal/clipboard_media.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// A clipboard that holds files copied in Finder.
final class _CopiedFiles implements ClipboardMedia {
  const _CopiedFiles(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> files() async => paths;

  @override
  Future<Uint8List?> image() async => null;
}

/// V2-1 §4.1, D3, D5, D14, B11: the AI pane in the window.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  workspace(WidgetTester t, FakeAiRuntimes fakes) => pumpConfiguredWorkspace(
    t,
    platform: TargetPlatform.macOS,
    extra: [
      ...fakes.overrides,
      aiFolderExistsProvider.overrideWithValue(
        (path) async => path == testAiCwd,
      ),
    ],
  );

  testWidgets('a new AI tab starts its agent once shown; a prompt '
      'round-trips and names the tab (D2, D3)', (t) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Hello back')],
        ],
      ),
    );
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    expect(fakes.requests.single.cwd, testAiCwd);
    await t.enterText(find.byKey(const Key('ai.composer')), 'Say hello');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(fakes.agent().received, contains('session/prompt:Say hello'));
    expect(
      find.textContaining('Hello back', findRichText: true),
      findsOneWidget,
    );
    expect(
      t.widget<Text>(find.byKey(const Key('ai.header.title'))).data,
      'Say hello',
    );
    final tab = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id);
    expect(tab.label, 'Say hello');
    expect(tab.ai!.sessionId, 'sess-1');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('keys typed in the pane stay there: the window focus node '
      'keeps no terminal key handler (Backspace, arrows)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.windows,
      extra: fakes.overrides,
    );
    final c = w.container;
    // The shell tab's terminal held the window's focus node first.
    final shell = c.read(terminalTabsProvider).tabs.single.id;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'abcx');
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    final field = t.widget<TextField>(find.byKey(const Key('ai.composer')));
    expect(field.controller!.text, 'abc');
    expect(field.controller!.selection.baseOffset, 2);
    expect(w.local.views[shell]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('away and back: the pane keeps what was typed and its panel '
      'state (no rebuild from scratch)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final shell = c.read(terminalTabsProvider).tabs.single.id;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'half a thought');
    await t.pump();
    final tabs = c.read(terminalTabsProvider.notifier)..select(shell);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    tabs.select(ai.id);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      'half a thought',
    );
    expect(fakes.made, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B11: a tab opened in the background starts nothing until '
      'it is shown, then once', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final first = c.read(terminalTabsProvider).tabs.single.id;
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, isEmpty);
    final tabs = c.read(terminalTabsProvider.notifier)..select(ai.id);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    tabs.select(first);
    await t.pumpAndSettle();
    tabs.select(ai.id);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D5: without a folder the pane asks for one, then starts '
      'there', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: null);
    await t.pumpAndSettle();
    expect(find.text('Choose a project folder'), findsOneWidget);
    expect(fakes.made, isEmpty);
    await t.enterText(find.byKey(const Key('ai.folder.field')), 'not/here');
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    expect(
      find.text('Enter the absolute path of an existing folder.'),
      findsOneWidget,
    );
    await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    final pane = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id)
        .ai!;
    expect(pane.cwd, testAiCwd);
    expect(fakes.requests.single.cwd, testAiCwd);
    expect(fakes.launcher.channels, hasLength(1));
    expect(find.byKey(const Key('ai.composer')), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('§6: the folder is gone: "Choose folder" starts a new runtime '
      'in the chosen one', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: '/gone/project');
    await t.pumpAndSettle();
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    expect(fakes.launcher.channels, isEmpty);
    await t.tap(find.byKey(const Key('ai.chooseFolder')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    expect(fakes.requests.map((r) => r.cwd), ['/gone/project', testAiCwd]);
    expect(fakes.launcher.channels, hasLength(1));
    expect(find.text('The project folder no longer exists'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D14: a reopened session shows "Resume session" until it has '
      'loaded', (t) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        history: [
          {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Login fixed.'},
          },
        ],
      ),
    );
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
    await t.pump();
    expect(find.byKey(const Key('ai.resume')), findsOneWidget);
    expect(find.text('Loading the conversation…'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.resume')), findsNothing);
    expect(fakes.agent().received, contains('session/load:sess-9'));
    expect(
      find.textContaining('Login fixed.', findRichText: true),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('header: Terminal adds a shell under the pane; Zoom shows '
      'once split (D3, §4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    TerminalTab tab() =>
        c.read(terminalTabsProvider).tabs.firstWhere((x) => x.id == ai.id);
    expect(find.byKey(const Key('ai.zoom')), findsNothing);
    await t.tap(find.byKey(const Key('ai.terminal')));
    await t.pumpAndSettle();
    expect(tab().panes, hasLength(1));
    await t.tap(find.byKey(const Key('ai.zoom')));
    await t.pumpAndSettle();
    expect(tab().zoomedPaneId, ai.ai!.id);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⋯: View log shows the agent stderr; Settings › Agents opens '
      'Settings on that page (§4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more.log')));
    await t.pumpAndSettle();
    expect(
      t.widget<SelectableText>(find.byKey(const Key('ai.log.text'))).data,
      contains('RECV initialize'),
    );
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more.settings')));
    await t.pumpAndSettle();
    expect(find.byType(AgentsPage), findsOneWidget);
    expect(c.read(settingsStartPageProvider), isNull);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D21: ai-agent-claude = off stops a running Claude and the '
      'pane says why', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await workspace(t, fakes);
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels.single.exited, isFalse);
    w.fs.write(testConfigPaths().shellx, 'ai-agent-claude = off\n');
    await loadConfig(c);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels.single.stopCalls, 1);
    expect(
      find.text(
        'The Claude integration is turned off (ai-agent-claude = off).',
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('signed out: the composer waits and keeps the keyboard', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario(requireAuth: true));
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(find.text('Waiting for the agent…'), findsOneWidget);
    final field = t.widget<TextField>(find.byKey(const Key('ai.composer')));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    expect(field.readOnly, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('smoothness: a hidden pane hears nothing, then catches up '
      'once', (t) async {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: testAiCwd,
    );
    final frames = AiFrameNotifier(state)..active = false;
    addTearDown(frames.dispose);
    var heard = 0;
    frames.addListener(() => heard++);
    state
      ..touch()
      ..touch();
    await t.pump();
    expect(heard, 0);
    frames.active = true;
    await t.pump();
    expect(heard, 1);
  });

  testWidgets('⌘V of an image file copied in Finder attaches the picture: '
      'the pane asks the clipboard for files and reads the file itself', (
    t,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ai_pane_paste_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final shot = File('${dir.path}/shot.png')..writeAsBytesSync(_png);
    // Finder puts the name of a copied file on the clipboard as text too.
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'shot.png'} : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      clipboard: _CopiedFiles([shot.path]),
      extra: [
        ...fakes.overrides,
        aiFolderExistsProvider.overrideWithValue(
          (path) async => path == testAiCwd,
        ),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    // The pane reads the file off the disk: real time.
    for (
      var i = 0;
      i < 100 && find.byKey(const Key('ai.image.0')).evaluate().isEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await t.pump();
    }
    expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      isEmpty,
      reason: 'the name of the file is not pasted',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);
}
