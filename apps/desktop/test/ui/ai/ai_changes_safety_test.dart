import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart' show TextBlock;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/ai/ai_changes_panel.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// Reads that fail on demand: git answering nothing (a locked repository,
/// a full disk). Everything else is the [FakeProject]'s.
final class _FlakyStore implements Checkpoints {
  _FlakyStore(this.project);

  final FakeProject project;
  var failReads = false;

  @override
  UndoOff? get off => project.off;

  @override
  Future<Checkpoint?> snapshot(String ref) => project.snapshot(ref);

  @override
  Future<String?> currentTree() => project.currentTree();

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) {
    if (failReads) throw StateError('git did not answer');
    return project.changes(fromTree, toTree);
  }

  @override
  Future<Set<String>> changedSince(String tree) {
    if (failReads) throw StateError('git did not answer');
    return project.changedSince(tree);
  }

  @override
  Future<List<int>?> fileAt(String treeish, String path) =>
      project.fileAt(treeish, path);

  @override
  Future<void> restore(String treeish, Iterable<String> paths) =>
      project.restore(treeish, paths);
}

/// V2-1 §4.4, D12, B14: what the Changes panel and undo do when they do not
/// know enough — an unknown end of a turn, a git that does not answer, undo
/// off — and the notes at its foot.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// Turn 1 edits `lib/a.dart`, adds `new.txt` and deletes `old.txt`.
  FakeProject project() {
    final files = FakeProject(testAiCwd, {
      'lib/a.dart': 'one\n',
      'old.txt': 'gone\n',
    });
    files.onSnapshot = (ref) {
      if (!ref.endsWith('/1')) return;
      files.files
        ..['lib/a.dart'] = 'one\ntwo\n'
        ..['new.txt'] = 'hi\n'
        ..remove('old.txt');
    };
    return files;
  }

  Future<(ProviderContainer, FakeAiRuntimes)> pane(
    WidgetTester t,
    FakeProject files, {
    Checkpoints? store,
    List<List<Map<String, Object?>>> turns = const [],
  }) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(turns: turns),
      checkpoints: store ?? files,
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
    return (w.container, fakes);
  }

  Future<void> say(WidgetTester t, String text, {bool settle = true}) async {
    await t.enterText(find.byKey(const Key('ai.composer')), text);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    if (settle) {
      await t.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await t.pump();
      }
    }
  }

  Future<void> openPanel(WidgetTester t) async {
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
  }

  Finder inPanel(Finder finder) => find.descendant(
    of: find.byKey(const Key('ai.sidePanel')),
    matching: finder,
  );

  Finder note() => find.byKey(const Key('ai.changes.note'));

  test('aiLastEndedTurn: the last turn that ended, with a restore point or '
      'without one (undo off)', () {
    final s = AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/w');
    expect(aiLastEndedTurn(s), isNull);
    s.beginTurn([const TextBlock('a')], DateTime(2026));
    expect(aiLastEndedTurn(s), isNull, reason: 'it still runs');
    s.endTurn(outcome: TurnOutcome.finished, at: DateTime(2026));
    expect(aiLastEndedTurn(s), 1);
    expect(
      aiTurnsOf(s).lastFinished,
      isNull,
      reason: 'the old reading: only turns with a restore point',
    );
    s.beginTurn([const TextBlock('b')], DateTime(2026));
    expect(aiLastEndedTurn(s), 1);
    s.endTurn(outcome: TurnOutcome.interrupted, at: DateTime(2026));
    expect(aiLastEndedTurn(s), 2);
  });

  testWidgets('a turn that ended without its end tree (the agent died) asks '
      'about every file: Cancel keeps them, Revert all goes', (t) async {
    final files = project();
    final (c, _) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.exit(1)],
      ],
    );
    await say(t, 'go');
    expect(find.textContaining('was interrupted'), findsOneWidget);
    // What the user did meanwhile: the panel has no way to know.
    files.files['new.txt'] = 'mine\n';
    await openPanel(t);
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    expect(find.text('Some files changed after this turn'), findsOneWidget);
    expect(find.byKey(const Key('ai.revert.cancel')), findsOneWidget);
    expect(find.byKey(const Key('ai.revert.all')), findsOneWidget);
    expect(
      find.byKey(const Key('ai.revert.clean')),
      findsNothing,
      reason: 'no file is known to be unchanged',
    );
    await t.tap(find.byKey(const Key('ai.revert.cancel')));
    await t.pumpAndSettle();
    expect(files.restored, isEmpty);
    expect(files.files['new.txt'], 'mine\n');
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.revert.all')));
    await t.pumpAndSettle();
    expect(files.restored.single.$2, ['lib/a.dart', 'new.txt', 'old.txt']);
    expect(files.files, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'});
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('"Revert session" asks too when the last turn has no end tree; '
      'a turn that ended well still reverts without a question', (t) async {
    final files = project();
    final (c, _) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.text('Done.')],
      ],
    );
    await say(t, 'go');
    await openPanel(t);
    await t.tap(find.byKey(const Key('ai.changes.session')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    expect(
      find.text('Some files changed after this turn'),
      findsNothing,
      reason: 'the end tree is known and nothing changed after it',
    );
    expect(files.files, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'});
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('git does not answer: Revert says so (no silent nothing), and '
      'the panel says it could not read — not "No turn yet"', (t) async {
    final files = project();
    final store = _FlakyStore(files);
    final (c, _) = await pane(
      t,
      files,
      store: store,
      turns: [
        [FakeSteps.text('Done.')],
      ],
    );
    await say(t, 'go');
    await openPanel(t);
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsOneWidget);
    store.failReads = true;
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai.change.new.txt')),
        matching: find.byIcon(Icons.undo),
      ),
    );
    await t.pumpAndSettle();
    expect(note(), findsOneWidget);
    expect(
      t.widget<Text>(note()).data,
      'The revert did not work.',
      reason: 'the read failed, nothing was reverted',
    );
    expect(files.restored, isEmpty);
    // The panel reads again (the scope changes) and git still says nothing.
    await t.tap(find.byKey(const Key('ai.changes.session')));
    await t.pumpAndSettle();
    expect(inPanel(find.textContaining('No turn yet')), findsNothing);
    expect(
      inPanel(find.text('Something went wrong (changes). Try again.')),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('undo off: the panel gives the reason, not "No turn yet"', (
    t,
  ) async {
    final files = project()..off = UndoOff.noGit;
    final (c, _) = await pane(t, files);
    await openPanel(t);
    expect(
      inPanel(find.text('Undo is off for this project (git was not found)')),
      findsOneWidget,
    );
    expect(inPanel(find.textContaining('No turn yet')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('with undo working and no turn yet the panel still explains '
      'how it works', (t) async {
    final files = project();
    final (c, _) = await pane(t, files);
    await openPanel(t);
    expect(inPanel(find.textContaining('No turn yet')), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('"Wait for the running turn to finish." goes when the turn '
      'ends (it is no longer true)', (t) async {
    final files = project();
    final (c, fakes) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.text('Done.')],
        [FakeSteps.waitCancel()],
      ],
    );
    await say(t, 'one');
    await say(t, 'two', settle: false);
    // Turn 1's summary offers "Revert turn" while turn 2 runs.
    await t.tap(find.byKey(const Key('ai.turn.revert')));
    await t.pump();
    await t.pump();
    expect(note(), findsOneWidget);
    expect(t.widget<Text>(note()).data, 'Wait for the running turn to finish.');
    expect(files.restored, isEmpty);
    fakes.made.single.cancel();
    await t.pumpAndSettle();
    expect(find.textContaining('Stopped turn 2'), findsOneWidget);
    expect(note(), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a turn that starts while the question is open: the revert '
      'says to wait — it did not fail', (t) async {
    final files = project();
    final (c, fakes) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.text('Done.')],
        [FakeSteps.waitCancel()],
      ],
    );
    await say(t, 'one');
    files.files['new.txt'] = 'mine\n'; // so that the question is asked
    await openPanel(t);
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    expect(find.text('Some files changed after this turn'), findsOneWidget);
    // Something else starts a turn while the dialog is open.
    unawaited(fakes.made.single.send([const TextBlock('two')]));
    for (var i = 0; i < 5; i++) {
      await t.pump();
    }
    expect(fakes.made.single.state.turn, isNotNull);
    await t.tap(find.byKey(const Key('ai.revert.all')));
    await t.pump();
    await t.pump();
    expect(t.widget<Text>(note()).data, 'Wait for the running turn to finish.');
    expect(files.restored, isEmpty);
    fakes.made.single.cancel();
    await t.pumpAndSettle();
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('"Reverted N files." goes when the scope changes or the panel '
      'closes (it is old news)', (t) async {
    final files = project();
    final (c, _) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.text('Done.')],
      ],
    );
    await say(t, 'go');
    await openPanel(t);
    Future<void> revert(String path) async {
      await t.tap(
        find.descendant(
          of: find.byKey(ValueKey('ai.change.$path')),
          matching: find.byIcon(Icons.undo),
        ),
      );
      await t.pumpAndSettle();
    }

    await revert('new.txt');
    expect(t.widget<Text>(note()).data, 'Reverted 1 file.');
    await t.tap(find.byKey(const Key('ai.changes.session')));
    await t.pumpAndSettle();
    expect(note(), findsNothing);
    // Another file; closing the panel and opening it again clears too.
    await revert('old.txt');
    expect(t.widget<Text>(note()).data, 'Reverted 1 file.');
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    expect(note(), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Reverting a file that is no longer changed refreshes the '
      'panel instead of doing nothing', (t) async {
    final files = project();
    final (c, _) = await pane(
      t,
      files,
      turns: [
        [FakeSteps.text('Done.')],
      ],
    );
    await say(t, 'go');
    await openPanel(t);
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsOneWidget);
    // The user removed it by hand; the panel does not watch the disk.
    files.files.remove('new.txt');
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai.change.new.txt')),
        matching: find.byIcon(Icons.undo),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsNothing);
    expect(files.restored, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
