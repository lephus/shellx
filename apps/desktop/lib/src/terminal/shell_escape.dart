/// How a dropped or pasted file name is written on a command line (A10
/// D18). Pure; the pane's shell decides the family.
library;

enum ShellFamily { posix, powershell, cmd }

/// The family of the shell a pane runs: [shell] is `PaneSession.shell` (the
/// program's base name). Unknown shells are POSIX on macOS and PowerShell
/// on Windows.
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
final RegExp _control = RegExp(r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]');
final RegExp _posixSafe = RegExp(r'^[A-Za-z0-9_.,:/@%+=~\-\u00a0-\uFFFF]$');
// Bare in PowerShell and cmd: no `,` (array), `@` (splat), `%` (cmd expands
// it even inside quotes), `=`, `~`.
final RegExp _winSafe = RegExp(r'^[A-Za-z0-9_.:/\\+\-\u00a0-\uFFFF]+$');
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
      for (final unit in word.split('')) {
        // `~` (home) and `=` (zsh `=cmd`) are only special at the start.
        final atStart = out.isEmpty;
        final plain =
            _posixSafe.hasMatch(unit) &&
            !(atStart && (unit == '~' || unit == '='));
        if (!plain) out.write(r'\');
        out.write(unit);
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
