import 'acp_content.dart';
import 'acp_json.dart';
import 'acp_types.dart';
import 'json_rpc.dart';

/// What a tool call does; picks its card (spec §4.2).
enum ToolKind {
  read('read'),
  edit('edit'),
  delete('delete'),
  move('move'),
  search('search'),
  execute('execute'),
  think('think'),
  fetch('fetch'),
  switchMode('switch_mode'),
  other('other');

  const ToolKind(this.wire);

  final String wire;

  /// Null when not sent; an unknown kind is [other].
  static ToolKind? parse(String? wire) {
    if (wire == null) return null;
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return other;
  }
}

enum ToolCallStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  failed('failed');

  const ToolCallStatus(this.wire);

  final String wire;

  /// Null when not sent or unknown.
  static ToolCallStatus? parse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Something a tool call shows: output, a diff, or an agent terminal.
sealed class ToolContent with Redacted {
  const ToolContent();

  static ToolContent fromJson(JsonMap j) => switch (readString(j, 'type')) {
    'content' => ToolContentBlock(
      ContentBlock.fromJson(readMap(j, 'content') ?? const {}),
    ),
    'diff' => ToolDiff(
      path: readString(j, 'path') ?? '',
      oldText: readString(j, 'oldText'),
      newText: readString(j, 'newText') ?? '',
    ),
    'terminal' => ToolTerminal(readString(j, 'terminalId') ?? ''),
    final type => ToolContentOther(type),
  };
}

final class ToolContentBlock extends ToolContent {
  const ToolContentBlock(this.block);

  final ContentBlock block;
}

/// A file edit; a null [oldText] means the file is new (card "Tạo").
final class ToolDiff extends ToolContent {
  const ToolDiff({required this.path, this.oldText, required this.newText});

  final String path;
  final String? oldText;
  final String newText;
}

/// An agent-side terminal. ShellX offers none (D1), so it is not drawn.
final class ToolTerminal extends ToolContent {
  const ToolTerminal(this.terminalId);

  final String terminalId;
}

final class ToolContentOther extends ToolContent {
  const ToolContentOther(this.type);

  final String? type;
}

final class ToolLocation with Redacted {
  const ToolLocation(this.path, [this.line]);

  final String path;
  final int? line;
}

/// What a `tool_call` or `tool_call_update` says about one call; null means
/// "not sent". In an update, [content] and [locations] replace whole lists.
final class ToolCallFields with Redacted {
  const ToolCallFields({
    this.title,
    this.name,
    this.kind,
    this.status,
    this.content,
    this.locations,
    this.rawInput,
    this.rawOutput,
  });

  static ToolCallFields fromJson(JsonMap j) => ToolCallFields(
    title: readString(j, 'title'),
    name: readString(j, 'name'),
    kind: ToolKind.parse(readString(j, 'kind')),
    status: ToolCallStatus.parse(readString(j, 'status')),
    content: readList(
      j,
      'content',
    )?.whereType<JsonMap>().map(ToolContent.fromJson).toList(),
    locations: readList(j, 'locations')
        ?.whereType<JsonMap>()
        .map(
          (l) => ToolLocation(readString(l, 'path') ?? '', readInt(l, 'line')),
        )
        .toList(),
    rawInput: j['rawInput'],
    rawOutput: j['rawOutput'],
  );

  final String? title;
  final String? name;
  final ToolKind? kind;
  final ToolCallStatus? status;
  final List<ToolContent>? content;
  final List<ToolLocation>? locations;
  final Object? rawInput;
  final Object? rawOutput;

  /// These fields, with every field [update] sent replacing its own.
  ToolCallFields merge(ToolCallFields update) => ToolCallFields(
    title: update.title ?? title,
    name: update.name ?? name,
    kind: update.kind ?? kind,
    status: update.status ?? status,
    content: update.content ?? content,
    locations: update.locations ?? locations,
    rawInput: update.rawInput ?? rawInput,
    rawOutput: update.rawOutput ?? rawOutput,
  );
}

enum PlanStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const PlanStatus(this.wire);

  final String wire;

  static PlanStatus parse(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => pending);
}

final class PlanEntry with Redacted {
  const PlanEntry({
    required this.content,
    required this.status,
    this.priority = 'medium',
  });

  static PlanEntry? fromJson(JsonMap j) {
    final content = readString(j, 'content');
    if (content == null) return null;
    return PlanEntry(
      content: content,
      status: PlanStatus.parse(readString(j, 'status')),
      priority: readString(j, 'priority') ?? 'medium',
    );
  }

  final String content;
  final PlanStatus status;

  /// `high`, `medium` or `low`.
  final String priority;
}

/// A `/command` the agent offers (spec D16).
final class AvailableCommand with Redacted {
  const AvailableCommand({
    required this.name,
    this.description = '',
    this.hint,
  });

