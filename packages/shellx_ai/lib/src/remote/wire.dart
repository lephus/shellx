import 'dart:convert';
import 'dart:typed_data';

/// V2-2 §4: the version of the listing and mirror bodies. A body with a
/// higher `v` is still read: unknown keys and item kinds are skipped.
const int kAiWireVersion = 1;

/// The largest body (= shellx_core's `kAiMaxBodyBytes`; this package does
/// not depend on shellx_core, the hub's test pins the two together).
const int kAiBodyBytes = 48 * 1024;

/// Bytes a desktop may have in flight to one phone for one session before
/// it waits for an `ai.ack` (like a terminal's 256 KiB send window).
const int kAiWindowBytes = 256 * 1024;

/// Items a fresh attach brings; older ones come with "load earlier".
const int kAiAttachItems = 60;

/// Items per "load earlier" page.
const int kAiPageItems = 60;

/// The most text one item record carries; a longer text follows in more
/// records (`at` = where the piece starts; `r` = -1 until the last one).
const int kAiTextChunkBytes = 32 * 1024;

/// Tool output kept for the phone: this much from the start and this much
/// from the end, whole lines.
const int kAiOutputBytes = 4 * 1024;

/// A diff side kept for the phone (the changed region and 3 lines around).
const int kAiDiffSideBytes = 4 * 1024;

/// Diffs per tool card; context lines around a changed region.
const int kAiMaxDiffs = 3;
const int kAiDiffContext = 3;

/// The largest item record: a body holds at least one with its envelope.
const int kAiRecordBytes = kAiBodyBytes - 1024;

/// A tool call's input, as JSON text, when it is shown at all.
const int kAiInputBytes = 2 * 1024;

/// A question's form; a bigger one is answered on the computer.
const int kAiAskBytes = 16 * 1024;

/// UTF-8 JSON bytes of [value].
Uint8List encodeBody(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// The JSON object in [bytes]; null when it is not one (never throws).
Map<String, Object?>? decodeBody(Uint8List? bytes) {
  if (bytes == null) return null;
  try {
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, Object?> ? value : null;
  } on Object {
    return null;
  }
}

/// UTF-8 length of [s] without encoding it.
int utf8Length(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      final d = s.codeUnitAt(i + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) {
        n += 4;
        i++;
      } else {
        n += 3;
      }
    } else {
      n += 3;
    }
  }
  return n;
}

/// The longest start of [s] (from [from]) within [maxBytes] of UTF-8; it
/// never splits a surrogate pair. Returns the end index (exclusive).
int utf8Cut(String s, int maxBytes, {int from = 0}) {
  var n = 0;
  var i = from;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    var size = 3;
    var units = 1;
    if (c < 0x80) {
      size = 1;
    } else if (c < 0x800) {
      size = 2;
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      final d = s.codeUnitAt(i + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) {
        size = 4;
        units = 2;
      }
    }
    if (n + size > maxBytes) break;
    n += size;
    i += units;
  }
  return i;
}

final _escapes = RegExp(
  r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)?|[@-Z\\-_])',
);

/// [s] without terminal escape sequences (colours, titles): tool output is
/// shown as plain text on the phone.
String plainText(String s) =>
    s.contains('\x1b') ? s.replaceAll(_escapes, '') : s;

/// [s] cut to [maxBytes] of UTF-8, with "…" when it was cut.
String clipText(String s, int maxBytes) {
  if (utf8Length(s) <= maxBytes) return s;
  return '${s.substring(0, utf8Cut(s, maxBytes - 3))}…';
}

/// The first whole lines of [s] within [maxBytes] (at least the start of
/// the first line).
String headLines(String s, int maxBytes) {
  final end = utf8Cut(s, maxBytes);
  if (end >= s.length) return s;
  final nl = s.lastIndexOf('\n', end);
  return s.substring(0, nl > 0 ? nl : end);
}

/// The last whole lines of [s] within [maxBytes].
String tailLines(String s, int maxBytes) {
  var start = s.length;
  var n = 0;
  while (start > 0) {
    final c = s.codeUnitAt(start - 1);
    // A surrogate pair counts 2 + 2 = its 4 UTF-8 bytes.
    final size = c < 0x80
        ? 1
        : (c < 0x800 ? 2 : (c >= 0xD800 && c <= 0xDFFF ? 2 : 3));
    if (n + size > maxBytes) break;
    n += size;
    start--;
  }
  if (start > 0 && start < s.length) {
    final c = s.codeUnitAt(start);
    if (c >= 0xDC00 && c <= 0xDFFF) start++; // never half a pair
  }
  if (start == 0) return s;
  final nl = s.indexOf('\n', start);
  return nl >= 0 && nl + 1 < s.length
      ? s.substring(nl + 1)
      : s.substring(start);
}

// Tolerant readers of a body: a key of the wrong type reads as absent.

String? jString(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is String ? v : null;
}

int? jInt(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

bool jBool(Map<String, Object?> m, String key) => m[key] == true;

Map<String, Object?>? jMap(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is Map<String, Object?> ? v : null;
}

Iterable<Map<String, Object?>> jMaps(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is List ? v.whereType<Map<String, Object?>>() : const [];
}

List<int> jInts(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is List ? [for (final e in v) e is int ? e : -1] : const [];
}

/// V2-2b: the strings of list [key]; anything else in it is skipped, and a
/// key that is no list reads as empty.
List<String> jStrings(Map<String, Object?> m, String key) {
  final v = m[key];
  return v is List
      ? [
          for (final e in v)
            if (e is String) e,
        ]
      : const [];
}
