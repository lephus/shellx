import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/foundation.dart';

import 'ai_off_thread.dart';

enum DiffOp { same, added, removed }

/// One line of a line diff, with its numbers in the old and the new text.
@immutable
final class DiffLine {
  const DiffLine(this.op, this.text, {this.oldNo, this.newNo});
  final DiffOp op;
  final String text;
  final int? oldNo;
  final int? newNo;

  @override
  String toString() => '…';
}

/// Lines added and removed.
typedef DiffStat = ({int added, int removed});

DiffStat diffStat(List<DiffLine> lines) => (
  added: lines.where((l) => l.op == DiffOp.added).length,
  removed: lines.where((l) => l.op == DiffOp.removed).length,
);

/// Above this many lines in all, a diff runs off the UI isolate.
const int kInlineDiffLines = 2000;

List<String> _lines(String text) {
  // §6 Windows: shown without CR, so a CRLF file does not differ on every
  // line (revert still writes the exact bytes).
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// D17: a line-mode diff of `(old, new)`: diff_match_patch on one code unit
/// per distinct line (its own "line mode"). One argument, top-level: it
/// can run on another isolate ([lineDiff]).
List<DiffLine> computeLineDiff((String, String) texts) {
  final a = _lines(texts.$1);
  final b = _lines(texts.$2);
  final index = <String, int>{};
  final table = <String>[];
  // One BMP code unit per distinct line, never a surrogate.
  int code(String line) => index.putIfAbsent(line, () {
    table.add(line);
    final n = table.length;
    return n < 0xD800 ? n : n + 0x800;
  });
  final ca = a.map(code).toList();
  final cb = b.map(code).toList();
  if (table.length > 0xFFFF - 0x800 - 1) {
    // Too many distinct lines to encode: all out, all in.
    return [
      for (final (i, l) in a.indexed) DiffLine(DiffOp.removed, l, oldNo: i + 1),
      for (final (i, l) in b.indexed) DiffLine(DiffOp.added, l, newNo: i + 1),
    ];
  }
  String lineOf(int unit) => table[(unit < 0xD800 ? unit : unit - 0x800) - 1];
  final diffs = dmp.diff(
    String.fromCharCodes(ca),
    String.fromCharCodes(cb),
    checklines: false,
    timeout: 2,
  );
  final out = <DiffLine>[];
  var oldNo = 0;
  var newNo = 0;
  for (final d in diffs) {
    for (final unit in d.text.codeUnits) {
      final text = lineOf(unit);
      switch (d.operation) {
        case dmp.DIFF_EQUAL:
          out.add(DiffLine(DiffOp.same, text, oldNo: ++oldNo, newNo: ++newNo));
        case dmp.DIFF_DELETE:
          out.add(DiffLine(DiffOp.removed, text, oldNo: ++oldNo));
        default:
          out.add(DiffLine(DiffOp.added, text, newNo: ++newNo));
      }
    }
  }
  return out;
}

/// [computeLineDiff], off the UI isolate when the texts are long
/// (smoothness: the frame budget).
Future<List<DiffLine>> lineDiff(OffThread run, String old, String now) {
  final lines = '\n'.allMatches(old).length + '\n'.allMatches(now).length;
  return lines > kInlineDiffLines
      ? run(computeLineDiff, (old, now))
      : SynchronousFuture(computeLineDiff((old, now)));
}

/// The changed lines with [context] lines around each run; null stands for
/// the lines left out.
List<DiffLine?> withContext(List<DiffLine> lines, {int context = 3}) {
  final keep = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].op == DiffOp.same) continue;
    for (var j = i - context; j <= i + context; j++) {
      if (j >= 0 && j < lines.length) keep[j] = true;
    }
  }
  final out = <DiffLine?>[];
  var gap = false;
  for (var i = 0; i < lines.length; i++) {
    if (keep[i]) {
      out.add(lines[i]);
      gap = false;
    } else if (!gap) {
      out.add(null);
      gap = true;
    }
  }
  return out;
}
