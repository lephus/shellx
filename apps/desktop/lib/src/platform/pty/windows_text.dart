/// Quotes one argument following the CommandLineToArgvW rules.
///
/// The vendored flutter_pty joins the executable and the arguments into the
/// Windows command line exactly as given, so every one of them (the
/// executable path included, which may contain spaces) is quoted here.
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
