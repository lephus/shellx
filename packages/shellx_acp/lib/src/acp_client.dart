import 'acp_content.dart';
import 'acp_elicitation.dart';
import 'acp_json.dart';
import 'acp_requests.dart';
import 'acp_types.dart';
import 'acp_updates.dart';
import 'json_rpc.dart';

/// Answers a `session/request_permission`.
typedef PermissionHandler =
    Future<PermissionOutcome> Function(PermissionRequest request);

/// Answers an `elicitation/create`.
typedef ElicitationHandler =
    Future<ElicitationResponse> Function(ElicitationRequest request);

/// The client side of ACP v1 over one connection (spec D1).
///
/// Updates go to [onUpdate] synchronously, in the order they arrive, so all
/// of a turn's updates are delivered before [prompt] completes. With no
/// handler set, a permission request is answered `cancelled` and a question
/// `decline`: nothing is ever allowed on the user's behalf (spec §8.6).
final class AcpClient with Redacted {
  AcpClient(this.connection) {
    connection
      ..onNotification('session/update', (p) {
        final sessionId = readString(p, 'sessionId');
        final update = readMap(p, 'update');
        if (sessionId == null || update == null) return;
        onUpdate?.call(sessionId, SessionUpdate.fromJson(update));
      })
      ..onNotification('elicitation/complete', (p) {
        final id = readString(p, 'elicitationId');
        if (id != null) onElicitationComplete?.call(id);
      })
      ..onRequest('session/request_permission', (p) async {
        final handler = onPermission;
        final outcome = handler == null
            ? const PermissionCancelled()
            : await handler(PermissionRequest.fromJson(p));
        return outcome.toJson();
      })
      ..onRequest('elicitation/create', (p) async {
        final handler = onElicitation;
        final response = handler == null
            ? const ElicitDecline()
            : await handler(ElicitationRequest.fromJson(p));
        return response.toJson();
      });
  }

  final JsonRpcConnection connection;

  void Function(String sessionId, SessionUpdate update)? onUpdate;
  void Function(String elicitationId)? onElicitationComplete;
  PermissionHandler? onPermission;
  ElicitationHandler? onElicitation;

  Future<InitializeResult> initialize({required String clientVersion}) async =>
      InitializeResult.fromJson(
        _map(
          await connection.request(
            'initialize',
            initializeParams(clientVersion: clientVersion),
          ),
        ),
      );

  /// For [AuthMethodAgent] only; terminal logins run in a run sheet (D8).
  Future<void> authenticate(String methodId) =>
      connection.request('authenticate', authenticateParams(methodId));

  Future<NewSessionResult> newSession({
    required String cwd,
    List<McpServerStdio> mcpServers = const [],
  }) async => NewSessionResult.fromJson(
    _map(
      await connection.request(
        'session/new',
        newSessionParams(cwd: cwd, mcpServers: mcpServers),
      ),
    ),
  );

  /// The agent replays the session through [onUpdate] before this returns.
  Future<LoadSessionResult> loadSession({
    required String sessionId,
    required String cwd,
    List<McpServerStdio> mcpServers = const [],
  }) async => LoadSessionResult.fromJson(
    _map(
      await connection.request(
        'session/load',
        loadSessionParams(
          sessionId: sessionId,
          cwd: cwd,
          mcpServers: mcpServers,
        ),
      ),
    ),
  );

  Future<ListSessionsResult> listSessions({
    String? cwd,
    String? cursor,
  }) async => ListSessionsResult.fromJson(
    _map(
      await connection.request(
        'session/list',
        listSessionsParams(cwd: cwd, cursor: cursor),
      ),
    ),
  );

  Future<StopReason> prompt(
    String sessionId,
    List<ContentBlock> prompt,
  ) async => StopReason.parse(
    readString(
      _map(
        await connection.request(
          'session/prompt',
          promptParams(sessionId, prompt),
        ),
      ),
      'stopReason',
    ),
  );

  void cancel(String sessionId) =>
      connection.notify('session/cancel', cancelParams(sessionId));

  /// The options as the agent now has them, or null if it sent none.
  Future<List<ConfigOption>?> setConfigOption(
    String sessionId,
    String configId,
    Object value,
  ) async {
    final r = _map(
      await connection.request(
        'session/set_config_option',
        setConfigOptionParams(sessionId, configId, value),
      ),
    );
    return r['configOptions'] is List
        ? readConfigOptions(r, 'configOptions')
        : null;
  }

  /// For agents that only offer legacy `modes` (spec D11).
  Future<void> setMode(String sessionId, String modeId) =>
      connection.request('session/set_mode', setModeParams(sessionId, modeId));

  Future<void> close() => connection.close();

  static JsonMap _map(Object? v) => v is JsonMap ? v : const {};
}
