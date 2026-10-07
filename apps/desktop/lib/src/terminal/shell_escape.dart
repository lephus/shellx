/// How a dropped or pasted file name is written on a command line (A10
/// D18). Pure; the pane's shell decides the family.
library;

enum ShellFamily { posix, powershell, cmd }

/// The family of the shell a pane runs: [shell] is `PaneSession.shell` (the
/// program's base name). Unknown shells are POSIX on macOS and PowerShell
/// on Windows (single quotes).
///
/// Known limitation: the family is that of the shell the pane was launched
/// with. A different shell typed inside the pane (bash inside pwsh) reads
/// the paths with the outer family's quoting. The text is always pasted
/// (bracketed when the program asked) and never followed by Enter, so a
/// mismatch shows on the line and cannot run anything.
ShellFamily shellFamilyOf(String shell, {required bool windows}) {
  final name = shell.toLowerCase().replaceAll(RegExp(r'\.exe$'), '');
  if (name == 'cmd') return ShellFamily.cmd;
  if (name == 'powershell' || name == 'pwsh') return ShellFamily.powershell;
  const posix = {'zsh', 'bash', 'sh', 'fish', 'dash', 'ksh', 'tcsh', 'csh'};
  if (posix.contains(name)) return ShellFamily.posix;
  return windows ? ShellFamily.powershell : ShellFamily.posix;
}

// C0, DEL, C1 (0x9B is CSI to some terminals) and the Unicode line/paragraph
// separators: none can be written safely, so the whole drop is refused.
// Also the bidi controls (a name can be made to read differently from what
// it is), the zero-width characters and the byte-order mark.
final RegExp _control = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u200b\u200e\u200f\u2028\u2029'
  r'\u202a-\u202e\u2066-\u2069\ufeff]',
);
final RegExp _posixSafe = RegExp(r'^[A-Za-z0-9_.,:/@%+=~\-\u00a0-\uFFFF]$');
// Bare in PowerShell and cmd: ASCII only (no `,` array, `@` splat, `%` that
// cmd expands even inside quotes, `=`, `~`; and no Unicode: PowerShell reads
// U+00A0, U+2000-series spaces and U+2013/2014 dashes as separators or
// operators). Everything else is quoted.
final RegExp _winSafe = RegExp(r'^[A-Za-z0-9_.:/\\+\-]+$');
// PowerShell treats the typographic single quotes as quotes too.
final RegExp _psQuote = RegExp('[\'\u2018\u2019\u201a\u201b]');

/// True when [path] cannot be written safely for any shell (a control
/// character, an NUL, a line break): the whole drop is refused.
bool hasUnsafeCharacters(String path) => _control.hasMatch(path);

/// [path] as one word of a command line for [family]. Throws
/// [FormatException] for a path [hasUnsafeCharacters].
String escapePath(String path, ShellFamily family) {
  if (hasUnsafeCharacters(path)) {
    throw const FormatException('unsafe characters in a file name');
  }
  switch (family) {
    case ShellFamily.posix:
      // A relative name that starts with `-` would be an option: `./` first.
      final word = path.startsWith('-') ? './$path' : path;
      final out = StringBuffer();
      var previous = '';
      for (final unit in word.split('')) {
        // `~` (home) and `=` (zsh `=cmd`) are special at the start of a
        // word; `~` also after `=` or `:` (assignments, PATH-like lists).
        final special =
            (previous.isEmpty && (unit == '~' || unit == '=')) ||
            (unit == '~' && (previous == '=' || previous == ':'));
        if (!_posixSafe.hasMatch(unit) || special) out.write(r'\');
        out.write(unit);
        previous = unit;
      }
      return out.toString();
    case ShellFamily.powershell:
      if (_winSafe.hasMatch(path) && !path.startsWith('-')) return path;
      return "'${path.replaceAllMapped(_psQuote, (m) => '${m[0]}${m[0]}')}'";
    case ShellFamily.cmd:
      // `%VAR%` expands even inside quotes and a `"` cannot be escaped on
      // the interactive command line: refuse both rather than guess.
      if (path.contains('%') || path.contains('"')) {
        throw const FormatException('a file name cmd cannot take literally');
      }
      if (_winSafe.hasMatch(path) && !path.startsWith('-')) return path;
      return '"$path"';
  }
}

/// [paths] ready to paste: escaped, one space between, one space after.
/// Throws [FormatException] when any is unsafe.
String escapePaths(Iterable<String> paths, ShellFamily family) =>
    '${paths.map((p) => escapePath(p, family)).join(' ')} ';
