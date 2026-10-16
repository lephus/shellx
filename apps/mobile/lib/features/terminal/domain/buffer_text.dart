import 'package:xterm/core.dart';

/// The most lines "View as text" shows (A10 D28).
const int kViewAsTextMaxLines = 2000;

/// The most characters it shows; the start is cut first.
const int kViewAsTextMaxChars = 200000;

/// The terminal's text as plain lines (A10 D28): scrollback and screen
/// (just the screen while a full-screen program runs on the alternate
/// screen), the last [maxLines] lines, rows the terminal wrapped joined
/// into one line, trailing blanks of every line and trailing empty lines
/// removed, at most [maxChars] characters (the start is cut, at a line).
/// [truncated] says something was cut.
({String text, bool truncated}) terminalText(
  Terminal terminal, {
  int maxLines = kViewAsTextMaxLines,
  int maxChars = kViewAsTextMaxChars,
}) {
  final buffer = terminal.buffer;
  final logical = <String>[];
  var current = StringBuffer();
  var open = false;
  for (var row = 0; row < buffer.height; row++) {
    final line = buffer.lines[row];
    if (line.isWrapped && open) {
      // The previous row wrapped into this one: no trimming between them.
    } else {
      if (open) logical.add(_trimEnd(current.toString()));
      current = StringBuffer();
      open = true;
    }
    final nextWraps = row + 1 < buffer.height && buffer.lines[row + 1].isWrapped;
    current.write(nextWraps ? line.getText() : line.getText(0, line.getTrimmedLength()));
  }
  if (open) logical.add(_trimEnd(current.toString()));
  while (logical.isNotEmpty && logical.last.isEmpty) {
    logical.removeLast();
  }
  var truncated = false;
  var lines = logical;
  if (lines.length > maxLines) {
    lines = lines.sublist(lines.length - maxLines);
    truncated = true;
  }
  var text = lines.join('\n');
  if (text.length > maxChars) {
    final cut = text.indexOf('\n', text.length - maxChars);
    text = cut < 0 ? text.substring(text.length - maxChars) : text.substring(cut + 1);
    truncated = true;
  }
  return (text: text, truncated: truncated);
}

String _trimEnd(String s) {
  var end = s.length;
  while (end > 0 && (s.codeUnitAt(end - 1) == 0x20 || s.codeUnitAt(end - 1) == 0)) {
    end--;
  }
  return s.substring(0, end);
}
