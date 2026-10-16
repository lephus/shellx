import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/changes.dart';
import 'item_codec.dart' show aiTextDiffRegion;
import 'mirror.dart';
import 'wire.dart';

/// V2-2b B19: the most files one `ai.changes` answer lists; the others are
/// counted in [AiChangesView.more] and seen on the computer.
const int kAiChangesMax = 200;

/// V2-2b B19: one side of a file's diff on the phone's diff page, before the
/// JSON is cut harder to fit ([aiFileDiffBody]).
const int kAiFileDiffSideBytes = 20 * 1024;

/// One file changed since a restore point, as a phone lists it (V2-2b B19).
final class AiChangedFile with Redacted {
  const AiChangedFile({
    required this.path,
    required this.kind,
    this.plus,
    this.minus,
  });

  /// [change] as a phone lists it.
  factory AiChangedFile.of(FileChange change) => AiChangedFile(
    path: change.path,
    kind: switch (change.kind) {
      ChangeKind.added => 'a',
      ChangeKind.modified => 'm',
      ChangeKind.deleted => 'd',
    },
    plus: change.added,
    minus: change.removed,
  );

  /// Relative to the session folder, `/` separators.
  final String path;

  /// `a` (added), `m` (modified) or `d` (deleted).
  final String kind;

  /// Lines added and removed; null for a binary file.
  final int? plus;
  final int? minus;

  bool get binary => plus == null;

  Map<String, Object?> toJson() => {
    'p': path,
    'k': kind,
    'plus': ?plus,
    'minus': ?minus,
  };

  /// Null without a path; an unknown kind reads as `m`.
  static AiChangedFile? fromJson(Map<String, Object?> j) {
    final path = jString(j, 'p');
    if (path == null || path.isEmpty) return null;
    return AiChangedFile(
      path: path,
      kind: switch (jString(j, 'k')) {
        'a' => 'a',
        'd' => 'd',
        _ => 'm',
      },
      plus: jInt(j, 'plus'),
      minus: jInt(j, 'minus'),
    );
  }
}

/// What `ai.changes` answers (V2-2b B19), as the desktop's Changes panel
/// shows it: the files changed since [turn] began (`scope` `turn`) or since
/// the session's first turn (`session`), those of them changed again after
/// the turn ended ([after]), the turns that have a restore point, and why
/// undo is off ([off], an `UndoOff` name) while no turn has one.
final class AiChangesView with Redacted {
  const AiChangesView({
    required this.scope,
    this.turn,
    this.files = const [],
    this.after = const [],
    this.first,
    this.last,
    this.done,
    this.off,
    this.more = 0,
  });

  /// `turn` or `session`.
  final String scope;
  final int? turn;
  final List<AiChangedFile> files;
  final List<String> after;

  /// The first and the last turn with a restore point (a running turn
  /// counts), and the last one that finished with one.
  final int? first;
  final int? last;
  final int? done;
  final String? off;

  /// Files left out of [files] (more than [kAiChangesMax], or than a body
  /// holds).
  final int more;

  Map<String, Object?> toJson() => {
    'scope': scope,
    'turn': ?turn,
    'files': [for (final f in files) f.toJson()],
    'after': after,
    'turns': {'first': ?first, 'last': ?last, 'done': ?done},
    'off': ?off,
    if (more > 0) 'more': more,
  };

  /// Never throws: what is not as written reads as absent.
  static AiChangesView fromJson(Map<String, Object?> j) {
    final turns = jMap(j, 'turns') ?? const <String, Object?>{};
    return AiChangesView(
      scope: jString(j, 'scope') == 'turn' ? 'turn' : 'session',
      turn: jInt(j, 'turn'),
      files: [for (final f in jMaps(j, 'files')) ?AiChangedFile.fromJson(f)],
      after: jStrings(j, 'after'),
      first: jInt(turns, 'first'),
      last: jInt(turns, 'last'),
      done: jInt(turns, 'done'),
      off: jString(j, 'off'),
      more: max(0, jInt(j, 'more') ?? 0),
    );
  }
}

