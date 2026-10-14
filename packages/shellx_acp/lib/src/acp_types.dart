import 'acp_json.dart';
import 'acp_updates.dart';
import 'json_rpc.dart';

/// `clientInfo` / `agentInfo`.
final class Implementation with Redacted {
  const Implementation({required this.name, required this.version, this.title});

  static Implementation? fromJson(JsonMap? j) {
    final name = j == null ? null : readString(j, 'name');
    if (name == null) return null;
    return Implementation(
      name: name,
      version: readString(j!, 'version') ?? '',
      title: readString(j, 'title'),
    );
  }

  final String name;
  final String version;
  final String? title;
}

final class PromptCapabilities with Redacted {
  const PromptCapabilities({
    this.image = false,
    this.audio = false,
    this.embeddedContext = false,
  });

  static PromptCapabilities fromJson(JsonMap j) => PromptCapabilities(
    image: readBool(j, 'image') ?? false,
    audio: readBool(j, 'audio') ?? false,
    embeddedContext: readBool(j, 'embeddedContext') ?? false,
  );

  final bool image;
  final bool audio;
  final bool embeddedContext;
}

/// What the agent supports, from `initialize`.
final class AgentCapabilities with Redacted {
  const AgentCapabilities({
    this.loadSession = false,
    this.prompt = const PromptCapabilities(),
    this.listSessions = false,
    this.resumeSession = false,
    this.closeSession = false,
  });

  static AgentCapabilities fromJson(JsonMap j) {
    final s = readMap(j, 'sessionCapabilities') ?? const <String, Object?>{};
    return AgentCapabilities(
      loadSession: readBool(j, 'loadSession') ?? false,
      prompt: PromptCapabilities.fromJson(
        readMap(j, 'promptCapabilities') ?? const {},
      ),
      listSessions: s['list'] is JsonMap,
      resumeSession: s['resume'] is JsonMap,
      closeSession: s['close'] is JsonMap,
    );
  }

  /// `session/load` replays a past session (spec D14).
  final bool loadSession;
  final PromptCapabilities prompt;

  /// `session/list` is offered (spec D15).
  final bool listSessions;
  final bool resumeSession;
  final bool closeSession;
}

/// One way to sign in, from `initialize` (spec D8). Names are the agent's
/// and shown as they are.
sealed class AuthMethod with Redacted {
  const AuthMethod({required this.id, required this.name, this.description});

  static AuthMethod? fromJson(JsonMap j) {
    final id = readString(j, 'id');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    final description = readString(j, 'description');
    return switch (readString(j, 'type')) {
      null ||
      'agent' => AuthMethodAgent(id: id, name: name, description: description),
      'terminal' => AuthMethodTerminal(
        id: id,
        name: name,
        description: description,
        args: readStrings(j, 'args'),
        env: {
          for (final e
              in (readMap(j, 'env') ?? const <String, Object?>{}).entries)
            if (e.value case final String v) e.key: v,
        },
      ),
      final type => AuthMethodOther(
        id: id,
        name: name,
        description: description,
        type: type,
      ),
    };
  }

  final String id;
  final String name;
  final String? description;
}

/// The agent signs in by itself after `authenticate {methodId}`.
final class AuthMethodAgent extends AuthMethod {
  const AuthMethodAgent({
    required super.id,
    required super.name,
    super.description,
  });
}

/// ShellX runs the agent's own command plus [args] and [env] in a run sheet;
/// exit 0 means signed in. ShellX never calls `authenticate` for it and
/// never reads what the run sheet shows (spec D8, §5).
final class AuthMethodTerminal extends AuthMethod {
  const AuthMethodTerminal({
    required super.id,
    required super.name,
    super.description,
    this.args = const [],
    this.env = const {},
  });

  final List<String> args;
  final Map<String, String> env;
}

/// A sign-in kind this version does not know: listed, not offered.
final class AuthMethodOther extends AuthMethod {
  const AuthMethodOther({
    required super.id,
    required super.name,
    super.description,
    required this.type,
  });

  final String type;
}

final class InitializeResult with Redacted {
  const InitializeResult({
    required this.protocolVersion,
    this.capabilities = const AgentCapabilities(),
    this.authMethods = const [],
    this.agentInfo,
  });

  static InitializeResult fromJson(JsonMap j) => InitializeResult(
    protocolVersion: readInt(j, 'protocolVersion') ?? 0,
    capabilities: AgentCapabilities.fromJson(
      readMap(j, 'agentCapabilities') ?? const {},
    ),
    authMethods: readMaps(
      j,
      'authMethods',
    ).map(AuthMethod.fromJson).nonNulls.toList(),
    agentInfo: Implementation.fromJson(readMap(j, 'agentInfo')),
  );

