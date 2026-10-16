/// How ShellX starts an agent (spec D6, D23).
sealed class AgentLaunch {
  const AgentLaunch();
}

/// An npm adapter installed once under `<support>/ai/agents/<id>` at a
/// pinned version and run with node (no npx, no shell).
final class NpmLaunch extends AgentLaunch {
  const NpmLaunch({
    required this.package,
    required this.version,
    required this.bin,
    this.args = const [],
    required this.minNode,
  });

  final String package;
  final String version;

  /// The package's bin script; the installed `package.json` wins.
  final String bin;
  final List<String> args;
  final int minNode;
}

/// A command found on the login PATH.
final class PathLaunch extends AgentLaunch {
  const PathLaunch(this.command, [this.args = const []]);

  final String command;
  final List<String> args;
}

/// An agent the user added (Settings › Agents, spec D7).
final class CustomLaunch extends AgentLaunch {
  const CustomLaunch({
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  final String command;
  final List<String> args;
  final Map<String, String> env;
}

final class AgentSpec {
  const AgentSpec({required this.id, required this.name, required this.launch});

  final String id;

  /// Shown in menus; "Claude", never "Claude Code" (spec D21).
  final String name;
  final AgentLaunch launch;
}

/// The agents ShellX knows, in default order (spec D23). Bump a pin only
/// after testing it (spec D6).
const kKnownAgents = <AgentSpec>[
  AgentSpec(
    id: 'claude',
    name: 'Claude',
    launch: NpmLaunch(
      package: '@agentclientprotocol/claude-agent-acp',
      version: '0.90.0',
      bin: 'dist/index.js',
      minNode: 22,
    ),
  ),
  AgentSpec(
    id: 'codex',
    name: 'Codex',
    launch: NpmLaunch(
      package: '@agentclientprotocol/codex-acp',
      version: '2.2.2',
      bin: 'dist/index.js',
      minNode: 20,
    ),
  ),
  AgentSpec(
    id: 'gemini',
    name: 'Gemini CLI',
    launch: NpmLaunch(
      package: '@google/gemini-cli',
      version: '0.64.0',
      bin: 'bundle/gemini.js',
      args: ['--acp'],
      minNode: 20,
    ),
  ),
  AgentSpec(
    id: 'opencode',
    name: 'OpenCode',
    launch: PathLaunch('opencode', ['acp']),
  ),
];

/// A command line to start without a shell: an agent, its terminal login
/// (spec D8) or an adapter install (spec D7).
final class AgentCommand {
  const AgentCommand({
    required this.executable,
    this.args = const [],
    this.environment = const {},
    this.workingDirectory,
  });

  final String executable;
  final List<String> args;

  /// The whole environment: the child gets nothing else.
  final Map<String, String> environment;

  /// Installs run in their prefix (create it first); agents run in the
  /// session folder instead.
  final String? workingDirectory;

  /// This command plus a login method's args and env (spec D8).
  AgentCommand withArgs(
    List<String> extraArgs, [
    Map<String, String> extraEnv = const {},
  ]) => AgentCommand(
    executable: executable,
    args: [...args, ...extraArgs],
    environment: {...environment, ...extraEnv},
    workingDirectory: workingDirectory,
  );

  @override
  String toString() => '…';
}

/// Can the agent start (spec D7 statuses)?
sealed class AgentReadiness {
  const AgentReadiness();
}

final class AgentReady extends AgentReadiness {
  const AgentReady(this.command);

  final AgentCommand command;
}

/// "Thiếu Node 22": [found] is `node --version` (null: no node at all).
final class AgentNeedsNode extends AgentReadiness {
  const AgentNeedsNode({required this.required, this.found});

  final int required;
  final String? found;
}

/// "Chưa cài": [install] runs in the run sheet; null when npm is missing.
final class AgentNeedsInstall extends AgentReadiness {
  const AgentNeedsInstall(this.install);

  final AgentCommand? install;
}

/// A PATH or custom command that is not there ([shimOnly]: only a
/// `.cmd`/`.bat` on Windows).
final class AgentNotFound extends AgentReadiness {
  const AgentNotFound(this.command, {this.shimOnly = false});

  final String command;
  final bool shimOnly;
}
