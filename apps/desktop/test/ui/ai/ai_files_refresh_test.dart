import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_gitignore.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// A project whose `lib` listings land when the test says: each call reads
/// the project at once (what the folder held then) and waits for its gate —
/// two isolates finishing in the other order.
final class _GatedFiles implements AiProjectFiles {
  _GatedFiles(this.inner);

  final FakeProject inner;
  final gates = <Completer<void>>[];

  @override
  Future<List<AiDirEntry>> list(String root, String dir) async {
    final entries = await inner.list(root, dir);
    if (dir == 'lib') {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
    }
    return entries;
  }

  @override
  Future<AiFileContent> read(String path) => inner.read(path);

  @override
  Future<List<String>> index(String root) => inner.index(root);
}

/// V2-1 D18, D16: the Files tree and the `@` index look at the project again
/// when a turn ends — with undo off too — and when a folder opens.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A pane on [files] with undo OFF (no restore points: no turn has a
  /// checkpoint), whose agent answers each message with `ok`.
  Future<ProviderContainer> pane(
    WidgetTester t,
    AiProjectFiles files, {
    int turns = 0,
  }) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          for (var i = 0; i < turns; i++) [FakeSteps.text('ok')],
        ],
      ),
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    openTestAiTab(w.container, cwd: testAiCwd);
    w.container.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return w.container;
  }

  Future<void> say(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const Key('ai.composer')), text);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
  }

  Future<void> filesTab(WidgetTester t) async {
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel.files')));
    await t.pumpAndSettle();
  }

  Finder file(String path) => find.byKey(ValueKey('ai.file.$path'));

  testWidgets('undo off: the tree looks again when a turn ends (no restore '
      'point to count)', (t) async {
    final project = FakeProject(testAiCwd, {'README.md': '# Hi\n'});
    final c = await pane(t, project, turns: 1);
    await filesTab(t);
    expect(file('README.md'), findsOneWidget);
    expect(file('NEW.md'), findsNothing);
    project.files['NEW.md'] = 'n\n'; // what the agent did
    await say(t, 'go');
    expect(file('NEW.md'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('undo off: `@` offers the files the turn made', (t) async {
    final project = FakeProject(testAiCwd, {'README.md': '# Hi\n'});
    final c = await pane(t, project, turns: 1);
    // The first `@` reads the project once.
    await t.enterText(find.byKey(const Key('ai.composer')), '@');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.composer')), '');
    await t.pumpAndSettle();
    project.files['NEW.md'] = 'n\n';
    await say(t, 'go');
    await t.enterText(find.byKey(const Key('ai.composer')), '@NEW');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    expect(find.text('NEW.md'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a folder that is opened again is listed again (not what it '
      'held the first time)', (t) async {
    final project = FakeProject(testAiCwd, {'lib/a.dart': 'one\n'});
    final c = await pane(t, project);
    await filesTab(t);
    await t.tap(file('lib'));
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsOneWidget);
    await t.tap(file('lib')); // closed
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsNothing);
    project.files['lib/b.dart'] = 'two\n';
    await t.tap(file('lib')); // opened again
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsOneWidget);
    expect(file('lib/b.dart'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the rows already there stay until the new listing lands', (
    t,
  ) async {
    final project = FakeProject(testAiCwd, {'lib/a.dart': 'one\n'});
    final gated = _GatedFiles(project);
    final c = await pane(t, gated);
    await filesTab(t);
    await t.tap(file('lib'));
    await t.pump();
    gated.gates[0].complete();
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsOneWidget);
    await t.tap(file('lib')); // closed
    await t.pump();
    project.files['lib/b.dart'] = 'two\n';
    await t.tap(file('lib')); // opened again: listing 2 waits
    await t.pump();
    expect(gated.gates, hasLength(2));
    expect(file('lib/a.dart'), findsOneWidget, reason: 'no empty flash');
    expect(file('lib/b.dart'), findsNothing);
    gated.gates[1].complete();
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsOneWidget);
    expect(file('lib/b.dart'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('an older listing that lands after a newer one never wins', (
    t,
  ) async {
    final project = FakeProject(testAiCwd, {'lib/a.dart': 'one\n'});
    final gated = _GatedFiles(project);
    final c = await pane(t, gated);
    await filesTab(t);
    await t.tap(file('lib')); // listing 1 (a.dart) waits
    await t.pump();
    await t.tap(file('lib')); // closed before it landed
    await t.pump();
    project.files['lib/b.dart'] = 'two\n';
    await t.tap(file('lib')); // listing 2 (a.dart, b.dart) waits
    await t.pump();
    expect(gated.gates, hasLength(2));
    gated.gates[1].complete(); // the newer one lands first…
    await t.pumpAndSettle();
    expect(file('lib/b.dart'), findsOneWidget);
    gated.gates[0].complete(); // …and the older one later
    await t.pumpAndSettle();
    expect(file('lib/a.dart'), findsOneWidget);
    expect(file('lib/b.dart'), findsOneWidget, reason: 'the older one lost');
    await disposeWorkspace(t, c);
  }, variant: mac);
}
