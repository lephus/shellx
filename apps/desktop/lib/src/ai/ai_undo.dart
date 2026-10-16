import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/remote.dart' show aiTurnsOf;

/// V2-2b B19: what reverting a turn (or the session) would put back, read
/// now by [AiUndo.plan].
sealed class AiUndoPlanResult {
  const AiUndoPlanResult();

  @override
  String toString() => '$runtimeType(…)';
}

/// A turn is running: a revert waits for it (the runtime refuses one
/// meanwhile).
final class AiUndoBusy extends AiUndoPlanResult {
  const AiUndoBusy();
}

/// The restore point could not be read: git did not answer, or the turn has
/// none.
final class AiUndoFailed extends AiUndoPlanResult {
  const AiUndoFailed();
}

/// Nothing of it is changed any more (put back by hand meanwhile).
final class AiUndoNothing extends AiUndoPlanResult {
  const AiUndoNothing();
}

/// The files to put back ([paths]) and those of them changed after the turn
/// ended ([after]).
final class AiUndoPlan extends AiUndoPlanResult {
  const AiUndoPlan({
    required this.turn,
    required this.paths,
    required this.after,
  });

  /// The turn whose restore point the files go back to; null: the
  /// session's first.
  final int? turn;

  /// The changed files, relative to the session folder, as git lists them.
  final List<String> paths;

  /// The files changed after the turn ended — every file when that is not
  /// known (a turn that ended without its end tree: the agent died, "Dừng
  /// hẳn").
  final Set<String> after;

  /// The files that ask first (B14): changed by the turn and again after it.
  List<String> get touched => [
    for (final path in paths)
      if (after.contains(path)) path,
  ];

  /// Some files did not change after the turn: "Only revert unchanged
  /// files" is a choice.
  bool get someClean => touched.length < paths.length;
}

/// How [AiUndo.apply] went.
final class AiUndoDone {
  const AiUndoDone({required this.ok, this.count = 0, this.busy = false});

  /// The files were put back.
  final bool ok;

  /// How many files were put back.
  final int count;

  /// Not put back because a turn started meanwhile: the runtime refuses a
  /// revert while one runs.
  final bool busy;

  @override
  String toString() => 'AiUndoDone(…)';
}

/// V2-2b B19: undo of a turn or of the whole session without a widget —
/// the Changes panel ("Revert turn", "Revert session", one file) and a
/// phone's `ai.revert` share it. [plan] reads what would go back now; the
/// caller asks the user when [AiUndoPlan.touched] is not empty (V2-1 B14);
/// [apply] puts the files back.
final class AiUndo {
  AiUndo(this.runtime);

  final AiRuntime runtime;

  /// The files changed since [turn] began (null: since the session's first
  /// turn), [only] that one when given, and which of them changed after the
  /// turn ended (null [turn]: after the last turn that finished).
  Future<AiUndoPlanResult> plan({int? turn, String? only}) async {
    if (runtime.state.turn != null) return const AiUndoBusy();
    final last = turn ?? aiTurnsOf(runtime.state).lastFinished;
    final changes = turn == null
        ? await runtime.sessionChanges()
        : await runtime.changesSince(turn);
    // git did not answer: said, never a silent nothing.
    if (changes == null) return const AiUndoFailed();
    final paths = [
      for (final c in changes)
        if (only == null || c.path == only) c.path,
    ];
    if (paths.isEmpty) return const AiUndoNothing();
    // A turn that ended without its end tree (the agent died, "Dừng hẳn")
    // cannot say what changed after it: any file may have, so every file
    // asks.
    final known = last == null
        ? const <String>{}
        : await runtime.changedAfterTurn(last);
    return AiUndoPlan(turn: turn, paths: paths, after: known ?? paths.toSet());
  }

  /// Puts the files of [plan] back — without the [AiUndoPlan.touched] ones
  /// when [keepTouched] ("Only revert unchanged files").
  Future<AiUndoDone> apply(AiUndoPlan plan, {required bool keepTouched}) async {
    final paths = keepTouched
        ? [
            for (final path in plan.paths)
              if (!plan.after.contains(path)) path,
          ]
        : plan.paths;
    if (paths.isEmpty) return const AiUndoDone(ok: true);
    final turn = plan.turn;
    var ok = false;
    try {
      ok = turn == null
          ? await runtime.revertSession(paths)
          : await runtime.revert(turn, paths);
    } on Object catch (error) {
      debugPrint('ShellX: revert failed: ${error.runtimeType}');
    }
    return AiUndoDone(
      ok: ok,
      count: ok ? paths.length : 0,
      // A turn that started meanwhile is why the runtime said no.
      busy: !ok && runtime.state.turn != null,
    );
  }
}