  final int protocolVersion;
  final AgentCapabilities capabilities;
  final List<AuthMethod> authMethods;
  final Implementation? agentInfo;
}

enum ConfigKind { select, boolean, other }

/// One value of a select option; [group] is its group's display name.
final class ConfigChoice with Redacted {
  const ConfigChoice({
    required this.value,
    required this.name,
    this.description,
    this.group,
  });

  final String value;
  final String name;
  final String? description;
  final String? group;
}

/// A session setting the agent offers (`configOptions`, spec D11): mode,
/// model, thought level… Grouped values are flattened into [choices].
final class ConfigOption with Redacted {
  const ConfigOption({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.category,
    this.currentValue,
    this.choices = const [],
  });

  static ConfigOption? fromJson(JsonMap j) {
    final id = readString(j, 'id');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    final kind = switch (readString(j, 'type')) {
      'select' => ConfigKind.select,
      'boolean' => ConfigKind.boolean,
      _ => ConfigKind.other,
    };
    final choices = <ConfigChoice>[];
    void add(JsonMap c, String? group) {
      final value = readString(c, 'value');
      final label = readString(c, 'name');
      if (value == null || label == null) return;
      choices.add(
        ConfigChoice(
          value: value,
          name: label,
          description: readString(c, 'description'),
          group: group,
        ),
      );
    }

    for (final o in readMaps(j, 'options')) {
      if (readList(o, 'options') != null) {
        for (final c in readMaps(o, 'options')) {
          add(c, readString(o, 'name'));
        }
      } else {
        add(o, null);
      }
    }
    return ConfigOption(
      id: id,
      name: name,
      kind: kind,
      description: readString(j, 'description'),
      category: readString(j, 'category'),
      currentValue: switch (kind) {
        ConfigKind.select => readString(j, 'currentValue'),
        ConfigKind.boolean => readBool(j, 'currentValue'),
        ConfigKind.other => j['currentValue'],
      },
      choices: choices,
    );
  }

  final String id;
  final String name;
  final ConfigKind kind;
  final String? description;

  /// `mode`, `model`, `model_config`, `thought_level` or an agent's own.
  final String? category;

  /// A [String] for [ConfigKind.select], a [bool] for [ConfigKind.boolean].
  final Object? currentValue;
  final List<ConfigChoice> choices;

  ConfigOption withValue(Object? value) => ConfigOption(
    id: id,
    name: name,
    kind: kind,
    description: description,
    category: category,
    currentValue: value,
    choices: choices,
  );
}

/// The valid options in list [key] of [j].
List<ConfigOption> readConfigOptions(JsonMap j, String key) =>
    readMaps(j, key).map(ConfigOption.fromJson).nonNulls.toList();

final class SessionMode with Redacted {
  const SessionMode({required this.id, required this.name, this.description});

  final String id;
  final String name;
  final String? description;
}

/// Legacy modes (`modes`); agents with `configOptions` use those (spec D11).
final class SessionModes with Redacted {
  const SessionModes({required this.currentModeId, required this.available});

  static SessionModes? fromJson(JsonMap? j) {
    final current = j == null ? null : readString(j, 'currentModeId');
    if (current == null) return null;
    return SessionModes(
      currentModeId: current,
      available: [
        for (final m in readMaps(j!, 'availableModes'))
          if ((readString(m, 'id'), readString(m, 'name')) case (
            final String id,
            final String name,
          ))
            SessionMode(
              id: id,
              name: name,
              description: readString(m, 'description'),
            ),
      ],
    );
  }

  final String currentModeId;
  final List<SessionMode> available;

  SessionModes withCurrent(String id) =>
      SessionModes(currentModeId: id, available: available);
}

final class NewSessionResult with Redacted {
  const NewSessionResult({
    required this.sessionId,
    this.configOptions,
    this.modes,
  });

  static NewSessionResult fromJson(JsonMap j) => NewSessionResult(
    sessionId: readString(j, 'sessionId') ?? '',
    configOptions: j['configOptions'] is List
        ? readConfigOptions(j, 'configOptions')
        : null,
    modes: SessionModes.fromJson(readMap(j, 'modes')),
  );

  /// Empty when the agent sent none (a protocol error for the caller).
  final String sessionId;
  final List<ConfigOption>? configOptions;
  final SessionModes? modes;
}

final class LoadSessionResult with Redacted {
  const LoadSessionResult({this.configOptions, this.modes});

