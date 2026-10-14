import 'dart:convert';

/// One line of a phone diff (V2-2 D6): ' ' context, '-' removed, '+' added.
typedef DiffLine = ({String mark, String text});

/// The lines of [text] as the computer counts them (`LineSplitter`: a line ends with `\n`, `\r\n` or
/// `\r`, and a final line ending does not start another line). A new file keeps its Windows line
/// endings on the wire, and the card's `plus` and `minus` count lines this way.
List<String> _lines(String text) => const LineSplitter().convert(text);

/// The lines of a diff region the desktop sent: the lines both sides share
/// at the start and at the end are context, the middle is removed then
/// added (the desktop already cut the region to its changed lines and 3
/// around them). [oldText] null: a new file, every line added.
List<DiffLine> diffLines(String? oldText, String newText) {
  final after = _lines(newText);
  if (oldText == null) return [for (final l in after) (mark: '+', text: l)];
  final before = _lines(oldText);
  var start = 0;
  while (start < before.length && start < after.length && before[start] == after[start]) {
    start++;
  }
  var endOld = before.length;
  var endNew = after.length;
  while (endOld > start && endNew > start && before[endOld - 1] == after[endNew - 1]) {
    endOld--;
    endNew--;
  }
  return [
    for (final l in before.sublist(0, start)) (mark: ' ', text: l),
    for (final l in before.sublist(start, endOld)) (mark: '-', text: l),
    for (final l in after.sublist(start, endNew)) (mark: '+', text: l),
    for (final l in after.sublist(endNew)) (mark: ' ', text: l),
  ];
}

/// A line that can open or close a code fence: three or more backticks or tildes (after any
/// indentation), then the rest of the line.
final _fenceLine = RegExp(r'^(`{3,}|~{3,})(.*)$');

/// [text] split into markdown blocks at blank lines outside code fences, so
/// a streaming answer re-renders only its last block (V2-1 D17, V2-2 §5).
/// A fence ends with a line of the same character, at least as long as the
/// one that opened it, and nothing after it (so a fence inside a longer one,
/// or of the other kind, is text of the outer one); one still open holds the
/// rest of the text.
List<String> markdownBlocks(String text) {
  final blocks = <String>[];
  final current = StringBuffer();
  String? fence;
  for (final line in _lines(text)) {
    final m = _fenceLine.firstMatch(line.trimLeft());
    if (m != null) {
      final marker = m.group(1)!;
      final rest = m.group(2)!;
      if (fence == null) {
        // A backtick fence has no backtick in its info string: "```a```" is inline code.
        if (!(marker.startsWith('`') && rest.contains('`'))) fence = marker;
      } else if (marker[0] == fence[0] && marker.length >= fence.length && rest.trim().isEmpty) {
        fence = null;
      }
    }
    if (fence == null && line.trim().isEmpty) {
      if (current.isNotEmpty) {
        blocks.add(current.toString());
        current.clear();
      }
      continue;
    }
    if (current.isNotEmpty) current.write('\n');
    current.write(line);
  }
  if (current.isNotEmpty) blocks.add(current.toString());
  return blocks;
}

/// What the phone lays out of one text, at most (V2-2 D4). The computer cuts what it sends (4 KiB of
/// tool output at each end, 4 KiB per side of a diff, 2 KiB of input), but an agent's answer has no
/// length, and a megabyte on one line takes seconds to lay out: the phone does not rely on being sent
/// less. These stay above what the computer sends (and a user's text above the 32 KiB a phone may
/// send), so nothing it meant to show is ever cut here.
const int kShownTextChars = 40000;

/// An agent's answer, a thought: markdown costs more than plain text, and a single word of that length
/// (an encoded blob, a minified line) is the slowest to wrap.
const int kShownAnswerChars = 20000;

/// Blocks of one text the phone builds (each is a markdown widget).
const int kShownBlocks = 200;

/// One piece of tool output, one side of a diff: the computer's 8 KiB whole, or 4 KiB at each end.
const int kShownOutputChars = 8192;

/// A tool call's input as JSON (the computer sends 2 KiB at most).
const int kShownInputChars = 4096;

/// Lines of one piece of output or one side of a diff.
const int kShownLines = 1000;

/// [text] cut to what the phone lays out: at most [maxChars] UTF-16 units and [maxLines] lines (null:
/// any number), never in the middle of a surrogate pair. [cut] says whether anything is left out;
/// [text] is then the start of the original. A text within both limits comes back as it is (no copy).
/// It reads at most [maxChars] units, so a megabyte costs no more than a short text.
({String text, bool cut}) clipForDisplay(String text, {required int maxChars, int? maxLines = kShownLines}) {
  var end = text.length < maxChars ? text.length : maxChars;
  if (maxLines != null) {
    var lines = 1;
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A && ++lines > maxLines) {
        end = i;
        break;
      }
    }
  }
  if (end >= text.length) return (text: text, cut: false);
  if (end > 0 && _isHighSurrogate(text.codeUnitAt(end - 1))) end--;
  return (text: text.substring(0, end), cut: true);
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
