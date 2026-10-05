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
String insertBlock(String text, String block, {required String eol}) {
  final converted = eol == '\n' ? block : block.replaceAll('\n', eol);
  return converted + removeBlock(text);
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