/// [view] as an `ai.changes` body within [kAiRecordBytes]: at most
/// [kAiChangesMax] files, fewer while the JSON is too big (paths are as long
/// as a project makes them); what is left out is counted in `more`, and the
/// [AiChangesView.after] paths of files left out go with them.
Uint8List encodeChangesView(AiChangesView view) {
  final files = view.files.take(kAiChangesMax).toList();
  String json() {
    final kept = {for (final f in files) f.path};
    return jsonEncode(
      AiChangesView(
        scope: view.scope,
        turn: view.turn,
        files: files,
        after: [
          for (final path in view.after)
            if (kept.contains(path)) path,
        ],
        first: view.first,
        last: view.last,
        done: view.done,
        off: view.off,
        more: view.more + view.files.length - files.length,
      ).toJson(),
    );
  }

  var text = json();
  while (utf8Length(text) > kAiRecordBytes && files.isNotEmpty) {
    files.removeRange(files.length - max(1, files.length ~/ 10), files.length);
    text = json();
  }
  return Uint8List.fromList(utf8.encode(text));
}

/// V2-2b B19: the body of `ai.diff` for [path] — its changed region with 3
/// lines around it, [oldText] null for a file that was not there — each side
/// within [side] bytes, halved while the JSON is over [kAiRecordBytes] (a
/// file of control characters grows six times when escaped).
/// Null when even a sixteenth does not fit: the window answers `too_big`.
Map<String, Object?>? aiFileDiffBody({
  required String path,
  String? oldText,
  required String newText,
  int side = kAiFileDiffSideBytes,
}) {
  for (final scale in const [1, 2, 4, 8, 16]) {
    final region = aiTextDiffRegion(
      path: path,
      oldText: oldText,
      newText: newText,
      side: side ~/ scale,
    );
    if (utf8Length(jsonEncode(region)) <= kAiRecordBytes) return region;
  }
  return null;
}

/// V2-2b B19: the region of an `ai.diff` body as the phone draws it; null for
/// `{"binary": true}`, `{"missing": true}` or a body it cannot read.
MirrorDiff? aiFileDiffOf(Map<String, Object?> body) {
  if (jBool(body, 'binary') || jBool(body, 'missing')) return null;
  final next = jString(body, 'new');
  if (next == null) return null;
  return MirrorDiff(
    path: jString(body, 'path') ?? '',
    oldText: jBool(body, 'created') ? null : jString(body, 'old') ?? '',
    newText: next,
    plus: jInt(body, 'plus') ?? 0,
    minus: jInt(body, 'minus') ?? 0,
    cut: jBool(body, 'cut'),
  );
}

/// What `ai.revert` asks before it puts back files changed after the turn
/// (`confirm`, V2-2b B19, the desktop's B14 question): those files (as many
/// as fit, [more] after them), whether some files did not change after the
/// turn ("Only unchanged files" is then a choice), and how many files the
/// revert would put back in all.
final class AiRevertConfirm with Redacted {
  const AiRevertConfirm({
    this.touched = const [],
    this.more = 0,
    this.someClean = false,
    this.files = 0,
  });

  final List<String> touched;
  final int more;
  final bool someClean;
  final int files;

  /// The files changed after the turn in all.
  int get touchedCount => touched.length + more;

  Map<String, Object?> toJson() => {
    'touched': touched,
    if (more > 0) 'more': more,
    'some_clean': someClean,
    'files': files,
  };

  static AiRevertConfirm fromJson(Map<String, Object?> j) => AiRevertConfirm(
    touched: jStrings(j, 'touched'),
    more: max(0, jInt(j, 'more') ?? 0),
    someClean: jBool(j, 'some_clean'),
    files: max(0, jInt(j, 'files') ?? 0),
  );
}

/// The body of a `confirm` answer to `ai.revert`: [touched] as long as they
/// fit in half a record (the rest counted), [someClean], and [total] files.
Uint8List encodeRevertConfirm({
  required List<String> touched,
  required bool someClean,
  required int total,
}) {
  final kept = <String>[];
  var size = 0;
  for (final path in touched) {
    final bytes = utf8Length(jsonEncode(path)) + 1;
    if (size + bytes > kAiRecordBytes ~/ 2) break;
    kept.add(path);
    size += bytes;
  }
  return encodeBody(
    AiRevertConfirm(
      touched: kept,
      more: touched.length - kept.length,
      someClean: someClean,
      files: total,
    ).toJson(),
  );
}
