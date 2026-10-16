import 'dart:convert';
import 'dart:typed_data';

/// First and last line of every ShellX block (spec §5.2, §5.3).
const String blockStartMarker = '# >>> ShellX >>>';
const String blockEndMarker = '# <<< ShellX <<<';

/// How a startup file is stored (spec §10.2: kept as found).
enum ConfigEncoding {
  /// UTF-8 without BOM, or any ASCII-compatible 8-bit code page (Windows
  /// PowerShell 5.1 reads BOM-less files in the system code page). Kept
  /// byte for byte: the text is the bytes read as latin1, and the block is
  /// ASCII.
  ascii8,
  utf8Bom,
  utf16le,
  utf16be,
}

/// A decoded startup file: its text (without BOM), how it is stored, and
/// its line ending (`null` while it has no line break).
final class ConfigText {
  const ConfigText(this.text, this.encoding, this.eol);

  final String text;
  final ConfigEncoding encoding;
  final String? eol;

  ConfigText withText(String text) => ConfigText(text, encoding, eol);
}

/// Throws [FormatException] for a UTF-16 file with an odd number of bytes.
ConfigText decodeConfig(Uint8List bytes) {
  final ConfigEncoding encoding;
  final String text;
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    encoding = ConfigEncoding.utf8Bom;
    text = latin1.decode(bytes.sublist(3));
  } else if (_startsWith(bytes, const [0xFF, 0xFE])) {
    encoding = ConfigEncoding.utf16le;
    text = _decodeUtf16(bytes, littleEndian: true);
  } else if (_startsWith(bytes, const [0xFE, 0xFF])) {
    encoding = ConfigEncoding.utf16be;
    text = _decodeUtf16(bytes, littleEndian: false);
  } else {
    encoding = ConfigEncoding.ascii8;
    text = latin1.decode(bytes);
  }
  return ConfigText(text, encoding, _lineEnding(text));
}

Uint8List encodeConfig(ConfigText config) {
  final text = config.text;
  switch (config.encoding) {
    case ConfigEncoding.ascii8:
      return latin1.encode(text);
    case ConfigEncoding.utf8Bom:
      return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...latin1.encode(text)]);
    case ConfigEncoding.utf16le || ConfigEncoding.utf16be:
      final little = config.encoding == ConfigEncoding.utf16le;
      final out = Uint8List(2 + text.length * 2);
      out[0] = little ? 0xFF : 0xFE;
      out[1] = little ? 0xFE : 0xFF;
      for (var i = 0; i < text.length; i++) {
        final unit = text.codeUnitAt(i);
        out[2 + i * 2] = little ? unit & 0xFF : unit >> 8;
        out[3 + i * 2] = little ? unit >> 8 : unit & 0xFF;
      }
      return out;
  }
}

/// [block] (LF, ending with a newline) at the top of [text], written with
/// [eol]. Any ShellX block already in [text] is removed first, so inserting
/// again never makes a second block.
///
/// [powerShell]: `using namespace|module|assembly` statements and a script
/// `param(…)` block must come before any other statement, so the block goes
/// right after such a prelude (comments and blank lines may sit in it);
/// without one it stays at the very top.
String insertBlock(
  String text,
  String block, {
  required String eol,
  bool powerShell = false,
}) {
  final converted = eol == '\n' ? block : block.replaceAll('\n', eol);
  final rest = removeBlock(text);
  final at = powerShell ? powerShellPreludeEnd(rest) : 0;
  if (at == 0) return converted + rest;
  final head = rest.substring(0, at);
  final separator = head.endsWith('\n') ? '' : eol;
  return head + separator + converted + rest.substring(at);
}

final RegExp _using = RegExp(
  r'^\s*using\s+(namespace|module|assembly)\b',
  caseSensitive: false,
);
final RegExp _attribute = RegExp(r'^\s*\[[^\]]*\]\s*$');
final RegExp _param = RegExp(r'^\s*param\s*\(', caseSensitive: false);

/// Visible for tests: the offset just after the last `using` line or the
/// `param(…)` block of a PowerShell prelude, or 0 when there is none.
int powerShellPreludeEnd(String text) {
  var end = 0;
  var pos = 0;
  var inBlockComment = false;
  while (pos < text.length) {
    final newline = text.indexOf('\n', pos);
    final lineEnd = newline < 0 ? text.length : newline + 1;
    final line = text.substring(pos, newline < 0 ? text.length : newline);
    final trimmed = line.trim();
    if (inBlockComment) {
      if (trimmed.contains('#>')) inBlockComment = false;
    } else if (trimmed.isEmpty || trimmed.startsWith('#')) {
      // Blank line or comment (#requires included).
    } else if (trimmed.startsWith('<#')) {
      if (!trimmed.contains('#>')) inBlockComment = true;
    } else if (_using.hasMatch(line)) {
      end = lineEnd;
    } else if (_attribute.hasMatch(line) || _param.hasMatch(line)) {
      // [CmdletBinding()] lines, then param( … ): find the closing paren.
      final paramAt = text.indexOf(
        RegExp(r'param\s*\(', caseSensitive: false),
        pos,
      );
      if (paramAt < 0) return end;
      final between = text.substring(pos, paramAt);
      if (!between
          .split('\n')
          .every(
            (l) =>
                l.trim().isEmpty ||
                _attribute.hasMatch(l) ||
                l.trim().startsWith('#'),
          )) {
        return end;
      }
      var depth = 0;
      for (var i = text.indexOf('(', paramAt); i < text.length; i++) {
        final c = text[i];
        if (c == '(') depth++;
        if (c == ')' && --depth == 0) {
          final nl = text.indexOf('\n', i);
          return nl < 0 ? text.length : nl + 1;
        }
      }
      return end; // Unbalanced: leave the top alone.
    } else {
      return end;
    }
    pos = lineEnd;
  }
  return end;
}

/// [text] without its ShellX blocks: each runs from a start-marker line
/// through the next end-marker line, including that line's line break. A
/// start marker with no end marker after it is left alone.
String removeBlock(String text) {
  var result = text;
  while (true) {
    final range = _blockRange(result);
    if (range == null) return result;
    result = result.replaceRange(range.$1, range.$2, '');
  }
}

bool hasBlock(String text) => _blockRange(text) != null;

/// The first ShellX block in [text] with LF line endings, or null.
String? installedBlock(String text) {
  final range = _blockRange(text);
  if (range == null) return null;
  var block = text.substring(range.$1, range.$2).replaceAll('\r\n', '\n');
  if (!block.endsWith('\n')) block = '$block\n';
  return block;
}

/// [start, end) of the first complete block.
(int, int)? _blockRange(String text) {
  int? start;
  var lineStart = 0;
  while (lineStart < text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline < 0 ? text.length : newline + 1;
    var line = text.substring(lineStart, newline < 0 ? text.length : newline);
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    if (start == null) {
      if (line == blockStartMarker) start = lineStart;
    } else if (line == blockEndMarker) {
      return (start, lineEnd);
    }
    lineStart = lineEnd;
  }
  return null;
}

String? _lineEnding(String text) {
  final newline = text.indexOf('\n');
  if (newline < 0) return null;
  return newline > 0 && text.codeUnitAt(newline - 1) == 0x0D ? '\r\n' : '\n';
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  if (bytes.length.isOdd) {
    throw const FormatException('UTF-16 file with an odd number of bytes');
  }
  final units = <int>[
    for (var i = 2; i < bytes.length; i += 2)
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
  ];
  return String.fromCharCodes(units);
}
