import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// V2-1 §4.4, D12, B14: the Changes panel and undo.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A project where turn 1 edits `lib/a.dart`, adds `new.txt` and deletes
  /// `old.txt` (what the agent did, as the restore points see it).
  FakeProject project() =>
      FakeProject(testAiCwd, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'})
        ..onSnapshot = null;

  Future<(ProviderContainer, FakeAiRuntimes)> afterTurn(
    WidgetTester t,
    FakeProject files, {
    List<List<Map<String, Object?>>>? turns,
  }) async {
    files.onSnapshot = (ref) {
      if (!ref.endsWith('/1')) return;
      files.files
        ..['lib/a.dart'] = 'one\ntwo\n'
        ..['new.txt'] = 'hi\n'
        ..remove('old.txt');
    };
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns:
            turns ??
            [
              [FakeSteps.text('Done.')],
            ],
      ),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    if (turns == null) {
      await t.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await t.pump();
      }
    }
    return (c, fakes);
  }

  testWidgets('the panel lists this turn\'s files (M/A/D, +/−), shows a '
      'diff, and the restore point', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    expect(find.text('Turn 1 · 0:00 · 3 files changed'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    for (final path in ['lib/a.dart', 'new.txt', 'old.txt']) {
      expect(find.byKey(ValueKey('ai.change.$path')), findsOneWidget);
    }
    expect(find.text('Restore point: before turn 1 · ct1'), findsOneWidget);
    expect(find.text('Revert turn'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('ai.change.lib/a.dart')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.diff')), findsOneWidget);
    expect(find.text('compared with the start of the turn'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.diff.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.diff')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B14: a file changed after the turn asks first, Cancel has '
      'the focus; "Only revert unchanged files" keeps it', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    files.files['new.txt'] = 'mine\n';
    await t.tap(find.byKey(const Key('ai.turn.revert')));
    await t.pumpAndSettle();
    expect(find.text('Some files changed after this turn'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<TextButton>()?.key,
      const Key('ai.revert.cancel'),
    );
    await t.tap(find.byKey(const Key('ai.revert.clean')));
    await t.pumpAndSettle();
    expect(files.restored.single.$2, ['lib/a.dart', 'old.txt']);
    expect(files.files, {
      'lib/a.dart': 'one\n',
      'old.txt': 'gone\n',
      'new.txt': 'mine\n',
    });
    expect(find.text('Reverted 2 files.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('one file reverts alone; "Reviewed" stays with an unchanged '
      'file; "Whole session" reverts the session', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    final row = find.byKey(const ValueKey('ai.change.lib/a.dart'));
    await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai.change.new.txt')),
        matching: find.byIcon(Icons.undo),
      ),
    );
    await t.pumpAndSettle();
    expect(files.restored.single.$2, ['new.txt']);
    expect(files.files.containsKey('new.txt'), isFalse);
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsNothing);
    expect(
      t
          .widget<Checkbox>(
            find.descendant(of: row, matching: find.byType(Checkbox)),
          )
          .value,
      isTrue,
    );
    await t.tap(find.byKey(const Key('ai.changes.session')));
    await t.pumpAndSettle();
    expect(find.text('Revert session'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    expect(files.files, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'});
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('while a turn runs the changes show but revert waits', (t) async {
    final files = project();
    final (c, _) = await afterTurn(
      t,
      files,
      turns: [
        [FakeSteps.waitCancel()],
      ],
    );
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsOneWidget);
    expect(find.text('Wait for the running turn to finish.'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const Key('ai.changes.revert')))
          .onPressed,
      isNull,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    await disposeWorkspace(t, c);
  }, variant: mac);
}
