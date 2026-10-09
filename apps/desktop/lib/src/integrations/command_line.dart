/// The longest `agent-event-command` string.
const int kAgentCommandMaxLength = 4096;

/// Every control character but the tab (a word separator).
final RegExp _control = RegExp(r'[\u0000-\u0008\u000a-\u001f\u007f]');

final RegExp _hidden = RegExp(
  r'[\p{Cf}\u0080-\u009f\u2028\u2029]',
  unicode: true,
);

/// Bidi controls, zero-width characters, every other format character
/// (Cf), the C1 controls (U+0085 included) and the line/paragraph
/// separators: they make a command look like something else. Refused in
/// `agent-event-command`.
bool hasHiddenChars(String text) => _hidden.hasMatch(text);

/// Whether the program word names a place, not a PATH search: `/…`, `~/…`
/// (Windows: `C:\…`, or PowerShell by name, which `argvAllowed` pins to
/// `-File`).
bool programIsAbsolute(String program, {required bool windows}) {
  if (windows) {
    final lower = program.toLowerCase();
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(program) ||
        const {
          'powershell',
          'powershell.exe',
          'pwsh',
          'pwsh.exe',
        }.contains(lower) ||
        program.startsWith('~/');
  }
  return program.startsWith('/') || program.startsWith('~/');
}

/// What the approval dialog shows: one word per line, a space as `␣`, a
/// backslash doubled, a tab as `\t`, an empty word as `""`, so a space at
/// an edge or a lookalike cannot hide.
List<String> visibleArgs(List<String> argv) => [
  for (final a in argv)
    a.isEmpty
        ? '""'
        : a
              .replaceAll(r'\', r'\\')
              .replaceAll(' ', '\u2423')
              .replaceAll('\t', r'\t'),
];

/// A small word splitter, not a shell: whitespace separates words; single
/// quotes keep everything; double quotes keep everything but `\"` and `\\`;
/// outside quotes a backslash escapes the next character. `$`, backticks,
/// globs and operators are ordinary characters. A word that starts with an
/// unquoted `~/` begins at [home]. Null: empty, an unbalanced quote, a
/// trailing backslash, or a control character anywhere.
List<String>? splitCommand(String input, {required String home}) {
  if (input.length > kAgentCommandMaxLength ||
      _control.hasMatch(input) ||
      hasHiddenChars(input)) {
    return null;
  }
  final words = <String>[];
  final word = StringBuffer();
  var inWord = false;
  var tilde = false; // the word began with an unquoted `~/`
  var index = 0;
  final n = input.length;

  void end() {
    if (!inWord) return;
    var text = word.toString();
    if (tilde && home.isNotEmpty) {
      text = home.endsWith('/')
          ? '$home${text.substring(2)}'
          : '$home${text.substring(1)}';
    }
    words.add(text);
    word.clear();
    inWord = false;
    tilde = false;
  }

  while (index < n) {
    final c = input[index];
    if (c == ' ' || c == '\t') {
      end();
      index++;
    } else if (c == "'") {
      final close = input.indexOf("'", index + 1);
      if (close < 0) return null;
      inWord = true;
      word.write(input.substring(index + 1, close));
      index = close + 1;
    } else if (c == '"') {
      inWord = true;
      index++;
      var closed = false;
      while (index < n) {
        final d = input[index];
        if (d == '"') {
          closed = true;
          index++;
          break;
        }
        if (d == r'\' &&
            index + 1 < n &&
            (input[index + 1] == '"' || input[index + 1] == r'\')) {
          word.write(input[index + 1]);
          index += 2;
        } else {
          word.write(d);
          index++;
        }
      }
      if (!closed) return null;
    } else if (c == r'\') {
      if (index + 1 >= n) return null;
      inWord = true;
      word.write(input[index + 1]);
      index += 2;
    } else {
      if (!inWord && c == '~' && index + 1 < n && input[index + 1] == '/') {
        tilde = true;
      }
      inWord = true;
      word.write(c);
      index++;
    }
  }
  end();
  return words.isEmpty ? null : words;
}

/// Windows has no shell here, so only a program that can start without one:
/// an `.exe`, or PowerShell with `-File`. Elsewhere any non-empty program.
bool argvAllowed(List<String> argv, {required bool windows}) {
  if (argv.isEmpty || argv.first.isEmpty) return false;
  if (!windows) return true;
  final exe = argv.first.toLowerCase();
  const shells = {'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe'};
  if (shells.contains(exe)) {
    return argv.length >= 3 && argv[1].toLowerCase() == '-file';
  }
  return exe.endsWith('.exe');
}
