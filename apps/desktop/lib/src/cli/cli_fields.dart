import 'dart:convert';

import 'package:shellx_agent/shellx_agent.dart';

/// A7: reading the fields of a command-line request.
CliFailure badRequest(String message) =>
    CliFailure(MuxError.badRequest, message);

/// Text of at most [max] characters.
String? stringField(MuxMessage r, String key, {int max = 4096}) {
  final v = r.fields[key];
  if (v == null) return null;
  if (v is! String || v.length > max) {
    throw badRequest('$key must be text of at most $max characters');
  }
  return v;
}

/// D32: text of at most [maxBytes] of UTF-8 ([limit] says it in KiB).
String? textField(
  MuxMessage r,
  String key, {
  required int maxBytes,
  required String limit,
}) {
  final v = r.fields[key];
  if (v == null) return null;
  if (v is! String) throw badRequest('$key must be text');
  if (v.length > maxBytes || utf8.encode(v).length > maxBytes) {
    throw badRequest('$key is over $limit');
  }
  return v;
}

bool flagField(MuxMessage r, String key) {
  final v = r.fields[key];
  if (v == null) return false;
  if (v is! bool) throw badRequest('$key must be true or false');
  return v;
}
