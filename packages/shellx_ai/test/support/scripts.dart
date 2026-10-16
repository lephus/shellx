import 'dart:io';

/// Writes a Dart program into [dir] and returns the args to run it with
/// the current VM.
List<String> dartScript(Directory dir, String name, String source) {
  final f = File('${dir.path}${Platform.pathSeparator}$name.dart')
    ..writeAsStringSync(source);
  return [f.path];
}

/// A program that ignores stdin closing and lives for five minutes.
const ignoreStdin = '''
import 'dart:async';
void main() { Timer(const Duration(minutes: 5), () {}); }
''';

/// Like [ignoreStdin], but says "ready" once its code runs. On macOS the
/// `dart` launcher turns into `dartvm` first: until it has printed, a process
/// lookup may still see the old name.
const readyThenIgnoreStdin = '''
import 'dart:async';
void main() { print('ready'); Timer(const Duration(minutes: 5), () {}); }
''';

/// Prints which of HOME / USERPROFILE / ONLY_THIS it can see, then exits.
const printEnv = '''
import 'dart:io';
void main() {
  final e = Platform.environment;
  stdout.write(['HOME', 'USERPROFILE', 'ONLY_THIS'].where(e.containsKey).join(','));
}
''';

/// Writes 300 KiB to stderr, the last line being "last line".
const noisyStderr = r'''
import 'dart:io';
void main() {
  final line = 'x' * 1023 + '\n';
  for (var i = 0; i < 300; i++) { stderr.write(line); }
  stderr.write('last line\n');
}
''';

/// Prints its working folder.
const printCwd = '''
import 'dart:io';
void main() { stdout.write(Directory.current.path); }
''';

/// Prints its arguments as a JSON list.
const printArgs = '''
import 'dart:convert';
import 'dart:io';
void main(List<String> args) { stdout.write(jsonEncode(args)); }
''';

/// The variables a Windows process needs to start at all.
Map<String, String> minimalEnv() => {
  if (Platform.isWindows)
    for (final k in ['SystemRoot', 'PATH', 'TEMP', 'TMP'])
      if (Platform.environment[k] != null) k: Platform.environment[k]!,
};
