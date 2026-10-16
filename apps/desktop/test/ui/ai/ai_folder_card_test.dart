import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1 D5, §6: the folder card — "Choose a project folder" over a
/// conversation can be cancelled, and it does not take the conversation
/// (the text typed in the composer) away.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(ProviderContainer, FakeAiRuntimes)> workspace(
    WidgetTester t, {
    String? cwd,
    FakeScenario scenario = const FakeScenario(),
  }) async {
    final fakes = FakeAiRuntimes(scenario);
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiFolderExistsProvider.overrideWithValue(
          (path) async => path == testAiCwd,
        ),
      ],
    );
    openTestAiTab(w.container, cwd: cwd ?? testAiCwd);
    w.container.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (w.container, fakes);
  }

  Finder card() => find.byKey(const Key('ai.folder'));
  Finder cancel() => find.byKey(const Key('ai.folder.cancel'));
  Finder composer() => find.byKey(const Key('ai.composer'));

  TextField composerField(WidgetTester t) => t.widget<TextField>(composer());

  TextField folderField(WidgetTester t) =>
      t.widget<TextField>(find.byKey(const Key('ai.folder.field')));

  /// "Choose folder" as the card of a vanished folder calls it.
  void chooseFolder(WidgetTester t) {
    AiPaneScope.of(t.element(composer())).ui.onChooseFolder!();
  }

  testWidgets('Cancel closes the card and the conversation is back with what '
      'was typed in the composer, the keyboard in it', (t) async {
    final (c, _) = await workspace(t);
    await t.enterText(composer(), 'half a thought');
    await t.pump();
    chooseFolder(t);
    await t.pumpAndSettle();
    expect(card(), findsOneWidget);
    expect(composer(), findsNothing, reason: 'out of sight, not gone');
    expect(
      folderField(t).focusNode!.hasPrimaryFocus,
      isTrue,
      reason: 'the card has the keyboard',
    );
    await t.tap(cancel());
    await t.pumpAndSettle();
    expect(card(), findsNothing);
    expect(composerField(t).controller!.text, 'half a thought');
    expect(composerField(t).focusNode!.hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Esc in the field cancels too', (t) async {
    final (c, _) = await workspace(t);
    await t.enterText(composer(), 'kept');
    chooseFolder(t);
    await t.pumpAndSettle();
    expect(folderField(t).focusNode!.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(card(), findsNothing);
    expect(composerField(t).controller!.text, 'kept');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a vanished folder: "Choose folder" then Cancel goes back to '
      'the notice, nothing else changed', (t) async {
    final (c, fakes) = await workspace(t, cwd: '/gone/project');
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.chooseFolder')));
    await t.pumpAndSettle();
    expect(card(), findsOneWidget);
    await t.tap(cancel());
    await t.pumpAndSettle();
    expect(card(), findsNothing);
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    expect(find.byKey(const Key('ai.chooseFolder')), findsOneWidget);
    expect(fakes.requests.map((r) => r.cwd), ['/gone/project']);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('choosing another folder over a conversation starts a new '
      'runtime there and the new composer has the keyboard', (t) async {
    final (c, fakes) = await workspace(t);
    chooseFolder(t);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    expect(card(), findsNothing);
    expect(fakes.requests, hasLength(2));
    expect(composerField(t).focusNode!.hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a pane without any folder has nothing to cancel back to', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    final c = w.container;
    openTestAiTab(c, cwd: null);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(card(), findsOneWidget);
    expect(cancel(), findsNothing);
    expect(folderField(t).focusNode!.hasPrimaryFocus, isTrue);
    expect(c.read(terminalTabsProvider).tabs.last.ai!.cwd, isNull);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
