import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart' show TextBlock;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_undo.dart';

import '../support/ai_fakes.dart';
import '../support/ai_parts.dart';
import '../support/fake_project.dart';

/// Turn 1 edits `lib/a.dart`, adds `new.txt` and deletes `old.txt` (the
/// Changes panel tests' project); a turn 2, when there is one, edits `b.txt`.
FakeProject _project() {
  final files = FakeProject(testAiCwd, {
    'lib/a.dart': 'one\n',
    'old.txt': 'gone\n',
    'b.txt': 'b\n',
  });
  files.onSnapshot = (ref) {
    if (ref.endsWith('/1')) {
      files.files
        ..['lib/a.dart'] = 'one\ntwo\n'
        ..['new.txt'] = 'hi\n'
        ..remove('old.txt');
    } else if (ref.endsWith('/2')) {
      files.files['b.txt'] = 'b2\n';
    }
  };
  return files;
}

const _before = {'lib/a.dart': 'one\n', 'old.txt': 'gone\n', 'b.txt': 'b\n'};

/// Reads that fail on demand: git answering nothing.
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
  Future<Set<String>> changedSince(String tree) => project.changedSince(tree);

  @override
  Future<List<int>?> fileAt(String treeish, String path) =>
      project.fileAt(treeish, path);

  @override
  Future<void> restore(String treeish, Iterable<String> paths) =>
      project.restore(treeish, paths);
}