  static AvailableCommand? fromJson(JsonMap j) {
    final name = readString(j, 'name');
    if (name == null) return null;
    final input = readMap(j, 'input');
    return AvailableCommand(
      name: name,
      description: readString(j, 'description') ?? '',
      hint: input == null ? null : readString(input, 'hint'),
    );
  }

  final String name;
  final String description;
  final String? hint;
}

/// Context use (`usage_update`, the composer's "Ngữ cảnh 16%").
final class Usage with Redacted {
  const Usage({
    required this.used,
    required this.size,
    this.costAmount,
    this.costCurrency,
  });

  final int used;
  final int size;
  final double? costAmount;
  final String? costCurrency;

  int get percent => size <= 0 ? 0 : (used * 100 / size).round().clamp(0, 100);
}

/// One `session/update`. Unknown kinds (including `notice` and
/// `compaction_*`, which ShellX does not advertise) are [UnknownUpdate].
sealed class SessionUpdate with Redacted {
  const SessionUpdate();

  static SessionUpdate fromJson(JsonMap j) {
    final kind = readString(j, 'sessionUpdate');
    switch (kind) {
      case 'user_message_chunk':
      case 'agent_message_chunk':
      case 'agent_thought_chunk':
        final content = readMap(j, 'content');
        if (content == null) return UnknownUpdate(kind);
        final block = ContentBlock.fromJson(content);
        final messageId = readString(j, 'messageId');
        return switch (kind) {
          'user_message_chunk' => UserMessageChunk(block, messageId: messageId),
          'agent_message_chunk' => AgentMessageChunk(
            block,
            messageId: messageId,
          ),
          _ => AgentThoughtChunk(block, messageId: messageId),
        };
      case 'tool_call':
      case 'tool_call_update':
        final id = readString(j, 'toolCallId');
        if (id == null) return UnknownUpdate(kind);
        final fields = ToolCallFields.fromJson(j);
        return kind == 'tool_call'
            ? ToolCallStarted(id, fields)
            : ToolCallUpdated(id, fields);
      case 'plan':
        return PlanUpdated(
          readMaps(j, 'entries').map(PlanEntry.fromJson).nonNulls.toList(),
        );
      case 'available_commands_update':
        return CommandsUpdated(
          readMaps(
            j,
            'availableCommands',
          ).map(AvailableCommand.fromJson).nonNulls.toList(),
        );
      case 'current_mode_update':
        final id = readString(j, 'currentModeId');
        return id == null ? UnknownUpdate(kind) : ModeUpdated(id);
      case 'config_option_update':
        return ConfigUpdated(readConfigOptions(j, 'configOptions'));
      case 'session_info_update':
        return SessionInfoUpdated(
          hasTitle: j.containsKey('title'),
          title: readString(j, 'title'),
          updatedAt: readString(j, 'updatedAt'),
        );
      case 'usage_update':
        final used = readInt(j, 'used');
        final size = readInt(j, 'size');
        if (used == null || size == null) return UnknownUpdate(kind);
        final cost = readMap(j, 'cost');
        return UsageUpdated(
          Usage(
            used: used,
            size: size,
            costAmount: cost == null
                ? null
                : readNum(cost, 'amount')?.toDouble(),
            costCurrency: cost == null ? null : readString(cost, 'currency'),
          ),
        );
      default:
        return UnknownUpdate(kind);
    }
  }
}

final class UserMessageChunk extends SessionUpdate {
  const UserMessageChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class AgentMessageChunk extends SessionUpdate {
  const AgentMessageChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class AgentThoughtChunk extends SessionUpdate {
  const AgentThoughtChunk(this.content, {this.messageId});

  final ContentBlock content;
  final String? messageId;
}

final class ToolCallStarted extends SessionUpdate {
  const ToolCallStarted(this.toolCallId, this.fields);

  final String toolCallId;
  final ToolCallFields fields;
}

final class ToolCallUpdated extends SessionUpdate {
  const ToolCallUpdated(this.toolCallId, this.fields);

  final String toolCallId;
  final ToolCallFields fields;
}

final class PlanUpdated extends SessionUpdate {
  const PlanUpdated(this.entries);

  final List<PlanEntry> entries;
}

final class CommandsUpdated extends SessionUpdate {
  const CommandsUpdated(this.commands);

  final List<AvailableCommand> commands;
}

final class ModeUpdated extends SessionUpdate {
  const ModeUpdated(this.currentModeId);

  final String currentModeId;
}

final class ConfigUpdated extends SessionUpdate {
  const ConfigUpdated(this.options);

  final List<ConfigOption> options;
}

final class SessionInfoUpdated extends SessionUpdate {
  const SessionInfoUpdated({
    required this.hasTitle,
    this.title,
    this.updatedAt,
  });

  /// `title` was sent; a null [title] then clears the title.
  final bool hasTitle;
  final String? title;
  final String? updatedAt;
}

final class UsageUpdated extends SessionUpdate {
  const UsageUpdated(this.usage);

  final Usage usage;
}

final class UnknownUpdate extends SessionUpdate {
  const UnknownUpdate(this.kind);

  final String? kind;
}
