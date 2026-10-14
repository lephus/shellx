import 'acp_content.dart';
import 'acp_types.dart';
import 'json_rpc.dart';

// Params of every request ShellX sends. Kept apart from AcpClient so the
// conformance test checks each one against the ACP schema (spec §7).

/// `initialize` (spec D1): no file system and no terminals offered; ShellX
/// runs terminal logins itself and answers form and URL questions.
JsonMap initializeParams({required String clientVersion}) => {
  'protocolVersion': 1,
  'clientCapabilities': {
    'fs': {'readTextFile': false, 'writeTextFile': false},
    'terminal': false,
    'auth': {'terminal': true},
    'elicitation': {'form': <String, Object?>{}, 'url': <String, Object?>{}},
  },
  'clientInfo': {'name': 'shellx', 'title': 'ShellX', 'version': clientVersion},
};

JsonMap authenticateParams(String methodId) => {'methodId': methodId};

JsonMap newSessionParams({
  required String cwd,
  List<McpServerStdio> mcpServers = const [],
}) => {
  'cwd': cwd,
  'mcpServers': [for (final s in mcpServers) s.toJson()],
};

JsonMap loadSessionParams({
  required String sessionId,
  required String cwd,
  List<McpServerStdio> mcpServers = const [],
}) => {
  'sessionId': sessionId,
  'cwd': cwd,
  'mcpServers': [for (final s in mcpServers) s.toJson()],
};

JsonMap listSessionsParams({String? cwd, String? cursor}) => {
  'cwd': ?cwd,
  'cursor': ?cursor,
};

JsonMap promptParams(String sessionId, List<ContentBlock> prompt) => {
  'sessionId': sessionId,
  'prompt': [for (final b in prompt) b.toJson()],
};

JsonMap cancelParams(String sessionId) => {'sessionId': sessionId};

/// A [String] is a select value; a [bool] is sent with `type: "boolean"`.
JsonMap setConfigOptionParams(String sessionId, String configId, Object value) {
  if (value is! String && value is! bool) {
    throw ArgumentError.value(value, 'value', 'must be a String or a bool');
  }
  return {
    'sessionId': sessionId,
    'configId': configId,
    if (value is bool) 'type': 'boolean',
    'value': value,
  };
}

JsonMap setModeParams(String sessionId, String modeId) => {
  'sessionId': sessionId,
  'modeId': modeId,
};
