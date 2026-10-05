import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:shellx_core/shellx_core.dart';

const int _blockLength = 64;
const DartSha256 _sha256 = DartSha256();

Uint8List _hash(List<int> data) =>
    Uint8List.fromList(_sha256.hashSync(data).bytes);

/// RFC 2104 HMAC-SHA256.
Uint8List hmacSha256(List<int> key, List<int> data) {
  final normalized = key.length > _blockLength ? _hash(key) : key;
  final inner = Uint8List(_blockLength);
  final outer = Uint8List(_blockLength);
  for (var i = 0; i < _blockLength; i++) {
    final k = i < normalized.length ? normalized[i] : 0;
    inner[i] = k ^ 0x36;
    outer[i] = k ^ 0x5c;
  }
  return _hash(
    concatBytes([
      outer,
      _hash(concatBytes([inner, data])),
    ]),
  );
}

final _agentLabel = utf8.encode('shellx-term/agent');
final _termLabel = utf8.encode('shellx-term/term');

/// The agent proves it knows the secret (spec §6.3 step 2).
Uint8List agentProof(
  Uint8List secret,
  Uint8List nonceTerm,
  Uint8List nonceAgent,
) => hmacSha256(secret, concatBytes([_agentLabel, nonceTerm, nonceAgent]));

/// What `shellx-term` must send in `auth` (spec §6.3 step 4).
Uint8List termProof(
  Uint8List secret,
  Uint8List nonceAgent,
  Uint8List nonceTerm,
) => hmacSha256(secret, concatBytes([_termLabel, nonceAgent, nonceTerm]));