  static LoadSessionResult fromJson(JsonMap j) => LoadSessionResult(
    configOptions: j['configOptions'] is List
        ? readConfigOptions(j, 'configOptions')
        : null,
    modes: SessionModes.fromJson(readMap(j, 'modes')),
  );

  final List<ConfigOption>? configOptions;
  final SessionModes? modes;
}

/// One entry of `session/list` (spec D15).
final class SessionSummary with Redacted {
  const SessionSummary({
    required this.sessionId,
    required this.cwd,
    this.title,
    this.updatedAt,
  });

  final String sessionId;
  final String cwd;
  final String? title;

  /// ISO 8601, as the agent sent it.
  final String? updatedAt;
}

final class ListSessionsResult with Redacted {
  const ListSessionsResult({this.sessions = const [], this.nextCursor});

  static ListSessionsResult fromJson(JsonMap j) => ListSessionsResult(
    sessions: [
      for (final s in readMaps(j, 'sessions'))
        if (readString(s, 'sessionId') case final String id)
          SessionSummary(
            sessionId: id,
            cwd: readString(s, 'cwd') ?? '',
            title: readString(s, 'title'),
            updatedAt: readString(s, 'updatedAt'),
          ),
    ],
    nextCursor: readString(j, 'nextCursor'),
  );

  final List<SessionSummary> sessions;
  final String? nextCursor;
}

/// Why a turn ended (`session/prompt` result).
enum StopReason {
  endTurn('end_turn'),
  maxTokens('max_tokens'),
  maxTurnRequests('max_turn_requests'),
  refusal('refusal'),
  cancelled('cancelled'),

  /// A reason this version does not know.
  other('');

  const StopReason(this.wire);

  final String wire;

  static StopReason parse(String? wire) {
    for (final r in values) {
      if (r != other && r.wire == wire) return r;
    }
    return other;
  }
}

/// The kind of a permission option; the label comes from it (spec D10).
enum PermissionKind {
  allowOnce('allow_once'),
  allowAlways('allow_always'),
  rejectOnce('reject_once'),
  rejectAlways('reject_always'),
  other('');

  const PermissionKind(this.wire);

  final String wire;

  bool get isReject => this == rejectOnce || this == rejectAlways;

  static PermissionKind parse(String? wire) {
    for (final k in values) {
      if (k != other && k.wire == wire) return k;
    }
    return other;
  }
}

final class PermissionOption with Redacted {
  const PermissionOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  static PermissionOption? fromJson(JsonMap j) {
    final id = readString(j, 'optionId');
    final name = readString(j, 'name');
    if (id == null || name == null) return null;
    return PermissionOption(
      optionId: id,
      name: name,
      kind: PermissionKind.parse(readString(j, 'kind')),
    );
  }

  final String optionId;

  /// The agent's own words (shown under the kind label, spec D10).
  final String name;
  final PermissionKind kind;
}

/// `session/request_permission`: options in the agent's order (keys 1–9).
final class PermissionRequest with Redacted {
  const PermissionRequest({
    required this.sessionId,
    required this.toolCallId,
    required this.toolCall,
    required this.options,
  });

  static PermissionRequest fromJson(JsonMap j) {
    final call = readMap(j, 'toolCall') ?? const <String, Object?>{};
    return PermissionRequest(
      sessionId: readString(j, 'sessionId') ?? '',
      toolCallId: readString(call, 'toolCallId') ?? '',
      toolCall: ToolCallFields.fromJson(call),
      options: readMaps(
        j,
        'options',
      ).map(PermissionOption.fromJson).nonNulls.toList(),
    );
  }

  final String sessionId;
  final String toolCallId;
  final ToolCallFields toolCall;
  final List<PermissionOption> options;
}

/// The answer to a permission request.
sealed class PermissionOutcome with Redacted {
  const PermissionOutcome();

  JsonMap toJson();
}

final class PermissionSelected extends PermissionOutcome {
  const PermissionSelected(this.optionId);

  final String optionId;

  @override
  JsonMap toJson() => {
    'outcome': {'outcome': 'selected', 'optionId': optionId},
  };
}

/// The turn was cancelled while the question was open (ACP requires this
/// answer for every open request after `session/cancel`).
final class PermissionCancelled extends PermissionOutcome {
  const PermissionCancelled();

  @override
  JsonMap toJson() => {
    'outcome': {'outcome': 'cancelled'},
  };
}

/// An MCP server ShellX could hand to a session (none in V2-1).
final class McpServerStdio with Redacted {
  const McpServerStdio({
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;

  JsonMap toJson() => {
    'name': name,
    'command': command,
    'args': args,
    'env': [
      for (final e in env.entries) {'name': e.key, 'value': e.value},
    ],
  };
}
