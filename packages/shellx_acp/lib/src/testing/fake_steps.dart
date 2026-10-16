import '../json_rpc.dart';

/// Steps for `FakeScenario.turns`: each is a one-key JSON map, so the same
/// script drives the in-process agent and `bin/fake_agent.dart`.
abstract final class FakeSteps {
  /// The Claude adapter's permission options (0.90.0).
  static const claudeOptions = <JsonMap>[
    {'optionId': 'allow-once', 'name': 'Yes', 'kind': 'allow_once'},
    {
      'optionId': 'allow-with-updates',
      'name': 'Yes, allow all edits during this session',
      'kind': 'allow_always',
    },
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ];

  /// Sends `session/update` with [update].
  static JsonMap update(JsonMap update) => {'update': update};

  static JsonMap text(String text, {String? messageId}) => update({
    'sessionUpdate': 'agent_message_chunk',
    'messageId': ?messageId,
    'content': {'type': 'text', 'text': text},
  });

  static JsonMap thought(String text) => update({
    'sessionUpdate': 'agent_thought_chunk',
    'content': {'type': 'text', 'text': text},
  });

  static JsonMap tool(
    String id,
    String title, {
    String kind = 'other',
    String status = 'pending',
    List<JsonMap>? content,
    List<JsonMap>? locations,
    Object? rawInput,
  }) => update({
    'sessionUpdate': 'tool_call',
    'toolCallId': id,
    'title': title,
    'kind': kind,
    'status': status,
    'content': ?content,
    'locations': ?locations,
    'rawInput': ?rawInput,
  });

  static JsonMap toolUpdate(
    String id, {
    String? status,
    List<JsonMap>? content,
    String? title,
  }) => update({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    'status': ?status,
    'content': ?content,
    'title': ?title,
  });

  /// Tool content: a diff (`oldText` null = new file).
  static JsonMap diff(String path, String? oldText, String newText) => {
    'type': 'diff',
    'path': path,
    'oldText': oldText,
    'newText': newText,
  };

  /// Tool content: text output.
  static JsonMap output(String text) => {
    'type': 'content',
    'content': {'type': 'text', 'text': text},
  };

  /// [entries]: (content, status) pairs.
  static JsonMap plan(List<(String, String)> entries) => update({
    'sessionUpdate': 'plan',
    'entries': [
      for (final (content, status) in entries)
        {'content': content, 'priority': 'medium', 'status': status},
    ],
  });

  /// Asks permission and waits; `cancelled` ends the turn as cancelled.
  static JsonMap permission(
    String toolCallId,
    String title, {
    String kind = 'edit',
    List<JsonMap> options = claudeOptions,
  }) => {
    'permission': {
      'toolCall': {'toolCallId': toolCallId, 'title': title, 'kind': kind},
      'options': options,
    },
  };

  /// Sends `elicitation/create` with [request] (+ sessionId) and waits.
  static JsonMap ask(JsonMap request) => {'ask': request};

  static JsonMap completeAsk(String elicitationId) => {
    'completeAsk': elicitationId,
  };

  /// Waits [ms], or less if the turn is cancelled.
  static JsonMap sleep(int ms) => {'sleep': ms};

  /// Waits for `session/cancel`, then ends the turn as cancelled.
  static JsonMap waitCancel() => {'waitCancel': true};

  /// Never answers the prompt, even after `session/cancel`.
  static JsonMap hang() => {'hang': true};

  /// The agent exits with [code] in the middle of the turn.
  static JsonMap exit(int code) => {'exit': code};

  /// Writes [line] to stdout as it is (not JSON-RPC).
  static JsonMap raw(String line) => {'raw': line};

  /// An agent message of [chars] characters on one line.
  static JsonMap bigText(int chars) => {'bigText': chars};

  static JsonMap stderr(String text) => {'stderr': text};

  /// Writes a file under the agent's cwd, like an agent editing with a tool.
  static JsonMap write(String path, String text) => {
    'write': {'path': path, 'text': text},
  };

  static JsonMap delete(String path) => {'delete': path};

  /// Ends the turn with [reason] (`end_turn`, `refusal`, …).
  static JsonMap stop(String reason) => {'stop': reason};

  /// Answers the prompt with a JSON-RPC error.
  static JsonMap error(int code, String message) => {
    'error': {'code': code, 'message': message},
  };
}
