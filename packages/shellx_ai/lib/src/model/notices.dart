import 'package:shellx_acp/shellx_acp.dart';

import 'changes.dart';

/// Why an agent could not start (spec §6).
enum StartFailure { spawn, timeout, protocol, session }

/// A card in the conversation (spec §4.5).
sealed class AiNotice with Redacted {
  const AiNotice();
}

/// `-32000`: sign in with one of [methods] (spec D8).
final class LoginNeeded extends AiNotice {
  const LoginNeeded(this.methods);

  final List<AuthMethod> methods;
}

/// The agent needs Node [required] or newer; [found] is what is installed.
final class NodeMissing extends AiNotice {
  const NodeMissing({required this.required, this.found});

  final int required;
  final String? found;
}

/// The adapter is not installed (or not at the pinned version).
final class AgentNotInstalled extends AiNotice {
  const AgentNotInstalled({this.canInstall = true});

  /// False when npm was not found next to node.
  final bool canInstall;
}

/// A PATH or custom agent command was not found.
final class AgentMissing extends AiNotice {
  const AgentMissing(this.command, {this.shimOnly = false});

  final String command;

  /// Found only as a `.cmd`/`.bat` shim on Windows, which ShellX does not run.
  final bool shimOnly;
}

final class AgentExited extends AiNotice {
  const AgentExited(this.exitCode);

  final int exitCode;
}

/// The agent wrote output ShellX cannot read: more than 20 bad lines in a
/// row, or one line over 64 MiB (spec §6). ShellX stopped it.
final class AgentOutputInvalid extends AiNotice {
  const AgentOutputInvalid(this.reason);

  final ConnectionCloseReason reason;
}

final class StartFailed extends AiNotice {
  const StartFailed(this.reason);

  final StartFailure reason;
}

/// The agent cannot load the old session; a new one was started (D14).
final class CannotResume extends AiNotice {
  const CannotResume();
}

final class FolderMissing extends AiNotice {
  const FolderMissing();
}

/// Undo is off for the project, or only for this turn when [turnOnly].
final class UndoUnavailable extends AiNotice {
  const UndoUnavailable(this.reason, {this.turnOnly = false});

  final UndoOff reason;
  final bool turnOnly;
}