Future<void> _until(bool Function() test) async {
  for (var i = 0; i < 400 && !test(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(test(), isTrue, reason: 'condition not reached');
}

/// A runtime over [store] whose first turn ran ([turns]: the fake agent's
/// steps, one list per prompt; the last repeats).
Future<AiRuntime> _afterTurn(
  Checkpoints store, {
  List<List<Map<String, Object?>>>? turns,
}) async {
  final fakes = FakeAiRuntimes(
    FakeScenario(
      turns:
          turns ??
          [
            [FakeSteps.text('Done.')],
          ],
    ),
    checkpoints: store,
  );
  final runtime = partRuntime(fakes);
  addTearDown(runtime.dispose);
  await runtime.start();
  expect(await runtime.send([const TextBlock('go')]), isTrue);
  await runtime.whenIdle();
  expect(runtime.checkpointOf(1), isNotNull, reason: 'turn 1 has a restore');
  return runtime;
}

/// V2-2b B19: undo without a widget — what the Changes panel and a phone's
/// revert share.
void main() {
  test(
    'a plan lists what the turn changed; nothing changed after it',
    () async {
      final files = _project();
      final runtime = await _afterTurn(files);
      final plan = await AiUndo(runtime).plan(turn: 1) as AiUndoPlan;
      expect(plan.turn, 1);
      expect(plan.paths, ['lib/a.dart', 'new.txt', 'old.txt']);
      expect(plan.touched, isEmpty);
      expect(plan.someClean, isTrue);
      final done = await AiUndo(runtime).apply(plan, keepTouched: false);
      expect((done.ok, done.count, done.busy), (true, 3, false));
      expect(files.files, _before);
    },
  );

  test('a file changed after the turn is touched; keepTouched leaves it, '
      'and without it every file goes back', () async {
    final files = _project();
    final runtime = await _afterTurn(files);
    files.files['new.txt'] = 'mine\n'; // the user, on the computer
    final undo = AiUndo(runtime);
    final plan = await undo.plan(turn: 1) as AiUndoPlan;
    expect(plan.touched, ['new.txt']);
    expect(plan.someClean, isTrue);
    final kept = await undo.apply(plan, keepTouched: true);
    expect((kept.ok, kept.count), (true, 2));
    expect(files.restored.single.$2, ['lib/a.dart', 'old.txt']);
    expect(files.files['new.txt'], 'mine\n');
    final again = await undo.plan(turn: 1) as AiUndoPlan;
    expect(again.paths, ['new.txt']);
    final all = await undo.apply(again, keepTouched: false);
    expect((all.ok, all.count), (true, 1));
    expect(files.files, _before);
  });

  test('one file alone ([only]); a file put back by hand is nothing', () async {
    final files = _project();
    final runtime = await _afterTurn(files);
    final undo = AiUndo(runtime);
    final one = await undo.plan(turn: 1, only: 'new.txt') as AiUndoPlan;
    expect(one.paths, ['new.txt']);
    files.files.remove('new.txt'); // removed by hand meanwhile
    expect(await undo.plan(turn: 1, only: 'new.txt'), isA<AiUndoNothing>());
    files.files
      ..['lib/a.dart'] = 'one\n'
      ..['old.txt'] = 'gone\n';
    expect(await undo.plan(turn: 1), isA<AiUndoNothing>());
  });

  test('git that does not answer: failed, nothing put back', () async {
    final files = _project();
    final store = _FlakyStore(files);
    final runtime = await _afterTurn(store);
    store.failReads = true;
    expect(await AiUndo(runtime).plan(turn: 1), isA<AiUndoFailed>());
    expect(await AiUndo(runtime).plan(), isA<AiUndoFailed>());
    expect(files.restored, isEmpty);
  });

  test(
    'a turn without a restore point is failed (undo was off for it)',
    () async {
      final runtime = await _afterTurn(_project());
      expect(await AiUndo(runtime).plan(turn: 7), isA<AiUndoFailed>());
    },
  );

  test('the whole session goes back to before the first turn', () async {
    final files = _project();
    final runtime = await _afterTurn(files);
    expect(await runtime.send([const TextBlock('more')]), isTrue);
    await runtime.whenIdle();
    final plan = await AiUndo(runtime).plan() as AiUndoPlan;
    expect(plan.turn, isNull);
    expect(plan.paths, ['b.txt', 'lib/a.dart', 'new.txt', 'old.txt']);
    expect(plan.touched, isEmpty, reason: 'nothing changed after turn 2');
    final done = await AiUndo(runtime).apply(plan, keepTouched: false);
    expect((done.ok, done.count), (true, 4));
    expect(files.files, _before);
  });

  test(
    'a turn that ended without its end tree asks about every file',
    () async {
      final files = _project();
      final runtime = await _afterTurn(
        files,
        turns: [
          [FakeSteps.exit(1)],
        ],
      );
      final plan = await AiUndo(runtime).plan(turn: 1) as AiUndoPlan;
      expect(plan.touched, plan.paths);
      expect(plan.someClean, isFalse);
    },
  );

  test('while a turn runs: busy, and nothing is read', () async {
    final files = _project();
    final runtime = await _afterTurn(
      files,
      turns: [
        [FakeSteps.text('Done.')],
        [FakeSteps.waitCancel()],
      ],
    );
    unawaited(runtime.send([const TextBlock('two')]));
    await _until(() => runtime.state.turn != null);
    expect(await AiUndo(runtime).plan(turn: 1), isA<AiUndoBusy>());
    runtime.cancel();
    await runtime.whenIdle();
    expect(files.restored, isEmpty);
  });

  test('a turn that starts between the plan and the revert: busy, nothing '
      'put back', () async {
    final files = _project();
    final runtime = await _afterTurn(
      files,
      turns: [
        [FakeSteps.text('Done.')],
        [FakeSteps.waitCancel()],
      ],
    );
    final undo = AiUndo(runtime);
    final plan = await undo.plan(turn: 1) as AiUndoPlan;
    unawaited(runtime.send([const TextBlock('two')]));
    await _until(() => runtime.state.turn != null);
    final done = await undo.apply(plan, keepTouched: false);
    expect((done.ok, done.count, done.busy), (false, 0, true));
    expect(files.restored, isEmpty);
    runtime.cancel();
    await runtime.whenIdle();
  });

  test('nothing of a plan or an outcome is printed', () {
    const plan = AiUndoPlan(turn: 1, paths: ['secret.txt'], after: {});
    expect(plan.toString(), 'AiUndoPlan(…)');
    expect(const AiUndoBusy().toString(), 'AiUndoBusy(…)');
    expect(const AiUndoDone(ok: true, count: 2).toString(), 'AiUndoDone(…)');
  });
}
