/// The desktop host for AI sessions (`dart:io`): environment, agents,
/// processes, checkpoints and the runtime (spec D6, D12). The phone does not
/// import this library.
library;

export 'src/host/agent_catalog.dart';
export 'src/host/agent_process.dart';
export 'src/host/agent_resolver.dart';
export 'src/host/ai_host.dart';
export 'src/host/ai_runtime.dart';
export 'src/host/broad_folder.dart';
export 'src/host/byte_ring.dart';
export 'src/host/checkpoint_store.dart';
export 'src/host/git_locator.dart';
export 'src/host/git_runner.dart';
export 'src/host/login_shell_env.dart';
export 'src/host/probe.dart';
export 'src/host/process_snapshot.dart';
export 'src/host/running_agents.dart';
export 'src/host/serial_queue.dart';
