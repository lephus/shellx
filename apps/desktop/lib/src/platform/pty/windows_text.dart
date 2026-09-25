/// Helpers that work around flutter_pty 0.4.2 on Windows: its C code builds the
/// command line, environment block and working directory by widening every
/// UTF-8 *byte* into one UTF-16 code unit, and joins arguments with plain
/// spaces. Non-ASCII text is therefore mangled and arguments with spaces split.
library;

bool isAscii(String value) => value.codeUnits.every((unit) => unit < 0x80);

/// Quotes one argument following the CommandLineToArgvW rules.
String windowsQuoteArg(String argument) {
  if (argument.isNotEmpty && !argument.contains(RegExp(r'[\s"]'))) {
    return argument;
  }
  final buffer = StringBuffer('"');
  var backslashes = 0;
  for (final char in argument.split('')) {
    if (char == r'\') {
      backslashes++;
      continue;
    }
    if (char == '"') {
      buffer.write(r'\' * (backslashes * 2 + 1));
      buffer.write('"');
    } else {
      buffer.write(r'\' * backslashes);
      buffer.write(char);
    }
    backslashes = 0;
  }
  buffer.write(r'\' * (backslashes * 2));
  buffer.write('"');
  return buffer.toString();
}

/// Rewrites each non-ASCII element of a `;`-separated path list with
/// [shorten] (8.3 short path). Elements [shorten] cannot convert stay as they
/// are (and will reach the shell mangled).
String asciiSafePathList(String value, String Function(String path) shorten) {
  if (isAscii(value)) return value;
  return value
      .split(';')
      .map((part) => isAscii(part) ? part : shorten(part))
      .join(';');
}

/// Applies [asciiSafePathList] to every environment value.
Map<String, String> asciiSafeEnvironment(
  Map<String, String> environment,
  String Function(String path) shorten,
) {
  return {
    for (final entry in environment.entries)
      entry.key: asciiSafePathList(entry.value, shorten),
  };
}
