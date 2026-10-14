import 'json_rpc.dart';

/// `toString()` is `'…'`: ACP values may carry the user's prompt, files or
/// paths and must never reach a log (spec D20).
mixin Redacted {
  @override
  String toString() => '…';
}

// Tolerant readers for agent JSON: a field of the wrong type reads as
// absent and nothing throws (spec §6).

String? readString(JsonMap m, String key) {
  final v = m[key];
  return v is String ? v : null;
}

int? readInt(JsonMap m, String key) {
  final v = m[key];
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

num? readNum(JsonMap m, String key) {
  final v = m[key];
  return v is num ? v : null;
}

bool? readBool(JsonMap m, String key) {
  final v = m[key];
  return v is bool ? v : null;
}

JsonMap? readMap(JsonMap m, String key) {
  final v = m[key];
  return v is JsonMap ? v : null;
}

List<Object?>? readList(JsonMap m, String key) {
  final v = m[key];
  return v is List ? v.cast<Object?>() : null;
}

/// The objects in list [key]; other entries are skipped.
Iterable<JsonMap> readMaps(JsonMap m, String key) =>
    (readList(m, key) ?? const []).whereType<JsonMap>();

/// The strings in list [key]; other entries are skipped.
List<String> readStrings(JsonMap m, String key) =>
    (readList(m, key) ?? const []).whereType<String>().toList();
