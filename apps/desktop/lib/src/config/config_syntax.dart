import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'config_problem.dart';

/// One `key = value` line (A9 spec D5).
@immutable
final class ConfigEntry {
  const ConfigEntry({
    required this.file,
    required this.line,
    required this.key,
    required this.value,
  });

  final String file;
  final int line;
  final String key;
  final String value;

  @override
  String toString() => 'ConfigEntry($key @ $file:$line)';
}

final RegExp _keyPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// D5: whole-line `#` comments, the first `=` splits, both sides trimmed,
/// one pair of surrounding double quotes stripped (no escapes). Bad lines
/// are reported and skipped; the others are returned in order.
List<ConfigEntry> parseConfigText(
  String text, {
  required String file,
  required List<ConfigProblem> problems,
}) {
  final entries = <ConfigEntry>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim(); // also drops a CR
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) {
      problems.add(
        ConfigProblem(
          file: file,
          line: i + 1,
          severity: ConfigSeverity.error,
          code: ConfigProblemCode.syntax,
        ),
      );
      continue;
    }
    final key = line.substring(0, eq).trim();
    if (!_keyPattern.hasMatch(key)) {
      problems.add(
        ConfigProblem(
          file: file,
          line: i + 1,
          severity: ConfigSeverity.error,
          code: ConfigProblemCode.badKey,
          key: key,
        ),
      );
      continue;
    }
    entries.add(
      ConfigEntry(
        file: file,
        line: i + 1,
        key: key,
        value: unquoteConfigValue(line.substring(eq + 1).trim()),
      ),
    );
  }
  return entries;
}

String unquoteConfigValue(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// D5: UTF-8 (a BOM is skipped) or UTF-16 with a BOM. Anything else throws
/// [FormatException].
String decodeConfigBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), little: false);
  }
  return utf8.decode(bytes);
}

String _utf16(Uint8List bytes, {required bool little}) {
  if (bytes.length.isOdd) throw const FormatException('odd UTF-16 length');
  final units = List<int>.generate(
    bytes.length ~/ 2,
    (i) => little
        ? bytes[2 * i] | (bytes[2 * i + 1] << 8)
        : (bytes[2 * i] << 8) | bytes[2 * i + 1],
  );
  return String.fromCharCodes(units);
}

final RegExp _twoHex = RegExp(r'^[0-9a-fA-F]{2}$');
final RegExp _hexRun = RegExp(r'^[0-9a-fA-F]{1,6}$');

/// D31: Zig string-literal escapes (`\n \r \t \\ \" \' \xHH \u{H…}`).
/// Null when an escape is invalid.
String? decodeZigString(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c != r'\') {
      out.write(c);
      continue;
    }
    i++;
    if (i >= s.length) return null;
    switch (s[i]) {
      case 'n':
        out.write('\n');
      case 'r':
        out.write('\r');
      case 't':
        out.write('\t');
      case r'\':
        out.write(r'\');
      case '"':
        out.write('"');
      case "'":
        out.write("'");
      case 'x':
        if (i + 3 > s.length) return null;
        final hex = s.substring(i + 1, i + 3);
        if (!_twoHex.hasMatch(hex)) return null;
        out.writeCharCode(int.parse(hex, radix: 16));
        i += 2;
      case 'u':
        if (i + 1 >= s.length || s[i + 1] != '{') return null;
        final end = s.indexOf('}', i + 2);
        if (end < 0) return null;
        final hex = s.substring(i + 2, end);
        if (!_hexRun.hasMatch(hex)) return null;
        final cp = int.parse(hex, radix: 16);
        if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
        out.writeCharCode(cp);
        i = end;
      default:
        return null;
    }
  }
  return out.toString();
}
